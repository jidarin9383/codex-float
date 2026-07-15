# Contributing to Codex Float

Thanks for helping improve Codex Float.

## Development setup

1. macOS 14+, Xcode 16+ / Swift 6
2. Clone and open the package:

   ```bash
   git clone https://github.com/jidarin9383/codex-float.git
   cd codex-float
   ./scripts/open-xcode.sh
   ```

3. Run unit and smoke tests:

   ```bash
   swift test
   swift run CodexFloatCoreSmokeTests
   ```

4. Optional live protocol probe (needs local Codex login):

   ```bash
   CODEX_FLOAT_LIVE_PROTOCOL=1 swift run CodexFloatCoreSmokeTests
   ```

5. Package a local `.app`:

   ```bash
   ./scripts/package-app.sh
   ```

   This produces a universal `arm64` + `x86_64` app and `macos-universal.zip` archive.

## Project rules

- Prefer small native architecture: protocol client → repository → main-actor UI.
- Never log, copy, or persist Codex credentials / tokens.
- Launch `codex` with `Process` and structured arguments (no shell strings).
- User-facing UI copy stays **Simplified Chinese**.
- Commit messages and technical docs stay **English**.
- Do not invent a 5-hour window when Codex only returns a weekly window.
- Avoid third-party dependencies unless the standard library cannot meet a need.

Sources of truth: `PRD.md`, `Tech-Spec.md`, `DESIGN.md`, `AGENTS.md`.

## Pull requests

1. Keep PRs focused and reversible.
2. Run `swift build`, `swift test`, and `swift run CodexFloatCoreSmokeTests` before opening a PR.
3. Describe what changed and why; link related issues.
4. Do not commit `.build/`, `dist/`, credentials, or local quota history.

## Reporting issues

Please include:

- macOS version
- Codex CLI version (`codex --version`) if quota-related
- Whether the issue is UI, packaging, or protocol
- Steps to reproduce (no secrets)

## Security / privacy

If you believe you found a credential-handling issue, open a private security advisory if available, or contact the maintainer without pasting tokens or `auth.json` contents.
