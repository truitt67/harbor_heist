# Semantic Text Contrast Matrix (WCAG Benchmark)

**Bead:** harborheist-ux45-workflow-clarity-etj2.4.3 (EPIC 45, WS-D)
**Status:** MEASURED — feeds remediation bead harborheist-ux45-workflow-clarity-etj2.4.4
**Date:** 2026-08-02 · **Author:** GoldenEagle-Aug2
**Method:** WCAG 2.x relative-luminance contrast math over UIPalette RGB
triples (single source of truth, `src/shared/UIPalette.lua`) and
`GameConfig.Rarities` colors. Same formula as test/pure_specs/Contrast.spec.lua
(reproducible: re-run that spec or the math below).

**Thresholds used:** AA normal text ≥ 4.5:1 · AA large text (≥24px, or ≥19px
GothamBold ≈ 14pt bold) and non-text UI (WCAG 1.4.11) ≥ 3:1.
**Type scale:** xxs 11 · xs 12 · sm 15 · md 19 · lg 24 · xl 30
(`Theme.type.sizes`). xxs/xs/sm are ALWAYS normal-text class; md bold and
above can claim large-text.

---

## 1. Headline results

| Claim / area | Result | Evidence |
| --- | --- | --- |
| Static-audit claim: "textFaint fails WCAG AA" | **DISPROVEN** — 4.98–6.45:1 on every dark surface, all ≥ 4.5 | §2 |
| Rare rarity label on elevated surfaces | **BORDERLINE FAIL** 4.38:1 on surfaceHi at normal sizes | §4 |
| Epic rarity label on elevated surfaces | **FAIL for normal-size text** 3.70:1 on surfaceHi (passes 3:1 large/UI) | §4 |
| CLAIM "$0" idle state (ink text on neutral fill) | **FAIL** 1.98:1 — and NOT disability-exempt (button is Active) | §5 |
| Translucent toasts/banners over the live 3D world | **UNMEASURED — Studio sampling required** (not fabricated here) | §7 |

## 2. Core text tokens × surfaces (the textFaint verdict)

Ratios computed against flat palette surfaces and two composites:
`surfaceT12` = surface fill at BackgroundTransparency 0.12 composited over
`bg` (19,29,44); `surfaceHiT12` likewise (28,40,59). Composite assumption:
the layer behind is `bg` (screen-space dimmer). Real-world toasts float over
the 3D scene — see §7.

| Token | bg | surface | surfaceHi | surfaceMid | undiscovered | surfaceT12 | surfaceHiT12 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| text.primary (238,243,250) | 16.57 | 15.01 | 12.79 | 13.65 | 15.99 | 15.19 | 13.30 |
| text.secondary textDim (148,163,184) | 7.20 | 6.53 | 5.56 | 5.93 | 6.95 | 6.61 | 5.78 |
| text.tertiary textFaint (138,154,177) | 6.45 | 5.85 | **4.98** | 5.32 | 6.23 | 5.92 | 5.18 |

**Verdict (AC3): the textFaint AA-fail claim is DISPROVEN with reproducible
math.** Worst case is 4.98:1 on surfaceHi — above the 4.5:1 AA-normal floor
with ~11% headroom. Caveats, documented not fabricated: (a) Roblox text
rendering (font rasterization, no subpixel positioning guarantees) is not a
browser; (b) this covers flat and bg-composited surfaces only — translucent
panels over bright 3D content are §7. Headroom is thin enough that any
darkening of textFaint or lightening of surfaceHi breaks AA — Contrast.spec
already pins this (fails CI if either moves).

## 3. Accent / status / brand colors as text

All measured against the worst surface (surfaceHi) and all other §2 surfaces.
Floors: 4.5 normal, 3.0 large/UI.

| Token | Worst ratio (surface) | AA-normal | AA large/UI |
| --- | --- | --- | --- |
| money (158,215,88) | 8.36 (surfaceHi) | PASS | PASS |
| good | 6.52 (surfaceHi) | PASS | PASS |
| bad | 4.71 (surfaceHi) | PASS | PASS |
| warn | 8.27 (surfaceHi) | PASS | PASS |
| quest | 9.60 (surfaceHi) | PASS | PASS |
| boat | 7.43 (surfaceHi) | PASS | PASS |
| purple | 5.24 (surfaceHi) | PASS | PASS |
| alert | 7.55 (surfaceHi) | PASS | PASS |
| raidAlert | 5.58 (surfaceHi) | PASS | PASS |
| discovery | 10.17 (surfaceHi) | PASS | PASS |
| accent | 4.82 (surfaceHi) | PASS | PASS |
| info (accentSoft) | 7.20 (surfaceHi) | PASS | PASS |

