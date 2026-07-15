#!/bin/zsh
# Build a distributable Codex Float.app (ad-hoc signed) + zip for GitHub Releases.
#
# Env:
#   VERSION                  marketing version (default: Info.plist CFBundleShortVersionString)
#   BUILD_NUMBER             CFBundleVersion (default: 1 or GITHUB_RUN_NUMBER)
#   CODEX_FLOAT_GITHUB_REPO  owner/repo for in-app update checks (optional)
#   CONFIGURATION            debug|release (default: release)
#   SKIP_ICON                1 to reuse existing Assets/AppIcon.icns
#   OUTPUT_DIR               default: <repo>/dist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: packaging requires macOS" >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  # Fall back to active CLT / Xcode selection.
  unset DEVELOPER_DIR
fi

CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
APP_NAME="Codex Float"
EXEC_NAME="CodexFloat"
BUNDLE_ID="app.codexfloat.mac"
SOURCE_PLIST="$ROOT/Sources/CodexFloat/Info.plist"
ICON_ICNS="$ROOT/Assets/AppIcon.icns"

if [[ ! -f "$SOURCE_PLIST" ]]; then
  echo "error: missing $SOURCE_PLIST" >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST" 2>/dev/null || echo "0.1.0")"
fi
if [[ -z "${BUILD_NUMBER:-}" ]]; then
  BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARCH_LABEL="arm64" ;;
  x86_64) ARCH_LABEL="x86_64" ;;
  *) ARCH_LABEL="$ARCH" ;;
esac

echo "==> Codex Float package"
echo "    version=$VERSION build=$BUILD_NUMBER config=$CONFIGURATION arch=$ARCH_LABEL"
echo "    github_repo=${CODEX_FLOAT_GITHUB_REPO:-"(unset)"}"

echo "→ building $EXEC_NAME ($CONFIGURATION)…"
if [[ "$CONFIGURATION" == "release" ]]; then
  swift build -c release --product "$EXEC_NAME"
  BIN="$ROOT/.build/release/$EXEC_NAME"
else
  swift build -c debug --product "$EXEC_NAME"
  BIN="$ROOT/.build/debug/$EXEC_NAME"
fi

if [[ ! -x "$BIN" ]]; then
  # SPM may nest under triple directory.
  BIN="$(find "$ROOT/.build" -type f -name "$EXEC_NAME" -path "*/$CONFIGURATION/*" | head -1)"
fi
if [[ ! -x "$BIN" ]]; then
  echo "error: built binary not found" >&2
  exit 1
fi
echo "    binary=$BIN"

if [[ "${SKIP_ICON:-0}" != "1" ]] || [[ ! -f "$ICON_ICNS" ]]; then
  echo "→ generating AppIcon.icns…"
  "$ROOT/scripts/make-app-icon.sh" "$ROOT/Assets/Brand/v2/app-icon.svg" "$ICON_ICNS"
else
  echo "→ reusing $ICON_ICNS"
fi

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "→ assembling $APP_DIR"
cp "$BIN" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Build Info.plist from source + packaging overrides.
PACK_PLIST="$APP_DIR/Contents/Info.plist"
cp "$SOURCE_PLIST" "$PACK_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PACK_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PACK_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${EXEC_NAME}" "$PACK_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "$PACK_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName '${APP_NAME}'" "$PACK_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string '${APP_NAME}'" "$PACK_PLIST"
if /usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$PACK_PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '${APP_NAME}'" "$PACK_PLIST"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '${APP_NAME}'" "$PACK_PLIST"
fi
if /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$PACK_PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$PACK_PLIST"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PACK_PLIST"
fi
if [[ -n "${CODEX_FLOAT_GITHUB_REPO:-}" ]]; then
  if /usr/libexec/PlistBuddy -c "Print :CodexFloatGitHubRepo" "$PACK_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CodexFloatGitHubRepo '${CODEX_FLOAT_GITHUB_REPO}'" "$PACK_PLIST"
  else
    /usr/libexec/PlistBuddy -c "Add :CodexFloatGitHubRepo string '${CODEX_FLOAT_GITHUB_REPO}'" "$PACK_PLIST"
  fi
fi

plutil -lint "$PACK_PLIST" >/dev/null

# Minimal PkgInfo for classic bundles.
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "→ ad-hoc codesign…"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/    /'

ZIP_NAME="CodexFloat-${VERSION}-macos-${ARCH_LABEL}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
echo "→ zipping $ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "✓ package ready"
echo "  app: $APP_DIR"
echo "  zip: $ZIP_PATH"
echo
echo "Install: unzip and drag “$APP_NAME.app” to /Applications."
echo "If Gatekeeper blocks: right-click the app → Open → Open."
echo "Run: open \"$APP_DIR\""
