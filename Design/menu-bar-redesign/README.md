# Menu Bar Icon Redesign

## Constraints

- Canvas: `18 × 18 pt`; monochrome macOS template image.
- No percentage digits. The quota indicator must remain legible at 18 pt.
- Track alpha: `22%`; active quota stroke: `100%`.
- Loading/unavailable: track only, no active stroke.
- Stale/error pip remains outside the icon at bottom-right.
- Center symbol must remain readable in light, dark, and increased-contrast menu bars.

## Directions

### A — Orbit (recommended)

One circular quota gauge plus one Codex chevron. It has the clearest quota mapping and the lowest visual noise. The progress arc starts at 12 o'clock and proceeds clockwise.

### B — Terminal

Stronger developer-tool identity, but the bottom quota rail becomes small at 18 pt and the frame competes with the progress state.

### C — Float

Keeps the original floating-orb character while simplifying it. It is the closest to the app icon, but the lower curved progress rail is less immediately understood as a percentage.

## Fidelity acceptance

- Inspect each direction at true 18 pt before judging the enlarged drawing.
- At 0%, the active segment disappears; at 100%, it becomes a full solid ring/rail.
- The chevron must not close up at 1× rendering.
- Do not integrate live quota until one direction is selected and its current/loading/stale/error static states pass screenshot QA.
