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
10. [Best Practices](#10-best-practices)

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
| `surface.default` | #1A2639 (tuned) | bg | Panels, overlays, HUD, reveal cards |
| `surface.elevated` | surface | surfaceHi | Elevated containers |
| `surface.hud` | #182436 (tuned) | bg | HUD background |

### Accent Gradients

| Preset | From | To | Usage |
| --- | --- | --- | --- |
| `accent.primary` | accent | accentSoft | Buttons, highlights |
| `accent.soft` | accentSoft | text | Soft accents |
| `accent.brand` | purple | accent | Branded elements |
| `accent.capacity` | #C4B5FD (tuned) | purple | Capacity meters |

### Status Gradients

| Preset | From | To | Usage |
| --- | --- | --- | --- |
| `status.success` | good | #64DCA0 (tuned) | Progress bars, success |
| `status.warning` | quest | warn | Warning indicators |
| `status.collection` | quest | warn | Collection milestones |
| `status.error` | bad | #FF8C8C (tuned) | Error indicators |
| `status.info` | accentSoft | boat | Informational elements |

### Rarity Gradients

| Preset | Colors | Usage |
| --- | --- | --- |
| `rarity.Common` | Gray gradient | Common fish |
| `rarity.Uncommon` | Green gradient | Uncommon fish |
| `rarity.Rare` | Blue gradient | Rare fish |
| `rarity.Epic` | Purple gradient | Epic fish |
| `rarity.Legendary` | Gold-orange gradient | Legendary fish |
| `rarity.Mythic` | Pink-magenta gradient | Mythic fish |

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

- **Press**: 0.96 scale compression (EASE_FAST, 0.12s)
- **Release**: Spring bounce-back (EASE_POP, 0.28s)
- **Visual ripple**: White circular Frame spawns at press point, expands
  outward while fading (350ms, self-cleaning via `task.delay`)
- **Haptic feedback**: `UIClick` haptic on press (mobile only, `IS_MOBILE` guard)

---

## 8. Animation & Motion

### Easing Presets

| Constant | Style | Direction | Duration | Usage |
| --- | --- | --- | --- | --- |
| `EASE_OUT` | Quint | Out | 0.22s | Panel opens, element entry |
| `EASE_IN` | Quad | In | 0.16s | Panel closes, element exit |
| `EASE_POP` | Spring | Out | 0.28s | Button bounce, scale reveals |
| `EASE_FAST` | Quad | Out | 0.12s | Press compression, hover glows |

**Principle**: Entries decelerate (feel smooth arriving); exits accelerate
(feel snappy leaving). Spring easing is reserved for physical bounce-back, not
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

## 10. Best Practices

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
- **Use `EASE_OUT` for entries, `EASE_IN` for exits, `EASE_POP` for bounces.**
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
