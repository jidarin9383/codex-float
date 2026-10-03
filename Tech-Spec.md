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
- CI packages one **universal** `arm64` + `x86_64` archive and verifies both Mach-O slices before signing.

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
- Identifies an exact 10,080-minute weekly window and an exact 300-minute (5-hour) window. Duration-unknown windows remain unlabeled.
- Glance fields (`remainingPercent`, `resetsAt`) come from the 5-hour window **only when `planType` is Plus and that window exists**. Every other plan, and Plus without a 5-hour window, uses the weekly window. Short windows on non-Plus plans are stored but never promoted to glance or detail UI.
- Optional HTTPS `/wham/usage` enrichment may attach a 5-hour window for Plus when app-server omitted it. It must never invent dates or windows, never replace app-server weekly data, and never promote a 5-hour glance for non-Plus plans.
- Owns refresh policy, stale-state calculation, retry backoff, and last successful snapshot.
- Emits a domain model that contains only UI-safe, non-secret data.
- Maps `rateLimitResetCredits.availableCount` into an optional reset-opportunity count for the detail view.
- Treats the app-server reset count as authoritative and accepts only `0...100` before creating display rows.
- Publishes app-server snapshots without awaiting optional HTTPS enrichment; enrichment is cached for 15 minutes and may add reset-credit dates and, for Plus only, a real 5-hour window from `/wham/usage`.

### `LocalSampleStore`

- Optional JSON or SQLite persistence for non-secret quota samples and preferences.
- MVP stores only the last successful snapshot and widget preferences.
- Daily token history remains opt-in and out of the initial data path unless explicitly selected.

### Presentation

- `MenuBarExtra` provides a persistent **logo template + remaining % text** and a settings/actions menu (not the quota detail). Stale/error use a small status pip. MVP menu: floating-widget toggle, launch at login, check for updates, quit.
- A borderless, non-activating `NSPanel` provides the floating widget (on by default at first launch). Collapsed size ~**92 × 36** (logo + percent, centered). Click expands in place to the detail layout (~320 × 372).
- Panel behavior: `canJoinAllSpaces`, `fullScreenAuxiliary`, no Dock icon, remembers position per display, and avoids stealing focus.
- SwiftUI renders menu bar, widget, detail, and all states from one observable store.
- A top-right collapse control changes the expanded panel back to its edge-attached compact state; it does not close the app or hide the widget.
- Primary quota still comes from app-server `account/rateLimits/read`.
- Reset opportunity **count** from `rateLimitResetCredits.availableCount`.
- Per-credit **expiry dates** (when available) from ChatGPT HTTPS `wham/rate-limit-reset-credits` using the local Codex access token in `auth.json` (in-memory only; never logged). Display `第 N 次` + date when expanded. If dates are missing, count-only — never invent dates.
- No web jump for the reset-opportunity row.
- Compact fill and detail progress tint: system green when remaining **> 50%**, orange when **> 20% and ≤ 50%**, red when **≤ 20%**, secondary gray for loading / unknown. Capacity bands apply whenever a remaining % is known (including stale cache). Stale uses a yellow pip/banner; error uses text/iconography so color is not the only freshness signal.
- Working display name: **Codex Float**; bundle id: `app.codexfloat.mac`.
- Detail copy: Plus with a 5-hour glance uses **5 小时剩余** as the hero and keeps weekly remaining as a fact row; all other cases use **本周剩余**. **下次重置** is the glance window (absolute + relative). **当前套餐** is unchanged.

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

`RateLimitResetCreditsSummary.availableCount` is the authoritative reset-opportunity count. Optional ChatGPT HTTPS enrichment may attach expiry dates to those rows but must never replace the count, create extra rows, or delay publication of app-server quota data.

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
- On a rate-limit protocol error, restart the app-server process and retry the read once before entering failure backoff.
- Wake/network recovery: immediate refresh.
- Only one refresh may be in flight.
- Floating content (compact and expanded) exposes `立即刷新` in its native context menu; the menu bar offers the same recovery action.
- Manual refresh waits for any automatic read, relaunches app-server, and bypasses the HTTPS enrichment cache. Concurrent callers await the actual result; repeated manual clicks share one forced request.
- Disable manual refresh while running and show `正在刷新…`. Preserve stale/error reporting on local read failure; optional HTTPS failure retains authoritative local data.
- Verification: concurrent reads share a result, forced refresh bypasses the enrichment cache and awaits new Plus data, failure remains retryable, and both floating states expose the action.

## Security and Privacy

- Read `CODEX_HOME/auth.json` or `~/.codex/auth.json` only for request-local ChatGPT expiry enrichment. Never log, persist, or place token/account values in process arguments.
- Never pass credentials or tokens through command-line arguments.
- Never log full protocol payloads in release builds because future fields may contain account metadata.
- Redact executable paths and errors before optional diagnostic export.
- No telemetry in the MVP.
- Local history contains quota percentages and timestamps only and can be cleared from settings.

## Test Strategy

- XCTest (`swift test`): JSONL splitting, interleaved notifications, request correlation, timeout, malformed JSON, process exit, nullable fields, multi-limit selection, exact-weekly selection, Plus-only 5-hour glance, non-Plus weekly glance, count bounds and authority, percentage normalization, reset formatting, stale calculation, and backoff.
- Integration test: launch the real local `codex app-server` only behind an explicit developer flag; never run in normal CI.
- Static UI tests: fixed current, stale, error, 0%, 100%, long plan name, missing reset time, and multiple-window fixtures.
- Visual QA: light/dark, 1x/2x display, multiple Spaces, full-screen auxiliary behavior, multiple displays, and localization overflow.

## Implementation Sequence

1. Static menu bar menu, floating widget (collapsed + expanded detail), using fixed fixtures.
2. Screenshot QA against the selected visual direction.
3. Protocol client and repository with unit tests.
4. Integrate live quota data without changing approved layout.
5. Settings menu, launch at login, GitHub packaging/CI/Releases, in-app update check (ad-hoc sign). Developer ID + notarization optional later.
