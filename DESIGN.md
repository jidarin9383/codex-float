# Design System — Calm Instrument

## Intent

The app should feel like a quiet macOS instrument aligned with **macOS Tahoe liquid glass**: translucent materials, soft specular edges, and restrained type. It is not a gaming HUD, traffic light, or analytics dashboard.

## Visual Principles

- Weekly remaining quota is the only hero metric.
- Reveal complexity progressively: glance, click, inspect.
- Use Tahoe-style glass (`.ultraThinMaterial`, specular top sheen, luminous edge) and semantic system colors rather than opaque cards or neon gradients.
- Reserve warning color for low quota or stale data; normal operation should not glow or pulse.
- Prefer typography, alignment, and whitespace over nested cards and heavy borders.

## Surfaces

### Brand

- App mark: **Ocean Mist v2 Float Glass** — outer progress ring (~1/3) + glass orb + center `>` + soft ground.
- Canonical palette: ring `#3D7A86` / ink `#173238` / glass `#A9C8CF`–`#E6F2F4`.
- Assets live in `Assets/Brand/` (canonical copies) and `Assets/Brand/v2/` (source). Do not ship official OpenAI/Codex logos.
- Surfaces stay Tahoe liquid glass. **Quota fill colors** use system semantic green / orange / red (not brand ring alone).

### Menu Bar Item

- **Brand logo template** (monochrome system template) **plus live remaining percentage** to the right (e.g. `93%`).
- v2 silhouette: outer progress + solid disc with `>` cutout + **float ground arc at the bottom**; drawn ~16 pt (`MenuBarQuotaIcon`).
- Optional tiny status pip for loading / stale / error; never replaces the logo.
- Accessibility label includes remaining percentage and freshness.
- Click opens a native menu of app actions (not the detail panel): 悬浮窗, 开机自启, 检查更新, 退出.

### Floating Widget (collapsed)

- Natural target size: approximately **92 × 36 pt** compact **liquid-glass battery capsule**.
- One capsule only — no nested pill. Body is transparent Tahoe glass (`.ultraThinMaterial` + light specular sheen).
- Capacity is a **full-height** left fill flush to the capsule edge.
- Unfilled region stays **pure transparent glass** — no opaque wash, no gray empty track.
- Edge: light dual-tone hairline. Elevation: **soft single-layer** ambient shadow (avoid heavy black pads under the chip).
- Content: **logo + percentage only** (no `剩余` label). Logo + percent are **centered** in the capsule (both axes). Fill still grows from the leading edge.
- Fill tint: system green / orange / red / gray per attention thresholds below. Glyphs turn white only when fill is wide enough (~≥58%) that they sit fully on the color band; otherwise use label color for contrast on glass.
- No title bar, close button, pin button, or refresh button in the collapsed state.
- Click expands in place to the detail panel.

### Detail Panel (floating expanded)

- Natural target size: approximately 320 × 372 pt; expands from the collapsed widget in place.
- Top brand row: **logo + product name `Codex Float`**, collapse control (`chevron.right`) on the trailing edge; weekly percentage hero below (tinted by attention color).
- Middle region: one remaining-quota progress track and factual rows:
  - **下次重置** — absolute date/time + relative countdown
  - **当前套餐** — plan type when available
- Bottom region: **重置机会** summary (`N 次可用`); expand chevron only when per-credit expiry dates exist; expanded list shows `第 N 次` + date.
- Additional limit windows appear as secondary rows only when present.

## Tokens

### Color

- Background: Tahoe liquid glass (`.ultraThinMaterial` plus specular sheen), adaptive light/dark.
- Primary text: `labelColor`.
- Secondary text: `secondaryLabelColor`.
- Healthy: system green when remaining **> 50%**.
- Attention: system orange when remaining **> 20% and ≤ 50%**.
- Critical: system red when remaining **≤ 20%**.
- Stale: system yellow with text; never rely on color alone.
- Unknown or loading: `secondaryLabelColor` gray.

### Typography

- System San Francisco only.
- Compact widget percentage: ~14 pt semibold rounded tabular.
- Detail hero percentage: 40–48 pt semibold.
- Section label: 11–12 pt medium.
- Body: 13–14 pt regular.
- Tabular digits for percentages, countdowns, and reset times.

### Spacing

- Base unit: 4 pt.
- Common gaps: 4, 8, 12, 16, 24 pt.
- Detail popover inset: 16 pt.
- Row height: 32–40 pt depending on content.

### Radius and Elevation

- Widget radius: ~18 pt.
- Detail radius: ~22 pt.
- Grouped rows: ~14 pt glass insets.
- Use system window shadow. Avoid layered glow and large decorative shadows.

## Interaction and Motion

- Click widget: open detail without moving the widget.
- Drag: movement begins only after a small threshold to prevent accidental repositioning.
- Progress updates animate over 180–240 ms with ease-out.
- No continuous animation in healthy or stale states.
- Respect Reduce Motion and Increase Contrast.

## Content Voice

- Short, factual, and calm.
- MVP UI copy is Simplified Chinese.
- Prefer compact `18%` on the float, detail copy such as `下次重置` / `当前套餐`, `7 月 20 日 14:30` + `6 天 18 小时后重置`, `2 次可用`.
- Avoid motivational scoring such as “speed up” or “slow down” in the MVP.
- Explain failures with one cause and one action.

## Required States

- Loading skeleton without a percentage.
- Current value.
- Stale cached value with timestamp.
- Logged out.
- Codex executable missing.
- Unsupported protocol.
- No weekly window.
- Limit reached.
- Light, dark, reduced transparency, increased contrast, and reduced motion.

## Anti-patterns

- No neon dual-color HUD copied from the Windows reference.
- No circular liquid meter.
- No always-visible window controls.
- No flashing or breathing status lights.
- No invented 5-hour metric when the source does not return one.
- No dashboard grid of metrics in the collapsed widget.
- No custom imitation of macOS controls when a native control exists.

## Selected Direction

- The selected visual route is the light-mode right-edge widget that expands inward.
- Preserve its edge attachment, warm translucent material, large remaining percentage, one weekly progress track, and flat factual rows.
- Replace all English UI copy with Simplified Chinese.
- Show dynamic reset-opportunity count; optional dated rows when ChatGPT credits API provides expiries (never invent dates).
- Add one native top-right collapse button; it returns the panel to the narrow right-edge widget and is not a close, settings, or refresh action.
- The compact progress fill changes like a battery indicator: green >50%, orange >20%…50%, red ≤20%, gray when current quota is unavailable.
- The progress track represents remaining quota: 18% remaining means an 18%-filled track.
- Do not show a target marker, `已使用 82%`, or `100%`; those repeat information already conveyed by the hero metric.
- Remove the normal-state refresh icon, update timestamp, and settings row. Automatic refresh should be invisible unless data becomes stale or unavailable.
