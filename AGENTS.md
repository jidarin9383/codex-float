# Codex Quota for Mac — Project Instructions

## Project

- Product: a native macOS utility that shows remaining Codex quota at a glance (working name: **Codex Float**).
- Created: 2026-07-14.
- Target stack: Swift 6, SwiftUI, and AppKit where macOS window behavior requires it.
- Package manager: Swift Package Manager.
- Planned directories: `Sources/`, `Tests/`, `Design/`, and `Assets/`.

## Product Rules

- The primary value is ambient awareness: weekly remaining percentage must be visible without opening a dashboard.
- Support both a menu bar surface and an optional always-on-top floating surface.
- Keep the floating surface calm, compact, readable, and non-interactive until clicked.
- Show freshness and failure honestly. Never present cached quota as current without a visible timestamp or stale state.
- Treat missing short-window data as a valid state. Do not invent a 5-hour window when Codex returns only a weekly window.

## Data and Security

- Use the locally installed `codex app-server --stdio` protocol for primary quota windows.
- Read quota through `account/rateLimits/read`; treat `account/rateLimits/updated` as an optional update signal, not the only refresh mechanism.
- **Reset-credit expiry enrichment (allowed):** read local `CODEX_HOME/auth.json` or `~/.codex/auth.json` **only** to obtain an access token for ChatGPT quota HTTPS endpoints:
  - `https://chatgpt.com/backend-api/wham/usage`
  - `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
- Tokens and account IDs must stay in memory for the request only. **Never** log, print, copy, or persist them. Never put them in status messages or diagnostics.
- If auth/HTTPS enrichment fails, keep app-server data and show count-only reset rows (no invented dates).
- Launch `codex` with `Process` and structured arguments. Do not build a shell command string.
- Store only non-secret preferences and optional local quota samples.
- Do not send telemetry or usage data off-device unless a future PRD explicitly adds an opt-in requirement.

## Architecture

- Prefer a small native architecture: protocol client, repository, observable app state, and two presentation surfaces.
- Use actors for subprocess and JSONL protocol ownership.
- Keep SwiftUI state on the main actor.
- Use AppKit only for behavior SwiftUI does not reliably provide, such as a non-activating floating `NSPanel`, all-Spaces visibility, and screen-edge positioning.
- Avoid third-party dependencies unless the standard library and Apple frameworks cannot meet a verified requirement.

## Design and Handoff

- `PRD.md`, `Tech-Spec.md`, and `DESIGN.md` are the product, engineering, and visual sources of truth.
- Freeze one selected visual direction before implementation.
- Build a fixed-data static UI first, capture screenshots, and resolve visual blockers before connecting live quota data.
- Use SF Symbols or project-owned assets for icons. Do not use emoji, text glyphs, or CSS-style drawings as production icons.

## Verification

- Add focused unit tests for JSONL framing, protocol decoding, percentage normalization, reset-time formatting, stale-state handling, and retry backoff.
- Test missing `codex`, logged-out state, malformed output, timeout, process exit, missing weekly window, and multiple limit IDs.
- Visually verify light and dark appearances, desktop Spaces, full-screen apps, multiple displays, long localized strings, and 0%/100% values.
- Before release, verify Developer ID signing and notarization. Mac App Store distribution is not assumed because the app launches an external executable.

## Packaging (Step 5 / GitHub)

- Package with `./scripts/package-app.sh` → universal `arm64` + `x86_64` `dist/Codex Float.app` + zip (ad-hoc signed).
- CI/release workflows live under `.github/workflows/`.
- Inject `CODEX_FLOAT_GITHUB_REPO=owner/repo` for in-app update checks when packaging.
- Do not commit `/dist`, credentials, or notarization secrets. `Assets/AppIcon.icns` may be generated locally and is optional to commit.

## Git

- Preserve unrelated user changes.
- Use English commit messages and technical documentation.
- Do not commit generated build products, credentials, local quota history, or user-specific paths.
