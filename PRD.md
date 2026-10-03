# Product Requirements Document

## Product

Working name: **Codex Float**

## Problem

Frequent Codex users cannot see their remaining quota without interrupting their work and opening a Codex surface. They need a trustworthy, low-friction signal that answers one question immediately: how much Codex quota is left in the window that will actually block them next. For Plus that is the 5-hour window when present; for every other plan it is the weekly window.

## Target User

Mac users who use Codex throughout the day and want to manage usage before a weekly limit is exhausted. The first user is a power user and independent developer working across multiple Codex surfaces.

## Core Job

At any moment, glance at the desktop or menu bar and understand remaining Codex quota for the active window, then click once for reset time and supporting details.

## Goals

- Show remaining quota for the active glance window as the dominant value: 5-hour for Plus when that window exists, weekly for every other plan.
- Use Simplified Chinese for all MVP user-facing copy.
- Keep the value persistently available through a menu bar item and optional floating widget.
- Open a detailed view in one click.
- Refresh automatically without handling or exposing account credentials.
- Communicate loading, stale, logged-out, unsupported, and unavailable states clearly.
- Feel native to macOS and consume minimal idle resources.

## Non-goals

- Bypassing, resetting, increasing, or predicting OpenAI limits.
- Managing ChatGPT plans, billing, or multiple accounts.
- Scraping the ChatGPT website.
- Reproducing the Windows reference project or its pace-scoring algorithm.
- Claiming second-by-second accuracy when the underlying quota is sampled and integer-rounded.

## Product Surfaces

### Menu Bar

- Shows the **brand logo template** plus **live remaining percentage digits** (e.g. icon + `93%`).
- Loading uses a neutral placeholder (`…`); unavailable may show `—`. Stale/error states use a small status pip. VoiceOver announces remaining percentage and freshness.
- Click opens a settings/actions menu (not the quota detail).
- MVP menu actions: floating-widget toggle, launch at login, check for updates, quit.
- On first launch, both the menu bar item and the floating widget are visible by default.

### Floating Widget

- On by default at first launch; always-on-top, draggable, and visible across Spaces.
- Collapsed capsule (~92 × 36): **logo + glance percentage only** (no `剩余` label), centered on transparent liquid glass; left capacity fill shows remaining share. Plus shows 5-hour remaining when available; other plans show weekly remaining.
- Click expands in place to the ~320 × 372 detail panel (detail lives on the floating surface, not the menu bar).
- The expanded panel has one top-right collapse control that returns it to the edge-attached compact state without hiding the widget.
- Capacity fill uses battery-like semantic colors: green when remaining > 50%, orange when > 20% and ≤ 50%, red when ≤ 20%, gray when freshness is unknown.
- Does not steal keyboard focus during ordinary use.
- Can be hidden without quitting the app.

### Detail Panel (floating expanded state)

- Glance remaining percentage as the hero metric (attention-colored). Plus with a 5-hour window labels this **5 小时剩余**; all other cases label it **本周剩余**.
- **下次重置**: reset of the glance window — absolute date/time plus relative countdown (e.g. `7 月 20 日 14:30` and `6 天 18 小时后重置`).
- Plus with a 5-hour glance also shows a **本周剩余** fact row (weekly percent + weekly reset). Other plans do not show a 5-hour row.
- **当前套餐**: plan type when available.
- Available rate-limit reset opportunities (`N 次可用`). Per-credit expiry dates when available via optional ChatGPT credits enrichment (in-memory token only); otherwise count-only, never invent dates.
- A 5-hour window is displayed only for Plus, and only when app-server or optional `/wham/usage` enrichment actually returns one. Never invent it.
- Reset opportunities are dynamic account data and must never be hardcoded.
- Optional future section for local daily token history, disabled by default until explicitly included.

## Primary Flow

1. User launches the app while already signed in to the local Codex CLI.
2. The menu bar and widget show a loading state.
3. The app reads the local Codex quota snapshot.
4. The glance percentage appears (5-hour for Plus when present, otherwise weekly).
5. The user clicks the floating widget to expand details, or uses the menu bar for settings actions.
6. The app refreshes automatically; normal current state stays visually quiet.

## Data Freshness

- Refresh on launch, detail-view open, wake from sleep, and network recovery.
- While visible, poll every 60 seconds by default.
- While menu-bar-only, poll every 60 seconds by default.
- After failures, keep the last successful value but mark it stale and retry with bounded backoff.
- “Live” means automatically refreshed ambient status, not a streaming billing meter.
- Normal current state stays visually quiet. A native right-click `立即刷新` action on the floating widget and detail panel provides recovery without restarting the app; the menu bar also exposes it. While refreshing, disable the action and show `正在刷新…`.

## States

- Loading: neutral placeholder, no fake percentage.
- Current: value and last-updated time are valid.
- Stale: cached value remains visible with a freshness warning.
- Logged out: explain that Codex CLI sign-in is required.
- Codex missing: show the detected-path problem and a concise fix.
- Unsupported protocol: explain that the installed Codex version does not expose quota data.
- No weekly window: show available windows without relabeling them as weekly. Plus with only a 5-hour window still shows that window as the glance metric.
- Plus without a 5-hour window: fall back to weekly glance; do not invent 5-hour remaining.
- Limit reached: show 0% and the reset time without alarming animation.

## Success Criteria

- Glance remaining quota (5-hour for Plus when present, weekly otherwise) is readable within one second without opening a full app window.
- Detail view opens in one click and includes reset time, plan, and reset opportunities.
- No credentials are read or stored by the app.
- Idle CPU remains effectively zero between refreshes; memory and energy impact are appropriate for a menu bar utility.
- The app recovers from Codex process exit, sleep/wake, and temporary network failure without restart.
- The floating widget behaves correctly across Spaces, full-screen apps, and multiple displays.

## Risks

- `codex app-server` is experimental and its schema can change between Codex releases.
- Spawning an external CLI complicates Mac App Store sandboxing.
- The server may expose integer-rounded values, so small usage changes may not appear immediately.
- Some plans may return different windows, missing fields, or multiple limit IDs.
