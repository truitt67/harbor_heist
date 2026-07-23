#!/usr/bin/env python3
"""
coverage_report.py — Static exported-function coverage analyzer for Harbor Heist.

TASK 18.13 (k5wz.13): Coverage measurement + enforcement gate.

APPROACH (decision recorded per task deliverable #1):
  (a) luacov under lune — NOT available (not installed); rejected.
  (b) require-wrapper instrumentation — works for pure bucket only; 9 of 12
      in-scope modules are DataModel-bound and can't run on this machine.
  (c) Static export-reference analyzer — CHOSEN. Parses each module source
      for `function ModuleName.xxx` declarations, then scans ALL spec files
      for references to `ModuleName.xxx`. Works for every module on any
      machine without execution. Produces a real, auditable, line-level
      number. Lightest approach with zero dependencies.

WHAT IT MEASURES: "Did any spec file reference this exported function by name?"
This is function-call COVERAGE (not line coverage) — the task explicitly asks
for "every exported function exercised at least once against the real
implementation." A spec that calls ModuleName.func(args) counts as covered.

LIMITATIONS (documented per task deliverable #4):
  - init() functions that only wire event handlers are counted as covered if
    any spec calls init() (which all service specs do). The real exercise of
    the wired handlers is asserted by the spec's test cases.
  - A reference in a comment would false-positive as covered. We mitigate by
    requiring the reference appear outside of a -- comment context. This is a
    heuristic; the report lists every covered function with the spec file +
    line so a human can audit.
  - DataModel-bound modules (test/specs/) can't execute on Linux, so this is
    a STATIC guarantee (the spec references the function). EPIC 19 (E2E)
    provides the runtime guarantee via actual execution.

USAGE:
  python3 scripts/coverage_report.py           # print report + write testlogs/coverage.txt
  python3 scripts/coverage_report.py --gate     # exit 1 if any module below threshold
  python3 scripts/coverage_report.py --json     # machine-readable output

THRESHOLDS (per k5wz.13 deliverable #3):
  100% — GameConfig, DataManager, AntiExploitService, QuestService,
         FishInventoryService, ShopService
  >=90% — AquariumService, RaidService, FishingService, CollectionService,
          OnboardingService, AuditLogService
"""

import os
import re
import sys
import json
from pathlib import Path

# ─── Configuration ───────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = PROJECT_ROOT / "src"
TEST_DIR = PROJECT_ROOT / "test"
REPORT_PATH = PROJECT_ROOT / "testlogs" / "coverage.txt"
EXCEPTIONS_PATH = PROJECT_ROOT / "test" / "coverage_exceptions.txt"

# Module registry: (relative source path, module name, required coverage %)
# Ordered: 100% modules first, then >=90% modules.
MODULES = [
    # 100% required
    ("src/shared/GameConfig.lua", "GameConfig", 100),
    ("src/server/DataManager.lua", "DataManager", 100),
    ("src/server/AntiExploitService.lua", "AntiExploitService", 100),
    ("src/server/QuestService.lua", "QuestService", 100),
    ("src/server/FishInventoryService.lua", "FishInventoryService", 100),
    ("src/server/ShopService.lua", "ShopService", 100),
    # >=90% required
    ("src/server/AquariumService.lua", "AquariumService", 90),
    ("src/server/RaidService.lua", "RaidService", 90),
    ("src/server/FishingService.lua", "FishingService", 90),
    ("src/server/CollectionService.lua", "CollectionService", 90),
    ("src/server/OnboardingService.lua", "OnboardingService", 90),
    ("src/server/AuditLogService.lua", "AuditLogService", 90),
]

# Directories to scan for spec files
SPEC_DIRS = [
    TEST_DIR / "pure_specs",
    TEST_DIR / "specs",
]

# ─── Analysis ────────────────────────────────────────────────────────────────

# Matches top-level exported function declarations: `function ModuleName.funcName`
FUNC_DECL_RE = re.compile(r"^function\s+([A-Z]\w+)\.([A-Za-z_]\w*)", re.MULTILINE)


def find_exported_functions(source_path: Path, module_name: str) -> list[str]:
    """Return all exported function names declared in the module source."""
    text = source_path.read_text(encoding="utf-8")
    funcs = []
    for match in FUNC_DECL_RE.finditer(text):
        mod, func = match.group(1), match.group(2)
        if mod == module_name:
            funcs.append(func)
    return funcs


