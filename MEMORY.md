# Project Memory

## 2026-07-14 — Initial product and protocol decisions

- The product is a native macOS quota monitor for Codex, with a menu bar item, an optional always-on-top floating widget, and a detailed popover.
- The local Codex CLI version verified during discovery was `codex-cli 0.142.3`.
- `codex app-server --stdio` exposes `account/rateLimits/read`. A live request returned a `codex` rate-limit snapshot with a 10,080-minute weekly window, percentage used, reset timestamp, plan type, credit state, and reset-credit count.
- The generated app-server schema also includes `account/rateLimits/updated`, `account/usage/read`, `rateLimitsByLimitId`, optional primary/secondary windows, and nullable fields. The implementation must decode defensively.
- `account/usage/read` can provide lifetime summary and daily token buckets. Those values are personal usage data and should remain local and opt-in if surfaced.
- The app must never inspect Codex credential files. It should reuse the authenticated local CLI process and communicate over JSONL stdio.
- The Windows project `stupdada/codex-quota-widget` was reviewed as a functional reference only. Do not copy its Electron implementation, dense dual-window HUD, visual styling, pace algorithm, or source code.
- The preferred implementation is SwiftUI plus a small AppKit bridge. This reduces idle resource use and gives better macOS menu bar, Spaces, and floating-panel behavior than Electron.
- Distribution should initially target a Developer ID-signed and notarized download, not the Mac App Store, because the app needs to launch the locally installed `codex` executable.

## Open decisions

- App icon (menu bar uses a drawn quota ring for now; branded app icon still open).
- Minimum macOS version after the first runnable spike (docs still say 14+ pending validation).
- Whether a later release includes an opt-in daily token history view (not in MVP).

## 2026-07-14 — Visual direction selected

- The user selected the second concept: a light-mode widget attached to the right screen edge that expands inward into a detail sheet.
- All MVP user-facing copy must be Simplified Chinese.
- The detail sheet must show the dynamic `rateLimitResetCredits.availableCount` value as `X 次重置机会`; the locally verified sample value was 2, but production UI must not hardcode it.
- Reset opportunities: app-server `availableCount` + optional ChatGPT `wham/rate-limit-reset-credits` dates via local `auth.json` (in-memory token only). UI `第 N 次 · M 月 d 日` or `可用`.
- The detail sheet does not show manual refresh, normal-state last-updated text, or a settings row. Freshness is automatic and only stale/error states call attention to it.
- The progress track visualizes remaining quota directly. For 18% remaining, it is 18% filled; it has no vertical marker, `已使用 82%`, or `100%` label.
- Capacity fill color always follows remaining bands (green >50 / orange >20…50 / red ≤20), including when data is stale. Stale is not a yellow battery fill; compact capsule has no freshness pip (menu bar + detail banner only).

## 2026-07-14 — Collapse, reset-detail, and color decisions

- The expanded sheet has one top-right collapse button that returns it to the right-edge compact widget without closing or hiding the app.
- The compact progress fill uses battery-like thresholds: green above 50%, orange from above 20% through 50%, red at or below 20%, and gray when freshness is unknown. (Updated 2026-07-15; 18% fixture is critical red.)
- The generated app-server schema defines `RateLimitResetCreditsSummary` with only `availableCount`; it does not expose individual reset-credit records or expiry dates. The UI must not invent text such as `第 1 次，7 月 30 日到期`.
- Codex App `26.707.72221` registers the `codex` URL scheme and contains an internal `/settings/usage` route, but the public settings deep-link allowlist does not expose that route. The MVP therefore opens the stable official web usage page instead of relying on AppleScript or private app internals.

## 2026-07-14 — Surface defaults and menu IA

- First launch defaults: **menu bar + floating widget both on**.
- Menu bar click opens a **settings/actions menu**, not the quota detail. Menu items for MVP: 悬浮窗开关, 开机自启, 检查更新, 退出. Menu bar shows **logo + remaining % digits**.
- Floating widget click expands **in place** to ~320×360 detail (not a separate menu-bar popover).
- Detail UI design work may use Open Design; implementation follows Tech-Spec sequence starting with static fixture UI.
- Product name frozen as working name: **Codex Float** (bundle `app.codexfloat.mac`).