No failures. `bad` (4.71) and `accent` (4.82) have the least headroom —
flag for Contrast.spec to keep pinning at 4.5 (it currently pins status
colors at 3.0 only; see §8 R3).

## 4. Rarity colors as text (GameConfig.Rarities — game data, NOT UI palette)

Usage: rarity labels in aquarium panel lines (xs), collection list headers
(xs, bold), reveal card (lg/xl, bold), fish leap FX tint (non-text).

| Rarity | bg | surface | surfaceHi | surfaceMid | undiscovered |
| --- | --- | --- | --- | --- | --- |
| Common (190,190,190) | 9.94 | 9.00 | 7.67 | 8.19 | 9.59 |
| Uncommon (85,200,120) | 8.72 | 7.90 | 6.74 | 7.19 | 8.42 |
| Rare (70,140,255) | 5.68 | 5.14 | **4.38 ✗** | 4.68 | 5.48 |
| Epic (170,85,255) | 4.80 | 4.35 ✗ | **3.70 ✗** | 3.95 ✗ | 4.63 |
| Legendary (255,170,0) | 9.68 | 8.77 | 7.47 | 7.97 | 9.34 |

(Worst surface for every rarity is surfaceHi; all values from the WCAG
formula, reproducible via Contrast.spec helpers.)

- **Rare**: passes everywhere except surfaceHi at 4.38 (−3% under 4.5).
  Fails only at normal sizes on elevated cards.
- **Epic**: fails 4.5 on surface/surfaceHi/surfaceMid; 3.70 worst. Passes
  3:1 everywhere, so large/bold usage (reveal card) is fine — xs list labels
  are not.
- **Blast radius warning (AC5):** these colors live in `GameConfig.Rarities`
  and double as gameplay FX tints (fish leap) and chat/feed colors. DO NOT
  retune the token — fix at the call site (§8 R2).

### 4b. Tinted-chip composite (rarity tags) — found post-remediation

The xs rarity TAGS (bag rows, collection tiles, reveal card) are label text
IN THEIR OWN HUE on a chip filled with the same hue at BackgroundTransparency
0.78 over the row/card. The flat-surface matrix above did NOT model this
composite; fresh-eyes review caught it. Chain: row/card = surface @~0.85
over bg → chip = lifted-rarity @ (1 − chipTransparency) over row → text =
lifted rarity.

| Chip transparency | Common | Uncommon | Rare | Epic | Legendary |
| --- | --- | --- | --- | --- | --- |
| 0.78 (as shipped pre-fix) | 6.21 | 5.77 | 4.60 | **4.21 ✗** | 6.17 |
| **0.9 (shipped fix)** | 8.53 | 7.74 | 5.84 | **5.19 ✓** | 8.34 |