def strip_comments_and_strings(lua_source: str) -> str:
    """
    Remove Lua comments (-- single line, --[[ block]]) from source so that
    references inside comments don't false-positive as coverage.

    String literals are left intact — function calls are never inside strings
    in well-formed spec code, and stripping strings risks mangling patterns
    that contain function-like syntax.
    """
    result = []
    lines = lua_source.split("\n")
    in_block_comment = False
    for line in lines:
        if in_block_comment:
            if "--]]" in line:
                in_block_comment = False
                idx = line.index("--]]") + 4
                result.append(line[idx:])
            else:
                result.append("")
            continue
        # Check for block comment start
        if "--[[" in line:
            before = line[: line.index("--[[")]
            after_part = line[line.index("--[[") + 4 :]
            if "--]]" in after_part:
                # Single-line block comment
                after = after_part[after_part.index("--]]") + 4 :]
                result.append(before + after)
            else:
                in_block_comment = True
                result.append(before)
            continue
        # Strip single-line comments (but not -- inside strings — heuristic:
        # split on -- and take the first part; rare false-negative is acceptable)
        if "--" in line:
            # Avoid stripping URL-like -- (e.g. http://). Simple heuristic:
            # only strip if -- is not preceded by :
            stripped = re.sub(r"(?<!:)--.*$", "", line)
            result.append(stripped)
        else:
            result.append(line)
    return "\n".join(result)


def find_module_aliases(module_name: str, spec_texts: list[tuple[str, str]]) -> set[str]:
    """
    Detect local aliases for a module in spec files.

    Specs commonly do: `local DM = require("...DataManager")` then call
    `DM.save(...)`. We need to track these aliases so coverage detection
    matches the alias, not just the full module name.

    Patterns detected:
      local <Alias> = require("...<ModuleName>")
      local <Alias> = require(...<ModuleName>)
      local <Alias> = require(path:WaitForChild("<ModuleName>"))

    Returns a set of alias names (including the original module_name).
    """
    aliases = {module_name}
    # Match: local WORD = require( ... ModuleName )
    # The require path may be a string, a chain of WaitForChild, or a variable.
    alias_re = re.compile(
        rf'local\s+(\w+)\s*=\s*require\([^)]*\b{re.escape(module_name)}\b[^)]*\)'
    )
    for _spec_filename, spec_text in spec_texts:
        cleaned = strip_comments_and_strings(spec_text)
        for match in alias_re.finditer(cleaned):
            alias = match.group(1)
            if alias and alias != module_name:
                aliases.add(alias)
    return aliases


def scan_specs_for_function(module_name: str, func_name: str, spec_texts: list[tuple[str, str]], aliases: set[str] | None = None) -> list[tuple[str, int]]:
    """
    Search all spec file texts for references to module_name.func_name,
    including any local aliases (e.g. `local DM = require("...DataManager")`).
    Returns a list of (spec_filename, line_number) hits.
    """
    if aliases is None:
        aliases = {module_name}

    hits = []
    # Build a pattern that matches ANY known alias followed by .funcName
    alias_alt = "|".join(re.escape(a) for a in sorted(aliases, key=len, reverse=True))
    pattern = re.compile(rf"\b(?:{alias_alt})\.{re.escape(func_name)}\b")

    for spec_filename, spec_text in spec_texts:
        cleaned = strip_comments_and_strings(spec_text)
        for i, line in enumerate(cleaned.split("\n"), 1):
            if pattern.search(line):
                hits.append((spec_filename, i))
    return hits


def collect_spec_texts() -> list[tuple[str, str]]:
    """Read all spec files from both spec directories."""
    specs = []
    for spec_dir in SPEC_DIRS:
        if not spec_dir.exists():
            continue
        for spec_file in sorted(spec_dir.glob("*.spec.lua")):
            specs.append((str(spec_file.relative_to(PROJECT_ROOT)), spec_file.read_text(encoding="utf-8")))
    return specs


def load_exceptions() -> dict[str, str]:
    """
    Load coverage exceptions from test/coverage_exceptions.txt.
    Returns a dict mapping 'ModuleName.functionName' → 'reason'.
    """
    exceptions = {}
    if not EXCEPTIONS_PATH.exists():
        return exceptions
    text = EXCEPTIONS_PATH.read_text(encoding="utf-8")
    for line in text.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Format: ModuleName.functionName: reason text
        if ":" in line:
            key, reason = line.split(":", 1)
            key = key.strip()
            reason = reason.strip()
            if key and reason:
                exceptions[key] = reason
    return exceptions


