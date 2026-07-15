## Codex Float 0.1.0

First public open-source release of **Codex Float** — a native macOS menu bar + floating widget for weekly Codex remaining quota.

### Highlights

- Live quota via local `codex app-server` (`account/rateLimits/read`)
- Menu bar (Ocean Mist brand) + battery-style floating capsule
- Detail sheet: 下次重置 · 当前套餐 · 重置机会（可展开到期日）
- Launch at login, single-instance guard, 60s poll + failure backoff
- Optional reset-credit expiry dates (in-memory token only; never logged)
- In-app “检查更新” against this GitHub repo’s Releases
- Ad-hoc signed `.app` for Apple Silicon

### Install

1. Download `CodexFloat-0.1.0-macos-arm64.zip`
2. Unzip → drag **Codex Float.app** to `/Applications`
3. If Gatekeeper blocks: right-click → **Open** → **Open**
4. Requires a logged-in [Codex CLI](https://github.com/openai/codex) on the same Mac

### Notes

- Not Developer ID signed / notarized yet (open-source path)
- Intel Macs: build from source with `./scripts/package-app.sh`
- Not affiliated with OpenAI