## 2026-07-14 — Tech-Spec step 1 scaffold

- Package/target renamed to `CodexFloat` / `CodexFloatCore`.
- Design mock: `Design/ui-mock.html`.
- Smoke tests: `swift run CodexFloatCoreSmokeTests` (Command Line Tools host; no XCTest).

## 2026-07-14 — Visual and naming refinements

- Menu bar was briefly icon-only; product decision later: **logo + percentage digits** on the menu bar as well as the float.
- Surfaces use **macOS Tahoe liquid glass**: `.ultraThinMaterial`, specular sheen, luminous edge stroke, larger continuous radii.
- Reset row shows absolute date/time + relative countdown (e.g. `7 月 20 日 14:30` / `6 天 18 小时后重置`).
- Working product name: **Codex Float**.

## 2026-07-14 — Open Design mock

- Open Design project: `codex-float-ui` (Codex Float UI).
- Local mirror: `Design/open-design-index.html`.
- Preview via Open Design app project **Codex Float UI**.

## 2026-07-14 — Brand + menu bar logo

- User feedback: first OD pass felt average; want Codex identity; menu bar icon must be **app logo white/template**, designed together with app icon.
- Brand mark v1: code chip + float arc (`Assets/Brand/v1/*`).
- OD redesign run `beb091f6-193d-438e-8b28-26074f39c9c4` succeeded (brand board + desktop mock).
- App code default still v1: `MenuBarLogoIcon` / `MenuBarLogoShape`; widget uses branded chip tinted by quota attention.

## 2026-07-14 — Brand v2 Float Glass

- User feedback: v1 hard to read; want **float / lightweight** or product-name expansion; **more rounded Tahoe glass**. Keep v1, add another direction.
- Brand v2: floating glass orb + soft ground + specular highlight.
- Compare board: `Design/brand-board.html`.

## 2026-07-14 — Brand v2.1 interior intent

- User: float essence OK, but empty orb too vague; wants Codex intent inside (logo / progress ring / code punctuation). Keep float.
- Trademark: do **not** use official OpenAI/Codex logo as app icon; use original `>_` + progress ring.
- v2.x assets in `Assets/Brand/v2/*`: outer progress + orb + `>` + ground; 18pt solid disc.

## 2026-07-15 — Ocean Mist palette frozen

- User selected **Ocean Mist** from color palette options.
- Canonical: ring `#3D7A86` / ink `#173238` / glass `#A9C8CF`–`#E6F2F4`.
- Applied to `app-icon.svg`, `logo-mark*.svg`, `CodexFloatTheme` brand tokens, logo V2 colors.
- Healthy attention tint was briefly brand ring; **usered to system green** with thresholds green >50% / orange ≤50% and >20% / red ≤20%.

## 2026-07-15 — Collapsed widget: battery capsule

- User: compact float no longer matched prior scheme.
- **Single liquid-glass capsule** (no nested pill): full-height left fill = remaining %; unfilled stays pure glass (no gray track).
- No inset white frame/gap — capacity is flush to the capsule edge.
- Expanded detail header shows **logo + Codex Float** brand row.
- Fill tint follows quota attention (system green / orange / red / gray).
- Logo overlays with **transparent** background — no attention-colored chip.

## 2026-07-15 — Widget polish (post color + contrast)

- Menu bar: logo + live %; float ground arc drawn with flipped template (arc at bottom).
- Compact size **~92×36**; content **logo + % only** (removed `剩余`); content **centered**.
- Transparent `.ultraThinMaterial` body; soft single-layer shadow (no heavy black pad).
- Detail labels: **下次重置**, **当前套餐**.

## 2026-07-15 — Step 2 menu-bar v2 cutover + Step 3 protocol