At 0.78 the 22% same-hue tint lifted the background toward the text hue and
dragged Epic below 4.5 even WITH the 0.22 label lift. Collection tiles were
worse: they used the RAW token (Epic ~3.4 on the composite). Fix shipped on
all three tag sites: chip transparency 0.78 → 0.9 (10% tint) + lifted tag
text (collection/reveal keep the saturated token only for decorative
silhouettes and the reveal card's LARGE title). Composite chain uses the
documented §2 assumptions (panel backdrop = bg); the reveal card's gradient
backdrop remains §7 Studio-sampling scope — the fix strictly improves that
ratio regardless of backdrop hue.

## 5. Button / control states

| State | Pair | Ratio | Verdict |
| --- | --- | --- | --- |
| primary (STORE ALL etc.) | ink on accent | 6.45 | PASS |
| secondary | text on surfaceHi | 12.79 | PASS |
| ghost | textDim on surface | 6.53 | PASS |
| danger | ink on bad | 6.30 | PASS |
| CLAIM ready | ink on claimReady | 5.70 | PASS |
| CLAIM ready (glow hi) | ink on claimReadyHi | 8.72 | PASS |
| **CLAIM idle "$0"** | **ink on neutral** | **1.98** | **FAIL** |
| Uniform disabled recipe | textFaint on surfaceHi | 4.98 | PASS (AA-normal) |
| System-error disabled recipe | textFaint on disabled fill | 3.26 | Exempt* |

*Inactive/disabled controls are exempt from WCAG 1.4.3; 3.26 recorded for
completeness.

**CLAIM idle is the one clear, non-exempt failure (AC1).** The button is
`Active=true` (init.client.lua:7347-7350) — "CLAIM $0" is real information
("nothing to claim yet"), not a disabled control, so the exemption does not
apply. Ink (10,16,26) on neutral (60,70,80) is barely legible. Fix is
call-site, one line: use `text` (8.62:1) or `textDim` (3.75:1) for the idle
label — §8 R1.

## 6. Gradient surfaces

`GradientLibrary` presets interpolate palette tokens (e.g. surface.default =
surface → surfaceMid). Mid-band measured as the `surfaceMid` column above:
all text tokens pass (worst textFaint 5.32). Gradient endpoints are palette
colors (already measured), so the flat-token matrix bounds every gradient
stop. No fabricated ratios: any preset whose stops are all palette tokens is
fully covered by §2/§3. Presets with non-palette stops: none found at audit
time (kqbq.22.5 promoted the last raw RGB into the palette).

## 7. Studio sampling queue (NOT measured — do not fabricate)

These composite over the live 3D scene (bright water/sky worst case) and
cannot be derived from flat math:

1. Toast surface (showNotification) — bg/surface at BackgroundTransparency
   0.12 over gameplay.
2. RaidBanner + DataStoreBanner — surface.primary at 0.12 over gameplay.
3. HUD income line / carry pill — text directly over the 3D world with only
   a text stroke.
4. Reveal card rarity title over its rarity-tinted gradient.
5. Quest progress text over quest-gold gradient chips.

Method: Studio screenshot per case (desktop + mobile), sample the actual
composited pixel behind the text centroid, compute ratio against the text
color, append to this matrix with confidence=measured.

## 8. Recommendations (input to etj2.4.4, prioritized)

| # | Fix | Level | Blast radius | Status |
| --- | --- | --- | --- | --- |
| R1 | **CLAIM idle**: TextColor3 = Theme.color.text in the unclaimedIncome==0 branch (1.98 → 8.62) | Call-site, 1 line | None | **DONE (etj2.4.4)** — ready branch explicitly keeps ink on claimReady (5.70) |
| R2 | **Epic/Rare small labels**: `rarityLabelColor()` lifts label colors 0.22 toward white (Rare 4.38→5.77, Epic 3.70→5.02 on surfaceHi); applied to bag rows, collection headers, aquarium stats lines. Reveal card keeps the saturated token (large-text pass). Follow-up: bag-row tinted-chip composite (§4b) fixed via chip transparency 0.78→0.9 (Epic 4.21→5.19) | Call-site helper + chip tweak | 3 label call sites + tag chip | **DONE (etj2.4.4)** |
| R3 | **Contrast.spec**: bad/accent pinned at 4.5 (was 3.0); CLAIM-idle pair and lifted-rarity math pinned drift-proof (parses GameConfig source) | Test-only | None | **DONE (etj2.4.4)** |
| R4 | Do NOT retune textFaint, Rare, or Epic tokens | Token freeze | Avoids palette-wide + gameplay-FX churn | **DONE (etj2.4.4)** — no tokens changed |
| R5 | Run §7 Studio sampling before any translucency change | Validation | None | OPEN — Studio-gated (tracked on etj2.5.2 matrix) |

## 9. Roblox/platform caveats (recorded per STANDARD)

- WCAG ratios are a browser-oriented benchmark applied here as a practical
  floor; Roblox does not do gamma-correct font rasterization identically on
  all GPUs, and mobile auto-brightness/OLED dimming erodes effective
  contrast further. Treat <5:1 as "monitor", not "safe".
- TextStrokeTransparency (used on HUD text) is an effective-contrast aid
  WCAG doesn't model; §7 sampling is the arbiter for stroked text.
- Large-text exception applied only where size+weight demonstrably meet
  ≥24px or ≥19px GothamBold.