def analyze_coverage() -> dict:
    """
    Analyze function-level coverage for all in-scope modules.
    Returns a structured report dict.
    """
    spec_texts = collect_spec_texts()
    exceptions = load_exceptions()
    report = {
        "modules": [],
        "summary": {
            "total_functions": 0,
            "total_covered": 0,
            "total_uncovered": 0,
            "total_exempted": 0,
            "modules_passing": 0,
            "modules_failing": 0,
        },
    }

    for rel_path, module_name, threshold in MODULES:
        source_path = PROJECT_ROOT / rel_path
        if not source_path.exists():
            report["modules"].append({
                "module": module_name,
                "path": rel_path,
                "threshold": threshold,
                "error": f"Source file not found: {rel_path}",
            })
            report["summary"]["modules_failing"] += 1
            continue

        exported = find_exported_functions(source_path, module_name)
        total = len(exported)
        covered_funcs = []
        uncovered_funcs = []
        exempted_funcs = []

        # Detect local aliases for this module across all specs
        aliases = find_module_aliases(module_name, spec_texts)

        for func_name in exported:
            # Check if this function is exempted
            exception_key = f"{module_name}.{func_name}"
            if exception_key in exceptions:
                exempted_funcs.append({
                    "function": func_name,
                    "reason": exceptions[exception_key],
                })
                continue  # exempted functions don't count against coverage

            hits = scan_specs_for_function(module_name, func_name, spec_texts, aliases)
            if hits:
                covered_funcs.append({"function": func_name, "hits": hits})
            else:
                uncovered_funcs.append({"function": func_name})

        # Coverage is computed over non-exempted functions only
        effective_total = total - len(exempted_funcs)
        covered = len(covered_funcs)
        uncovered = len(uncovered_funcs)
        pct = round((covered / effective_total * 100), 1) if effective_total > 0 else 100.0
        passed = pct >= threshold

        report["summary"]["total_functions"] += effective_total
        report["summary"]["total_covered"] += covered
        report["summary"]["total_uncovered"] += uncovered
        report["summary"]["total_exempted"] += len(exempted_funcs)
        if passed:
            report["summary"]["modules_passing"] += 1
        else:
            report["summary"]["modules_failing"] += 1

        report["modules"].append({
            "module": module_name,
            "path": rel_path,
            "threshold": threshold,
            "total_functions": total,
            "effective_functions": effective_total,
            "covered": covered,
            "uncovered": uncovered,
            "exempted": len(exempted_funcs),
            "coverage_pct": pct,
            "passed": passed,
            "covered_functions": covered_funcs,
            "uncovered_functions": uncovered_funcs,
            "exempted_functions": exempted_funcs,
        })

    report["summary"]["overall_coverage_pct"] = round(
        report["summary"]["total_covered"] / report["summary"]["total_functions"] * 100, 1
    ) if report["summary"]["total_functions"] > 0 else 0.0

    return report


def format_report(report: dict) -> str:
    """Format the coverage report as human-readable text."""
    lines = []
    lines.append("=" * 72)
    lines.append("HARBOR HEIST — Exported Function Coverage Report")
    lines.append("TASK 18.13 (k5wz.13) — Static export-reference analyzer")
    lines.append("=" * 72)
    lines.append("")

    s = report["summary"]
    lines.append(f"Overall: {s['total_covered']}/{s['total_functions']} functions "
                 f"({s['overall_coverage_pct']}%) — "
                 f"{s['total_exempted']} exempted — "
                 f"{s['modules_passing']} modules passing, {s['modules_failing']} failing")
    lines.append("")

    for mod in report["modules"]:
        if "error" in mod:
            lines.append(f"  ✗ {mod['module']}: ERROR — {mod['error']}")
            continue

        status = "✓" if mod["passed"] else "✗"
        exempt_note = f" ({mod['exempted']} exempted)" if mod["exempted"] > 0 else ""
        lines.append(f"  {status} {mod['module']:25s} {mod['covered']}/{mod['effective_functions']} "
                     f"({mod['coverage_pct']:5.1f}%)  threshold: {mod['threshold']}%{exempt_note}")

        if mod["uncovered_functions"]:
            for uf in mod["uncovered_functions"]:
                lines.append(f"      ✗ {mod['module']}.{uf['function']}")

        # Show exempted functions with their reasons (deliverable #3 requirement)
        if mod.get("exempted_functions"):
            for ef in mod["exempted_functions"]:
                lines.append(f"      ⓘ {mod['module']}.{ef['function']} — {ef['reason']}")

    lines.append("")
    lines.append("-" * 72)
    lines.append("METHODOLOGY: Static export-reference analysis. Each module source is")
    lines.append("parsed for `function ModuleName.xxx` declarations. All *.spec.lua files")
    lines.append("(test/pure_specs/ + test/specs/) are scanned for references to each")
    lines.append("function name outside of comment context. A reference counts as covered.")
    lines.append("")
    lines.append("This measures FUNCTION-CALL COVERAGE, not line coverage. It answers:")
    lines.append("'did any spec exercise this exported function at least once?'")
    lines.append("")
    lines.append("DataModel-bound specs (test/specs/) require Roblox Studio to execute;")
    lines.append("this analyzer provides a STATIC guarantee that the spec references the")
    lines.append("function. EPIC 19 (E2E) provides the runtime execution guarantee.")
    lines.append("=" * 72)

    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    as_json = "--json" in args
    gate_mode = "--gate" in args

    report = analyze_coverage()

    if as_json:
        print(json.dumps(report, indent=2))
    else:
        text = format_report(report)
        print(text)
        # Write report artifact
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(text + "\n", encoding="utf-8")
        print(f"\nReport written to: {REPORT_PATH}")

    if gate_mode:
        if report["summary"]["modules_failing"] > 0:
            print(f"\nGATE FAILED: {report['summary']['modules_failing']} module(s) below threshold")
            sys.exit(1)
        else:
            print("\nGATE PASSED: all modules meet coverage threshold")
            sys.exit(0)


if __name__ == "__main__":
    main()
