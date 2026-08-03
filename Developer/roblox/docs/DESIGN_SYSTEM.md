# Harbor Heist Design System

> **Single source of truth** for the game's visual language: colors, typography,
> spacing, motion, components, and accessibility standards.

## Table of Contents

1. [Color System](#1-color-system)
2. [Typography](#2-typography)
3. [Spacing](#3-spacing)
4. [Corner Radii](#4-corner-radii)
5. [Shadows & Elevation](#5-shadows--elevation)
6. [Gradient Presets](#6-gradient-presets)
7. [Button System](#7-button-system)
8. [Animation & Motion](#8-animation--motion)
9. [Accessibility Standards](#9-accessibility-standards)
10. [Feedback & Affordance](#10-feedback--affordance-epic-44)
11. [Desktop Modality](#11-desktop-modality-epic-44)
12. [Mobile Modality](#12-mobile-modality-epic-44)
13. [Minigame Visual Language](#13-minigame-visual-language-epic-44)
14. [Best Practices](#14-best-practices)
15. [Content & Voice Standards](#15-content--voice-standards-epic-45)
16. [Unavailable-State Content Pattern](#16-unavailable-state-content-pattern-epic-45)
17. [Cast Coaching Policy](#17-cast-coaching-policy-epic-45)
18. [STORE ALL Consequence Preview](#18-store-all-consequence-preview-epic-45)
19. [Minigame Feedback Model](#19-minigame-feedback-model-epic-45)
20. [Measured Contrast Matrix](#20-measured-contrast-matrix-epic-45)
21. [Non-Color State Communication](#21-non-color-state-communication-epic-45)
22. [DataStore Degraded-Mode Contract](#22-datastore-degraded-mode-contract-epic-45)

---

## 1. Color System

### Architecture

Colors flow through two layers:

1. **`UIPalette`** (`src/shared/UIPalette.lua`) — flat base palette of 24 colors
   stored as RGB integer triples. Zero Roblox-instance dependencies; safe to
   `require()` from pure-Luau specs under lune.
2. **`Theme`** (`src/client/init.client.lua:254`) — semantic token groupings
   built **on top of** the base palette. **New code reads from `Theme`, never
   from `UIPalette` directly.**

```lua
-- DO: use semantic Theme tokens
Theme.color.surface.secondary
Theme.color.text.primary
Theme.color.status.good

-- DON'T: use flat UIPalette values directly (except inside Theme definition or pure specs)
UIPalette.colors.surface
UI.surface
```

### Base Palette (`UIPalette.colors`)

| Name | RGB | Used For |
| --- | --- | --- |
| `bg` | 13, 20, 31 | Root background |
| `surface` | 20, 30, 46 | Panel/card backgrounds |
| `surfaceHi` | 30, 43, 63 | Elevated surfaces, hover states |
| `surfaceMid` | 26, 38, 57 | Mid-surface highlight (gradient tokens) |
| `stroke` | 255, 255, 255 | Borders/dividers (always used with transparency) |
| `accent` | 56, 152, 255 | Primary interactive elements |
| `accentSoft` | 120, 190, 255 | Hover/soft accent states |
| `good` | 52, 199, 123 | Success, positive feedback |
| `bad` | 255, 92, 92 | Errors, destructive actions |
| `warn` | 255, 184, 64 | Warnings, cautionary feedback |
| `quest` | 255, 205, 92 | Quest-related UI |
| `boat` | 94, 200, 235 | Boat/travel UI |
| `purple` | 167, 139, 250 | Collection/epic rarity |
| `text` | 238, 243, 250 | Primary text |
| `textDim` | 148, 163, 184 | Secondary text |
| `textFaint` | 138, 154, 177 | Tertiary/hint text |
| `ink` | 10, 16, 26 | Text on bright backgrounds |
| `money` | 134, 239, 172 | Currency/cash displays |
| `undiscovered` | 16, 24, 36 | Undiscovered/locked items |
| `claimReady` | 50, 160, 80 | Claim-ready indicators |
| `claimReadyHi` | 74, 198, 114 | Claim-ready hover |
| `disabled` | 100, 60, 60 | Disabled states |
| `neutral` | 60, 70, 80 | Neutral UI elements |
| `alert` | 255, 170, 80 | Alert notifications |
| `raidAlert` | 255, 120, 120 | Raid alert notifications |

### Semantic Tokens (`Theme.color.*`)

| Group | Token | Source | Description |
| --- | --- | --- | --- |
| **surface** | `.primary` | `bg` | Root background |
| | `.secondary` | `surface` | Panel/card backgrounds |
| | `.elevated` | `surfaceHi` | Elevated surfaces |
| | `.undiscovered` | `undiscovered` | Locked items |
| **text** | `.primary` | `text` | Body text |
| | `.secondary` | `textDim` | Labels, captions |
| | `.tertiary` | `textFaint` | Hints, metadata |
| | `.ink` | `ink` | Text on bright/solid backgrounds |
| **accent** | `.base` | `accent` | Buttons, links, active states |
| | `.soft` | `accentSoft` | Hover, soft highlights |
| **status** | `.good` | `good` | Success feedback |
| | `.bad` | `bad` | Error feedback |
| | `.warn` | `warn` | Warning feedback |
| | `.info` | `accentSoft` | Informational feedback |
| | `.claimReady` | `claimReady` | Ready-to-claim indicators |
| | `.claimReadyHi` | `claimReadyHi` | Claim-ready hover |
| | `.disabled` | `disabled` | Disabled interactive elements |
| | `.neutral` | `neutral` | Neutral controls |
| | `.alert` | `alert` | Alert toasts |
| | `.raidAlert` | `raidAlert` | Raid victim alerts |
| **brand** | `.quest` | `quest` | Quest-themed UI |
| | `.boat` | `boat` | Boat/travel UI |
| | `.purple` | `purple` | Collection/epic |
| **money** | — | `money` | Currency displays |
| **stroke** | — | `stroke` | Borders (use with transparency) |

### Usage

```lua
local UIPalette = require(ReplicatedStorage.Shared.UIPalette)
local bg = UIPalette.color("bg")  -- returns Color3

-- In init.client.lua (Theme is a local):
local panelColor = Theme.color.surface.secondary
local textColor  = Theme.color.text.primary
```

---

## 2. Typography

### Font Stack

| Token | Font | Usage |
| --- | --- | --- |
| `Theme.type.fonts.head` | GothamBlack | Headlines, titles |
| `Theme.type.fonts.bold` | GothamBold | Button labels, emphasis |
| `Theme.type.fonts.med` | GothamMedium | Subtitles, section headers |
| `Theme.type.fonts.body` | Gotham | Body text, default |

### Size Scale (1.25 Ratio)

| Token | Size (px) | Usage |
| --- | --- | --- |
| `Theme.type.sizes.xxs` | 11 | Fine print, metadata |
| `Theme.type.sizes.xs` | 12 | Captions, small labels |
| `Theme.type.sizes.sm` | 15 | Body text (compact) |
| `Theme.type.sizes.md` | 19 | Body text (default) |
| `Theme.type.sizes.lg` | 24 | Section headers |
| `Theme.type.sizes.xl` | 30 | Panel titles |

### Usage

```lua
label.Font = Theme.type.fonts.bold
label.TextSize = Theme.type.sizes.sm
```

---

## 3. Spacing

4px base grid with five standard steps:

| Token | Value (px) | Usage |
| --- | --- | --- |
| `Theme.spacing.xs` | 4 | Tight gaps, icon padding |
| `Theme.spacing.sm` | 8 | Compact element spacing |
| `Theme.spacing.md` | 12 | Standard padding/gaps |
| `Theme.spacing.lg` | 16 | Section padding |
| `Theme.spacing.xl` | 24 | Panel padding |
| `Theme.spacing.xxl` | 32 | Major section gaps |

```lua
padding.PaddingTop = UDim.new(0, Theme.spacing.lg)
layout.Padding = UDim.new(0, Theme.spacing.md)
```

---

## 4. Corner Radii

| Token | Value (px) | Usage |
| --- | --- | --- |
| `hairline` | 2 | Minimal rounding |
| `thin` | 3 | Small elements |
| `slim` | 4 | Tags, chips |
| `compact` | 5 | Small buttons |
| `snug` | 6 | Compact cards |
| `tight` | 7 | — |
| `sm` | 8 | Small panels |
| `roomy` | 10 | — |
| `md` | 12 | Standard panels, buttons |
| `spacious` | 14 | — |
| `lg` | 16 | Large panels |
| `xl` | 20 | Modals, dialogs |
| `pill` | 999 | Fully rounded (pills, avatars) |

Buttons inherit `Theme.corners.md` by default via `buttonVariants`.

---

## 5. Shadows & Elevation

Roblox UI has no native shadow; elevation is faked with layered semi-transparent
Frames. Three elevation levels:

| Token | Layers | Spread (px) | Alpha | Usage |
| --- | --- | --- | --- | --- |
| `Theme.shadows.low` | 2 | 4 | 0.15 | Cards, tooltips |
| `Theme.shadows.medium` | 3 | 8 | 0.20 | Panels, popovers |
| `Theme.shadows.high` | 4 | 16 | 0.30 | Modals, overlays |

---

## 6. Gradient Presets

`GradientLibrary` (`src/client/GradientLibrary.lua`) provides reusable
`UIGradient` presets. Apply via dot-separated path:

```lua
Gradients.apply(panel, "surface.default")
Gradients.apply(button, "accent.primary")
Gradients.apply(bar, "status.success")
```

### Surface Gradients

| Preset | From | To | Usage |
| --- | --- | --- | --- |
| `surface.default` | `surfaceMid` (token) | bg | Panels, overlays, reveal cards |
| `surface.elevated` | surface | surfaceHi | Elevated containers |
| `surface.hud` | surface | bg | HUD background (kqbq.22.5: seam fix) |

### Accent Gradients

| Preset | From | To | Usage |
| --- | --- | --- | --- |
| `accent.primary` | accent | accentSoft | Buttons, highlights |
| `accent.soft` | accentSoft | text | Soft accents |
| `accent.brand` | purple | accent | Branded elements |
| `accent.capacity` | `purple:Lerp(text, 0.3)` | purple | Capacity meters |

### Status Gradients

| Preset | From | To | Usage |
| --- | --- | --- | --- |
| `status.success` | good | `good:Lerp(text, 0.3)` | Progress bars, success |
| `status.warning` | quest | warn | Warning indicators |
| `status.collection` | quest | warn | Collection milestones |
| `status.error` | bad | `bad:Lerp(text, 0.3)` | Error indicators |
| `status.info` | accentSoft | boat | Informational elements |

### Rarity Gradients

All presets derive from palette tokens via `Color3:Lerp` (kqbq.22.5). Presets are
currently unused (canonical rarity colors live in `GameConfig.Rarities`); kept for
future gradient effects.

| Preset | Colors | Usage |
| --- | --- | --- |
| `rarity.Common` | `textDim` gradient | Common fish |
| `rarity.Uncommon` | `good` gradient | Uncommon fish |
| `rarity.Rare` | `accent` gradient | Rare fish |
| `rarity.Epic` | `purple` gradient | Epic fish |
| `rarity.Legendary` | `quest` gradient | Legendary fish |
| `rarity.Mythic` | `purple:Lerp(bad, 0.5)` gradient | Mythic fish |

---

## 7. Button System

### Variants

Use the `Variant` prop in `makeButton()`:

```lua
makeButton(parent, {
    Text = "Cast",
    Variant = "primary",
    -- ...other props
})
```

| Variant | Background | Text Color | Stroke | Usage |
| --- | --- | --- | --- | --- |
| `primary` | accent | ink | none | Main actions (Cast, Buy, Claim) |
| `secondary` | surfaceHi | text | stroke @ 0.7 | Secondary actions (Open Panel) |
| `ghost` | surface | textDim | stroke @ 0.85 | Low-emphasis actions |
| `danger` | bad | ink | none | Destructive actions |

All variants use `Theme.corners.md` (12px) corner radius by default.

### Micro-interactions

Every `makeButton` includes:

- **Press**: 0.94 scale compression (EASE_PRESS, 0.10s Quad Out)
- **Release**: Spring bounce-back (EASE_POP, 0.28s)
- **Visual ripple**: Luminance-derived circular Frame spawns at press point
  (adapts to button bg brightness), expands outward while fading
  (EASE_RIPPLE, 350ms, self-cleaning via `task.delay`)
- **Haptic feedback**: `UIClick` haptic on press (mobile only, `IS_MOBILE` guard)

---

## 8. Animation & Motion

### Easing Presets

| Constant | Style | Direction | Duration | Usage |
| --- | --- | --- | --- | --- |
| `EASE_OUT` | Quint | Out | 0.22s | Panel opens, element entry |
| `EASE_IN` | Quad | In | 0.16s | Panel closes, element exit |
| `EASE_POP` | Spring | Out | 0.28s | Button bounce, scale reveals |
| `EASE_FAST` | Quad | Out | 0.12s | Legacy fast transitions |
| `EASE_PRESS` | Quad | Out | 0.10s | Button press compression |
| `EASE_HOVER` | Quad | Out | 0.20s | Hover/leave tweens (distinct from press) |
| `EASE_RIPPLE` | Quad | Out | 0.35s | Visual ripple expansion |

**Principle**: Entries decelerate (feel smooth arriving); exits accelerate
at ~0.8x the entry duration (e.g. 0.22s close vs 0.28s open). Spring easing
is reserved for physical bounce-back, not
fades or exits.

### PanelAnimation (`src/shared/PanelAnimation.lua`)

Shared module for panel/modal open/close with fade + scale:

```lua
local PanelAnimation = require(ReplicatedStorage.Shared.PanelAnimation)

-- Open (fade in + scale up from 0.8)
PanelAnimation:open(panel, {
    duration = 0.25,
    scaleStart = 0.8,
    onComplete = function() ... end,
})

-- Close (fade out + scale down)
PanelAnimation:close(panel, {
    destroyOnComplete = true,
    onComplete = function() ... end,
})
```

| Function | Description |
| --- | --- |
| `:open(panel, opts)` | Fade + scale-in animation (Quint/Out) |
| `:close(panel, opts)` | Fade + scale-out animation (Quad/In) |
| `:cancel(panel)` | Cancel all tweens, reset to visible state |
| `:isAnimating(panel)` | Returns true if tweens are active |
| `:cleanup()` | Cancel all tracked animations (called on shutdown) |

**UIScale ownership**: `PanelAnimation` creates its own `UIScale` instance
(marked with `PanelAnimationOwned` attribute). If a panel already has a
user-managed `UIScale`, only the fade animation runs — scale is skipped to
avoid conflicts.

### AnimationSystem (`src/client/AnimationSystem.lua`)

Advanced spring-physics animation engine for:
- Smooth value transitions (position, size, color)
- Gesture-driven animations (drag, swipe)
- Staggered list item reveals
- Skeleton loader shimmer effects

### Theme.motion Token Table (EPIC-44 kqbq.17.2)

`Theme.motion` is the single source for every duration/easing token. `EASE_*`
presets derive from `Theme.motion`. **New motion: add a `Theme.motion` token
and alias — never construct `TweenInfo.new` inline at call sites.**

- **Press depth**: 0.94 at `EASE_PRESS` (0.10s Quad Out). Release: `EASE_POP` (Spring).
- **Hover**: `EASE_HOVER` (0.20s Quad Out) — perceptually distinct from press (0.10s).
- **Ripple**: `EASE_RIPPLE` (0.35s Quad Out).
- **Panel close**: `EASE_IN` (0.16s Quad In) at ~0.8x the 0.22s `EASE_OUT` open.

**RULE**: No `TweenInfo.new` literals outside `Theme.motion` without a code-comment
justification (see rejection log in `ClientChrome.spec.lua`). Finger-tracking is
always 1:1 instant — never Spring. Spring is reserved for bounce-back only.

---

## 9. Accessibility Standards

### WCAG Color Contrast

All text colors are regression-tested against WCAG AA requirements:

| Standard | Ratio | Applies To |
| --- | --- | --- |
| AA Normal | >= 4.5:1 | Body text on all dark surfaces |
| AA Large/UI | >= 3.0:1 | Status/accent colors, large text, UI components |

**Tested by**: `test/pure_specs/Contrast.spec.lua` (runs in pure-Luau bucket)

Text luminance hierarchy is enforced: `text > textDim > textFaint`.

**Known borderline**: `claimReady` on `surfaceHi` is ~4.26:1 — passes 3:1 for
large text/UI but is below 4.5:1 for normal body text. **Avoid `claimReady`
for small body text.**

### Touch Target Sizes

All interactive elements meet mobile minimums:

| Standard | Minimum | Applies To |
| --- | --- | --- |
| WCAG 2.1 / Apple HIG | 44 x 44 px | All interactive elements on mobile |

**Tested by**: `test/pure_specs/TouchTargets.spec.lua` (runs in pure-Luau bucket)

Covered elements: toast action buttons, toast close buttons, panel close
buttons, action bar buttons, full-width primary buttons, shop buy / raid
buttons. All use `IS_MOBILE and 44 or <desktop_size>` branching.

### Running Accessibility Tests

```bash
scripts/run_tests.sh --pure
# Contrast.spec.lua and TouchTargets.spec.lua are part of the pure bucket
```

---

## 10. Feedback & Affordance (EPIC-44)

Stripe-level UX means nothing ever leaves the player guessing. Every input gets
an acknowledgment; every state is visually legible.

### Adaptive Ripple (kqbq.4)

Button press ripple adapts to button background luminance. On dark buttons
(primary, danger) the ripple is light; on light buttons (ghost, secondary) it
darkens. The previous hardcoded white ripple was invisible on light backgrounds.

### Disabled State Recipe (kqbq.18.2)

`setButtonEnabled(button, false)` applies a uniform disabled treatment:
- `Active = false`
- `TextColor3` → `text.tertiary`
- `BackgroundColor3` → semantic disabled bg (`surface.elevated` or `status.disabled`)

Applied to: inventory debounce, raid opt-in debounce, claim button (DataStore
unhealthy), lock RECHARGE. Shop OWNED/LOCKED/unaffordable already have distinct
visuals (harborheist-cl05).

### Toast System (kqbq.5/kqbq.18.3)

- **Accent bar**: 6px left bar colored by category (good/bad/warn/quest) with a
  soft category glow frame.
- **Text overflow**: fade-edge indicator on long toast text.
- **Known tech debt**: server toasts use ~8 off-palette raw `Color3` literals —
  tracked in a2ug.1/.2/.3 for palette migration.

### Gradient Color Discipline (kqbq.22.5)

`GradientLibrary` presets derive from `UIPalette` tokens only — either directly
or via `Color3:Lerp`. No raw `Color3.fromRGB` in `GradientLibrary` (contract-
verified in `ClientChrome.spec.lua`). `surfaceMid` (26,38,57) promoted to
`UIPalette` as a named token. The HUD gradient seam was fixed: `surface.hud`
uses `UI.surface` instead of a hardcoded brighter value.

---

## 11. Desktop Modality (EPIC-44)

Desktop is not scaled-up mobile. It leverages cursor hover, physical keyboard,
and screen real estate.

### Hover Tooltips (kqbq.10/kqbq.20.1)

Action bar buttons show tooltips on hover: name + keyboard shortcut + one-line
hint. Tooltips never appear while a panel or minigame owns input.

### Esc-Cancel (kqbq.12.2)

Esc closes the current context: panels, prompts, onboarding, and cast overlay.
Cast cancel requires server cooperation — the client fires `Remotes.CancelCast`
and hides the cast overlay. Client-only cancel would desync the pending 2-6s
bite window.

### Ultra-Wide Balance (kqbq.13, P4)

On >1920px viewports, the bottom action bar scales button width modestly and
caps total bar width at ~40% of viewport. Standard widths remain unchanged
below the threshold.

---

## 12. Mobile Modality (EPIC-44)

Mobile is the dominant Roblox modality. It must feel NATIVE, not ported.
44px minimum touch targets (`TouchTargets.spec` enforced). Landscape phones
(~375px height) are the binding constraint.

### Scroll Affordance (kqbq.8)

Scrollable action stacks render a fade-edge indicator at the cut-off boundary
and a one-time nudge animation on first overflow. This signals scrollability
without persistent visual clutter.

### Scrollbar Auto-Hide (kqbq.9)

6 scrolling frames (shop, collection, inventory, quests, raid targets, action
stack) auto-hide their scrollbars after 3s of idle. Scrollbars fade in on
scroll, fade out when idle. Eliminates visual clutter on small screens.

### Toast Density (kqbq.16)

Mobile toasts carry a 52px min-height (to fit 44x44 action buttons) and stack
up to 3. Compact mobile toast layout: action buttons become icon-only 44x44
inline-right (touch-target preserved on both axes; label is the button glyph),
the message text narrows to clear the buttons, and a 1Hz viewport poll scales
the visible cap so the stack stays under ~30% of viewport height (clamped
1..3). A small `+N more` overflow chip under the stack reports the queued
backlog on mobile, refreshed on every enqueue/drain. Desktop is unchanged.

---

## 13. Minigame Visual Language (EPIC-44)

The three minigames (cast, bite, raid) share one visual language. A player
moving from cast to bite to raid should need zero re-learning.

### Zone Vocabulary (kqbq.19.1)

- **Good band**: wide, forgiving zone (accent-soft color).
- **Perfect bullseye**: narrow, high-reward zone (accent or rarity color).
- **Marker**: moving indicator (white, 18px glow at 0.50 transparency — kqbq.6).
- **Track**: dark surface with subtle stroke.

### Labels (kqbq.7)

Cast overlay shows PERFECT / GOOD micro-labels on the zone bands. Progressive
disclosure: labels appear subtly on first cast, fade on repeated casts. Luck
bonus values shown as subtitle: `PERFECT +25 LUCK  GOOD +12 LUCK`.

### Marker Sweep (kqbq.19.1)

Bite and raid markers use `os.clock`-based ping-pong triangular wave (not linear
`TweenService`). Sweep period ~1.7s for raid. Both minigames use the same timing
language.

---

## 14. Best Practices

### Do

- **Use `Theme.*` tokens** for all new UI code — never hardcode `Color3.fromRGB()`
  values outside the `UIPalette` definition and `Theme` constructor.
- **Use `Theme.spacing.*`** for all padding, margins, and gaps.
- **Use `Theme.type.sizes.*` and `Theme.type.fonts.*`** for all text.
- **Use `Theme.corners.*`** for all corner radii — avoid literal numbers.
- **Use `makeButton(parent, { Variant = "...", ... })`** for all buttons.
- **Apply gradients via `Gradients.apply(el, "category.name")`** — never
  hand-create `UIGradient` instances inline.
- **Animate panels via `PanelAnimation`** — don't hand-roll fade/scale tweens.
- **Use `EASE_OUT` for entries, `EASE_IN` for exits, `EASE_POP` for bounces,
  `EASE_PRESS` for press, `EASE_HOVER` for hover, `EASE_RIPPLE` for ripples.**
- **Ensure every new interactive element meets 44px touch target on mobile.**
- **Verify new text/surface color pairs pass WCAG AA** by adding cases to
  `Contrast.spec.lua` if introducing a new surface or text color.

### Don't

- **Don't hardcode `Color3.fromRGB()` values** elsewhere than `UIPalette` and
  `Theme`. If you need a new color, add it to `UIPalette.colors` and reference
  it via `Theme.color.*`.
- **Don't duplicate palette values** — `UIPalette` is the single source of truth.
  Both `init.client.lua`'s `UI` table and `GradientLibrary`'s `UI` table read
  from it.
- **Don't use `EASE_POP` (Spring) for fades or exits** — the overshoot causes
  flicker on transparent elements and feels wrong on departure.
- **Don't create raw `UIGradient` instances** — use `GradientLibrary.apply()`.
- **Don't shrink mobile touch targets below 44px** — the pure spec will fail.
- **Don't use `claimReady` for normal-sized body text** — it fails 4.5:1 AA on
  elevated surfaces. Use it only for large labels, icons, or UI components.
- **Don't bypass `PanelAnimation` for panel open/close** — it handles UIScale
  ownership tracking, tween cleanup, and consistent easing.

---

## 15. Content & Voice Standards (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.4.1. Scope: the high-risk
player-facing surfaces — action labels, blocked states, confirmations,
onboarding, timeouts, and recoverable errors. This is not a marketing voice
guide; strings that already meet these rules stay as they are.

### 15.1 Voice

Warm nautical confidence. Concise and calm. Playful only at celebration moments
(a perfect cast, a completed quest, a big sale). Never sarcastic, never
accusatory, never vague. When something goes wrong, the message tells the player
what happened and what to do next — it does not dramatize the failure.

### 15.2 Capitalization

| Surface | Rule | Examples |
| --- | --- | --- |
| Sentences (notifications, banners, prompts) | Sentence case. Capitalize first word + proper nouns only | "Your aquarium is full" |
| Panel titles, section headers | Title Case | "Bait & Tackle Shop" |
| Short controls/chips (≤ 3 words) | ALL CAPS is the documented rendered convention for buttons and state chips | CLAIM, SELL ALL, LOCKED, WAIT |
| Sentences inside ALL-CAPS controls | Never. If it needs a verb phrase longer than 3 words, it is a notification, not a label | ✗ "SAVING UNAVAILABLE" as a button state → use a banner + neutral label |

### 15.3 The "outcome + next action" grammar

Every blocked state, timeout, and recoverable error follows the same two-beat
shape: **what happened (+ why, if not obvious) → what the player does next.**
Both beats are mandatory; either one alone fails this standard.

- ✓ "Your aquarium is full! Sell some fish first." (outcome + next action)
- ✓ "Your hands are full! Store or sell your fish first."
- ✗ "Saving unavailable -- try again." (vague outcome, vague action)
- ✗ "No fish to sell!" (outcome only — no next action; fine ONLY when the next
  action is self-evident from the control the player just pressed)

### 15.4 Punctuation

- **Em dash `—`** for asides and outcome→action pivots. Never `--`.
- **No trailing `...` on failure messages.** Ellipsis signals "still in
  progress" and is reserved for genuine waits. Failures end with a period.
  (✗ "Too slow! The raid window of opportunity passed...")
- **One exclamation mark maximum**, and only for celebration or positive
  urgency ("PERFECT CAST!", "FISH ON!"). Failure and blocked states use
  periods — calm, not scolding. (✗ "Stand in a fishing zone at your dock!")
- **Contractions preferred** ("You're", "can't") — the voice is warm, not
  formal. Pick one form per string; duplicates must converge.
  (✗ "You are casting too fast" vs "You're casting too fast" — keep the latter)

### 15.5 Numerals, currency, durations

- **Digits always** ("5 fish", never "five fish").
- **Currency**: `$` prefix + the canonical `formatCash` rendering — comma-grouped
  integers below $1M (`$1,250`, `$999,999`), compact M/B suffixes at $1M and up
  (`$1,500,000` → `$1.5M`, `$999,999,999` → `$1B`). There is NO K suffix.
  Never hand-format cash in a new string; call `formatCash`.
- **Durations under 2 minutes**: seconds with an `s` suffix (`LOCK 60s`,
  `RECHARGE 45s`). **2 minutes and over**: minutes, rounded down (`2m`).
  Never mix units in one string (`1m 30s` ✗).
- **Separators**: the middot `•` separates stat clusters in HUD lines
  (`$250  •  $12/min`). Do not invent new separators.

### 15.6 Mobile length limits

| Surface | Limit | Notes |
| --- | --- | --- |
| Button / chip label | ≤ 14 characters | Must fit the smallest hero button at min window |
| Notification (toast) | ≤ 90 characters | One to two lines on a phone portrait viewport |
| Banner header | ≤ 40 characters | Persistent banners (e.g. DataStore-degraded) |
| Banner body | ≤ 120 characters | Outcome + next action, nothing else |
| Onboarding prompt | ≤ 80 characters, one action per prompt | "Press F to cast into the glowing zone at your dock!" |

### 15.7 Surface-specific rules

- **Action labels**: imperative verb first, object second (`STORE ALL`,
  `SELL BAG`, `CLAIM $1,250`). No punctuation.
- **Blocked states**: outcome + next action (15.3). If the block is timed, name
  the time (`LOCKED 45s`).
- **Confirmations**: state the consequence, then the confirm gesture —
  `SELL ALL $1,250? TAP` is the canonical shape. Destructive or irreversible
  actions always confirm; reversible ones never do.
- **Onboarding**: imperative, present tense, exactly one action per prompt,
  input named explicitly (`Press F`, `Press G`, `Tap`).
- **Timeouts & expired windows**: calm recovery framing — the next attempt is
  implied free. ✗ "Too slow! The raid window of opportunity passed..." →
  ✓ "The raid window closed — the next one opens soon."
- **Recoverable errors**: "Couldn't X — try again." is the canonical shape
  ("Couldn't sell that fish — try again."). Never blame the player, never say
  "error", never expose internal reasons.

### 15.8 Anti-cheat & security messages

Distinct and firm. These describe a limit the system enforced — they never
comment on the player's intent or character, and they are never playful.

- ✗ "Too fast! Play the minigame fairly." (accusatory)
- ✓ "That attempt didn't count — wait for the timing window."
- Rate limiting: "Slow down — you're casting too fast." (calm, mechanical,
  no moralizing)

### 15.9 Worked examples (current strings → standard)

| Current | Verdict | Standard form |
| --- | --- | --- |
| "Saving unavailable -- try again. Your progress is safe but purchases may not persist." | False claim, `--`, vague | Per docs/DATASTORE_DEGRADED_CONTRACT.md §3.2 banner |
| "Too slow! The raid window of opportunity passed..." | Scolding + trailing `...` | "The raid window closed — the next one opens soon." |
| "The fish got away..." | Trailing `...` | "The fish got away." |
| "Heist failed! The fish slipped away..." (server) vs "Heist failed — the fish slipped away." (client) | Divergent duplicates | One string: "Heist failed — the fish slipped away." |
| "You have no fish to store. Go fish!" | Meets standard (playful but instructive) | Keep |
| "PERFECT CAST! +Luck on this catch." | Meets standard (celebration) | Keep |
| "Stand in a fishing zone at your dock!" | Exclamation on a blocked state | "Stand in a fishing zone at your dock." |
| "Your aquarium is full! Sell some fish." / "...Sell some fish first." | Near-duplicates | Converge on "Your aquarium is full! Sell some fish first." |

Only strings that violate these rules are candidates for change
(harborheist-ux45-workflow-clarity-etj2.4.2); conforming strings are not churned.

## 16. Unavailable-State Content Pattern (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.2.1. Full pattern, taxonomy,
countdown rules, and worked examples: **docs/UNAVAILABLE_STATE_PATTERN.md**.

The grammar: **STATE** — *reason* — *recovery*, in fixed slots. STATE lives on
the control (≤ 14 chars, ALL CAPS chip convention); reason lives in adjacent
always-visible helper text (never hover-only, never tap-to-explain on an
inactive control); recovery tails the reason unless self-evident.

Six canonical states: disabled, locked-by-prerequisite (`LOCKED` + named
prerequisite), cooldown (`RECHARGE 30s`, live 1Hz, server-authoritative),
maxed (`MAXED` badge in `status.good`, an achievement not a block),
unhealthy/degraded (warn banner, actions stay live — §15 + the DataStore
contract), temporarily unavailable (toast `"Couldn't X — try again."`,
control returns to ready).

The one deliberate exception: **"not yet" is not disabled** — an
unaffordable-but-purchasable control stays tappable so the tap can explain
(harborheist-cl05). Timed blocks always name the time; unknown durations name
the condition, never a fake number; a countdown reaching zero shows the bare
reason until the server confirms availability.

---

## 17. Cast Coaching Policy (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.1.1  
**Full spec:** docs/CAST_COACHING_POLICY.md

Two miss classes in the cast minigame (timing bar before bite):

- **Class A — idle cast**: overlay opens, zero taps before timeout. Toast: "No timing bonus — tap the bar next cast!" (once per session).
- **Class B — off-target cast**: tap received, accuracy outside good band. Server derives tier "ok" (no bonus). Toast: "You missed the GOOD band — tap inside it to keep the luck bonus." (once per session).

**Cadence**: Both toasts are one-shot per client session. Class A fires on first idle timeout. Class B fires on first off-target tap. They never fire together in the same session.

**Anti-nag**: Toasts are non-severe (category "info"), tail the queue, evicted oldest-first under pressure. They never block gameplay or repeat on every miss.

---

## 18. STORE ALL Consequence Preview (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.2.3  
**Full spec:** docs/STORE_ALL_PREVIEW.md

Progressive disclosure at the decision point (no modal confirmation):

| State | Button label | Helper text |
| --- | --- | --- |
| All fit (`movable == #carried`, > 0) | `STORE ALL` | — (hidden) |
| Partial (`0 < movable < #carried`) | `STORE 2 OF 5` | "Only 2 fit — 3 stay in your bag." |
| None fit (`movable == 0`, carried > 0) | `TANK FULL` (inactive) | "Sell stored fish to free space." |
| Empty bag (carried == 0) | `STORE ALL` (inactive) | — (hidden) |

**One-tap all-fit path is sacred**: When every carried fish fits, nothing changes — no confirmation, no helper text. STORE ALL is a frequent, fully reversible core-loop action. A modal is a confirmation tax on the game's tightest loop and is rejected by default.

**Helper text**: One sentence, outcome + next action (§15.3), digits always (§15.5). Exists only when the result would surprise.

---

## 19. Minigame Feedback Model (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.3.1  
**Full spec:** docs/MINIGAME_FEEDBACK_MODEL.md

Four feedback moments (fishing and raid minigames):

| Moment | Name | Channel | Authoritative? |
| --- | --- | --- | --- |
| M1 | Input acknowledgment | Neutral white tap flash + haptic tick | No — "received" only |
| M2 | Server-confirmed timing tier | Toast/label naming the tier the SERVER derived | Yes (server-derived) |
| M3 | Final outcome + reason | Result toast / reveal card | Yes |
| M4 | Recovery action | Tail of the M3 message (one action) | — |

**Principles**:
1. Input acknowledgment is not a result. The tap flash means "input received" — never colors green/red, never previews hit/miss.
2. The client never claims a tier. The client reports raw marker position; the server re-derives the tier. No UI element may label a tier before the server responds.
3. Chance is honest. When a clean timing input still fails on the server's probability roll, the copy says so — distinctly from a timing failure.
4. Every failure teaches one next step. Outcome + next action (§15.3 grammar), one recovery action only.
5. Never reveal the roll early. No odds, no "almost won" framing before the server response.

---

## 20. Measured Contrast Matrix (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.4.3  
**Full spec:** docs/CONTRAST_MATRIX.md

WCAG 2.x relative-luminance contrast math over UIPalette RGB triples and GameConfig.Rarities colors. Same formula as test/pure_specs/Contrast.spec.lua.

**Thresholds**: AA normal text ≥ 4.5:1 · AA large text (≥24px, or ≥19px GothamBold ≈ 14pt bold) and non-text UI (WCAG 1.4.11) ≥ 3:1.

**Headline results**:

| Claim / area | Result |
| --- | --- |
| Static-audit claim: "textFaint fails WCAG AA" | **DISPROVEN** — 4.98–6.45:1 on every dark surface, all ≥ 4.5 |
| Rare rarity label on elevated surfaces | **BORDERLINE FAIL** 4.38:1 on surfaceHi at normal sizes |
| Epic rarity label on elevated surfaces | **FAIL for normal-size text** 3.70:1 on surfaceHi (passes 3:1 large/UI) |
| CLAIM "$0" idle state (ink text on neutral fill) | **FAIL** 1.98:1 — and NOT disability-exempt (button is Active) |
| Translucent toasts/banners over the live 3D world | **UNMEASURED — Studio sampling required** (not fabricated) |

**Remediation** (etj2.4.4): Rare/Epic rarity labels lifted 0.22 (Rare 5.77/Epic 5.02 on surfaceHi). CLAIM $0 idle state fixed. Zero token changes — call-site fixes only.

---

## 21. Non-Color State Communication (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.4.5  
**Full spec:** docs/etj2.4.5_NON_COLOR_AUDIT.md

**Result:** NO-CHANGE — every gameplay-critical state has a reliable non-color second channel.

**Audit matrix**:

| State | Color role | Non-color second channel | Verdict |
| --- | --- | --- | --- |
| Cast minigame zones (perfect/good) | Zone fill color (gold/green) | Text labels "PERFECT" / "GOOD" above zones | ✅ Compliant |
| Bite minigame zone | Zone stroke color (green) | Text label "ZONE" above zone | ✅ Compliant |
| Raid minigame zones | Zone fill color (green/yellow) | Text labels "PERFECT"/"GOOD" | ✅ Compliant |
| Rarity identification | Rarity color on tag/text | Rarity NAME as uppercase text on every bag row + collection card | ✅ Compliant |
| Capacity warning/full | Fill bar color (purple) | Text "N / M fish" in aquariumStats; STORE ALL label matrix | ✅ Compliant |
| Income ready | CLAIM button pulse (claimReady/Hi) | Button text "CLAIM $N" with dollar amount | ✅ Compliant |
| Destructive/error status | status.bad / status.warn colors | Toast message text (every showNotification has a message string) | ✅ Compliant |
| Disabled/unavailable buttons | Color swap (setButtonEnabled → surface.elevated + text.tertiary) | Text reason per docs/UNAVAILABLE_STATE_PATTERN.md | ✅ Compliant |

**Conclusion**: No code changes required. The codebase already follows the multi-channel principle consistently: color is always paired with text, shape, or position.

---

## 22. DataStore Degraded-Mode Contract (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.2.5  
**Full spec:** docs/DATASTORE_DEGRADED_CONTRACT.md

When DataStore is unhealthy (3 consecutive save/load failures), the game enters degraded mode:

**Player-facing banner** (persistent, not a toast):
- Header: "Saving interrupted — retrying"
- Body: "Everything you earn counts and saves automatically when connection recovers. Stay in game to keep recent progress."

**Recovery toast** (one-shot when health restores): "Saving restored — you're all caught up."

**Per-operation policy**:
- **Claim income, sell fish, store fish, shop purchase, quest reward, raid fish transfer**: Proceed in-memory, retry on next autosave (60s). In-session state is authoritative; single-document write makes operations atomic.
- **Fish catch → carried**: Proceed. No checkpoint until store/sell/autosave. Worst case: loss of ≤5 unsaved carried fish.
- **Autosave**: Retry every 60s. Each success self-heals the flag.
- **Leave save**: 2 attempts, wait ≤15s for in-flight, then accept loss. No requeue after remove().

**Health-flip propagation** (etj2.2.7): When health flips (healthy→unhealthy or unhealthy→healthy), DataManager notifies all sessions within ~1s via proactive StateSync.push. Clients show/clear the degraded banner immediately, not on the next income-tick or action push.

**Truthful copy**: Banner copy must never claim durability the code does not provide. The approved copy says "Everything you earn counts and saves automatically when connection recovers" — this is true as long as the player stays in game. If the player leaves before any write succeeds, data since the last successful save is lost. The copy is honest about the recovery mechanism without overpromising.

---

## Module Reference

| Module | Path | Description |
| --- | --- | --- |
| `UIPalette` | `src/shared/UIPalette.lua` | Base color palette (24 colors, RGB triples) |
| `Theme` | `src/client/init.client.lua:254` | Semantic tokens (spacing, type, color, corners, shadows, buttonVariants) |
| `GradientLibrary` | `src/client/GradientLibrary.lua` | Reusable UIGradient presets |
| `PanelAnimation` | `src/shared/PanelAnimation.lua` | Panel open/close fade + scale animations |
| `AnimationSystem` | `src/client/AnimationSystem.lua` | Spring physics, transitions, micro-interactions |
| `KeyboardNav` | `src/client/KeyboardNav.lua` | Keyboard navigation (Tab/Enter/Space, focus indicators) |
| `Contrast.spec` | `test/pure_specs/Contrast.spec.lua` | WCAG AA contrast regression guard |
| `TouchTargets.spec` | `test/pure_specs/TouchTargets.spec.lua` | 44px touch-target regression guard |