- App default brand mark is **Ocean Mist v2**: menu bar uses `MenuBarLogoIconV2`; compact widget + detail use `CodexFloatLogoMarkV2`.
- Fixture visual board: `Design/fixture-qa.html` (menu bar glyph, pips, all static fixtures, detail 18%).
- Dev-only static fixtures: `CODEX_FLOAT_STATIC_FIXTURES=1` (not exposed in the production menu).
- Step 3 protocol layer in `CodexFloatCore`:
  - `JSONLFramer`, `AppServerProtocol`, `RateLimitsMapper`, `RetryBackoff`
  - `CodexExecutableLocator` (PATH + known paths, no shell)
  - `CodexAppServerClient` actor (`Process` + `app-server --stdio`, initialize → initialized → `account/rateLimits/read`)
  - `QuotaRepository` (refresh, stale 30m, backoff 15s/30s/1m/5m, last success)
- Smoke tests cover framing, decode, multi-limit prefer `codex`, missing secondary, backoff, stale; live probe behind `CODEX_FLOAT_LIVE_PROTOCOL=1`.
- Step 4 live UI wired: `QuotaViewModel` polls `QuotaRepository` (launch/wake refresh; **60s** poll; failure backoff).
- Default live; fixtures via `CODEX_FLOAT_STATIC_FIXTURES=1` or Debug menu toggle.
- Detail reset labels use `Date.now` (not design fixture clock).

## 2026-07-15 — Step 5 GitHub-only open-source packaging

- User: open-source project; publish on GitHub first (no notarization required for this pass).
- `scripts/make-app-icon.sh`: SVG → AppIcon.icns via qlmanage/sips/iconutil.
- `scripts/package-app.sh`: release build → `dist/Codex Float.app` + zip; ad-hoc `codesign`; injects version + optional `CodexFloatGitHubRepo`.
- `UpdateChecker`: public GitHub Releases API; wired to menu「检查更新」.
- CI: `.github/workflows/ci.yml` (build, smoke, package artifact).
- Release: `.github/workflows/release.yml` on `v*` tags → upload zip.
- LICENSE: MIT. Bundle id frozen `app.codexfloat.mac`. First marketing version `0.1.0`.
- Developer ID + notarization + Homebrew deferred.

## 2026-07-15 — GitHub README audience and onboarding

- `README.md` is the end-user product homepage: value, core features, install, first-launch recovery, requirements, usage, privacy, and contribution entry point.
- Keep design boards, UI debugging, architecture diagrams, implementation progress, test commands, and release-maintainer commands out of the homepage; development setup belongs in `CONTRIBUTING.md`.
- Because the GitHub release is not notarized, the primary Gatekeeper recovery path is `System Settings → Privacy & Security → Security → Open Anyway`, matching Apple guidance. Users should be told to download only from this repository's Releases page.
- The current prebuilt GitHub release is Apple Silicon (`arm64`); Intel users must build from source until a separate artifact is published.

## 2026-07-15 — First audit repair batch

- Weekly top-level quota is derived only from an exact `10_080`-minute window; short or unknown windows remain visible but never masquerade as weekly.
- `codex app-server` owns reset-credit count, bounded to `0...100` before row allocation. HTTPS may enrich expiry dates only.
- HTTPS enrichment runs after the local snapshot is returned, retries after failure, and caches successful results for 15 minutes.
- `swift test` is a required CI/contributor gate alongside the smoke executable; repository timing and mapper boundaries have XCTest coverage.
- Menu-bar quota is a live remaining-percentage ring with explicit current/stale/error accessibility copy. External GitHub Actions are pinned to full commit SHAs.

## 2026-07-15 — Universal macOS distribution

- Supersedes the earlier arm64-only release note: GitHub Releases now publish one `macos-universal.zip` containing `arm64` and `x86_64` slices.
- `scripts/package-app.sh` uses SwiftPM multi-architecture builds and rejects the package unless `lipo` verifies both slices before signing.
- Minimum deployment target remains macOS 14 for both Apple Silicon and Intel Macs.
