# Technical Specification

## Platform and Distribution

- Native macOS application using Swift 6, SwiftUI, and AppKit.
- Initial compatibility target: macOS 14 or later, subject to validation in the first spike.
- Swift Package Manager for project dependencies and tests.
- **Open-source distribution (current):** GitHub source + GitHub Releases zip of an ad-hoc signed `.app` built by `scripts/package-app.sh` and CI.
- Gatekeeper: users may need right-click → Open for ad-hoc builds. Documented in README.
- In-app **检查更新** uses the public GitHub Releases API (`CodexFloatGitHubRepo` / `owner/repo` injected at package time). No private update feed.
- **Deferred:** Developer ID signing and notarization (optional later for smoother first-open).
- No App Store target in the MVP because the app launches the user's local `codex` executable.
- CI packages **arm64** on `macos-14` runners; Intel users build from source unless a universal binary is added later.

## Architecture

```text
MenuBarExtra / Floating NSPanel / Detail Popover
                    |
             QuotaViewModel
                    |
             QuotaRepository
          /                         \
 CodexAppServerClient         LocalSampleStore
          |
  codex app-server --stdio
```

### `CodexAppServerClient`

- Swift actor that owns `Process`, stdin/stdout/stderr pipes, JSONL framing, request IDs, pending continuations, timeout handling, and process shutdown.
- Starts the local command with structured arguments: `app-server --stdio`.
- Sends `initialize`, then `initialized`, then `account/rateLimits/read`.
- Decodes protocol messages by request ID and ignores unrelated notifications.
- Supports `account/rateLimits/updated` as a hint to refetch or merge, but polling remains the reliability baseline.

### `QuotaRepository`

- Selects the `codex` entry from `rateLimitsByLimitId` when present.
- Falls back to the backward-compatible `rateLimits` snapshot.
- Normalizes used percentage into remaining percentage without relabeling unknown windows.
- Owns refresh policy, stale-state calculation, retry backoff, and last successful snapshot.
- Emits a domain model that contains only UI-safe, non-secret data.
- Maps `rateLimitResetCredits.availableCount` into an optional reset-opportunity count for the detail view.

### `LocalSampleStore`

- Optional JSON or SQLite persistence for non-secret quota samples and preferences.
- MVP stores only the last successful snapshot and widget preferences.
- Daily token history remains opt-in and out of the initial data path unless explicitly selected.

### Presentation

- `MenuBarExtra` provides a persistent **icon-only** menu bar glyph (remaining-quota ring, no digits) and a settings/actions menu (not the quota detail). MVP menu: floating-widget toggle, launch at login, check for updates, quit.
- A borderless, non-activating `NSPanel` provides the floating widget (on by default at first launch). Click expands the panel in place to the detail layout (~320 × 360).
- Panel behavior: `canJoinAllSpaces`, `fullScreenAuxiliary`, no Dock icon, remembers position per display, and avoids stealing focus.
- SwiftUI renders menu bar, widget, detail, and all states from one observable store.
- A top-right collapse control changes the expanded panel back to its edge-attached compact state; it does not close the app or hide the widget.
- Primary quota still comes from app-server `account/rateLimits/read`.
- Reset opportunity **count** from `rateLimitResetCredits.availableCount`.
- Per-credit **expiry dates** (when available) from ChatGPT HTTPS `wham/rate-limit-reset-credits` using the local Codex access token in `auth.json` (in-memory only; never logged). Display `第 N 次 · M 月 d 日`. If dates are missing, show `可用` — never invent dates.
- No web jump for the reset-opportunity row.
- The compact dot and progress tint share one semantic state: green above 20%, system orange from 11% through 20%, system red at or below 10%, and secondary gray for loading, stale, or unknown data. Stale and error states also use text or iconography so color is not the only signal.
- Working display name: **Codex Float**; provisional bundle id: `app.codexfloat.mac` until packaging is finalized.
- Detail reset formatting includes absolute local date/time plus relative countdown.

## Protocol Contract

### Request

```json
{"id":2,"method":"account/rateLimits/read"}
```

### Relevant response shape

```json
{
  "rateLimits": {
    "limitId": "codex",
    "primary": {
      "usedPercent": 42,
      "windowDurationMins": 10080,
      "resetsAt": 1784622680
    },
    "secondary": null,
    "planType": "plus",
    "credits": {
      "hasCredits": false,
      "unlimited": false,
      "balance": "0"
    }
  },
  "rateLimitsByLimitId": {
    "codex": {}
  },
  "rateLimitResetCredits": {
    "availableCount": 2
  }
}
```

All fields except the response container are treated as version-sensitive and decoded defensively. Unknown fields are ignored. Missing windows, plan metadata, credits, reset opportunities, and reset timestamps are valid states.

`RateLimitResetCreditsSummary` currently contains only `availableCount`. The app must not infer or display per-opportunity expiry dates unless a future supported protocol version adds those fields.

## Executable Discovery

1. User-configured path in app settings.
2. Candidates found by scanning the current process `PATH` without invoking a shell.
3. Known Codex app bundle locations when verified on the target machine.
4. Failure state with a path picker; never silently download or replace Codex.

The selected path is persisted as a bookmark or plain non-secret preference as appropriate.

## Refresh Policy

- Launch: immediate snapshot.
- Widget visible or detail open: every 60 seconds.
- Menu-bar-only: every 60 seconds.
- Failure backoff: 15 seconds, 30 seconds, 1 minute, then 5 minutes, capped.
- Wake/network recovery: immediate refresh.
- Only one refresh may be in flight.
- No manual refresh control is exposed in the normal UI; automatic refresh and recovery own freshness.

## Security and Privacy

- Never read `~/.codex` credential content.
- Never pass credentials or tokens through command-line arguments.
- Never log full protocol payloads in release builds because future fields may contain account metadata.
- Redact executable paths and errors before optional diagnostic export.
- No telemetry in the MVP.
- Local history contains quota percentages and timestamps only and can be cleared from settings.

## Test Strategy

- Unit tests: JSONL splitting, interleaved notifications, request correlation, timeout, malformed JSON, process exit, nullable fields, multi-limit selection, percentage normalization, reset formatting, stale calculation, and backoff.
- Integration test: launch the real local `codex app-server` only behind an explicit developer flag; never run in normal CI.
- Static UI tests: fixed current, stale, error, 0%, 100%, long plan name, missing reset time, and multiple-window fixtures.
- Visual QA: light/dark, 1x/2x display, multiple Spaces, full-screen auxiliary behavior, multiple displays, and localization overflow.

## Implementation Sequence

1. Static menu bar menu, floating widget (collapsed + expanded detail), using fixed fixtures.
2. Screenshot QA against the selected visual direction.
3. Protocol client and repository with unit tests.
4. Integrate live quota data without changing approved layout.
5. Settings menu, launch at login, GitHub packaging/CI/Releases, in-app update check (ad-hoc sign). Developer ID + notarization optional later.
