#!/usr/bin/env bash
#
# release.sh — cut a signed, auto-updatable Claude Gusage release.
#
# Usage:  make release VERSION=1.1.2
#     or: bash macos/scripts/release.sh 1.1.2
#
# What it does, end to end:
#   1. Builds the .app, a Sparkle .zip, and a drag-to-Applications .dmg — with
#      the update feed URL baked into the bundle (SU_FEED_URL).
#   2. Signs the zip and (re)generates appcast.xml with generate_appcast, using
#      the private EdDSA key exported to ~/.config/claude-gusage/.
#   3. Publishes a GitHub Release with ClaudeGusage.dmg (manual install) and
#      ClaudeGusage.zip (what Sparkle downloads).
#   4. Commits & pushes appcast.xml so the live feed points at the new release.
#
# Installed copies from a previous feed-enabled release then pick the update up
# automatically. NOTE: the very first feed-enabled build must be installed
# manually once — older builds don't know the feed URL yet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MACOS_DIR/.." && pwd)"
BIN="$MACOS_DIR/.build/artifacts/sparkle/Sparkle/bin"
KEY_FILE="${SPARKLE_ED_KEY_FILE:-$HOME/.config/claude-gusage/sparkle_ed_private_key.pem}"

# --- Repo / feed identity -----------------------------------------------------
REPO_SLUG="dagdelenardic-ops/claude-gusage"
FEED_URL="https://raw.githubusercontent.com/$REPO_SLUG/main/appcast.xml"
ASSET_ZIP="ClaudeGusage.zip"   # the enclosure Sparkle downloads
ASSET_DMG="ClaudeGusage.dmg"   # the file humans drag into Applications

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Error: version required, e.g. 'make release VERSION=1.1.2'" >&2
    exit 1
fi
VERSION="${VERSION#v}"
TAG="v$VERSION"
DL_PREFIX="https://github.com/$REPO_SLUG/releases/download/$TAG/"

[[ -f "$KEY_FILE" ]] || { echo "Error: signing key not found at $KEY_FILE" >&2; exit 1; }
[[ -x "$BIN/generate_appcast" ]] || { echo "Error: Sparkle tools missing — run 'swift build' first." >&2; exit 1; }

echo "==> Releasing Claude Gusage $TAG"

# --- 1. Build (feed URL + version baked in) -----------------------------------
export SU_FEED_URL="$FEED_URL"
APP_VERSION="$VERSION" bash "$SCRIPT_DIR/build.sh" --zip --dmg
bash "$SCRIPT_DIR/verify-release.sh" "$MACOS_DIR/ClaudeUsageBar.zip"
bash "$SCRIPT_DIR/verify-release.sh" "$MACOS_DIR/ClaudeUsageBar.dmg"

# --- 2. Stage archives under friendly names + generate the appcast ------------
STAGE="$MACOS_DIR/dist"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$MACOS_DIR/ClaudeUsageBar.zip" "$STAGE/$ASSET_ZIP"
cp "$MACOS_DIR/ClaudeUsageBar.dmg" "$STAGE/$ASSET_DMG"

# generate_appcast only signs archives it finds in the folder; keep the DMG out
# of the signing folder so it doesn't produce a second enclosure.
APPCAST_SRC="$STAGE/appcast-src"
mkdir -p "$APPCAST_SRC"
cp "$STAGE/$ASSET_ZIP" "$APPCAST_SRC/$ASSET_ZIP"

"$BIN/generate_appcast" \
    --ed-key-file "$KEY_FILE" \
    --download-url-prefix "$DL_PREFIX" \
    -o "$REPO_DIR/appcast.xml" \
    "$APPCAST_SRC"

echo "==> appcast.xml written:"
grep -E "sparkle:version|enclosure url" "$REPO_DIR/appcast.xml" | tail -4

# --- 3. Publish the GitHub Release (zip is the Sparkle enclosure) --------------
gh release create "$TAG" \
    "$STAGE/$ASSET_DMG" \
    "$STAGE/$ASSET_ZIP" \
    --repo "$REPO_SLUG" \
    --title "Claude Gusage $VERSION" \
    --notes "Auto-updating build. Download **$ASSET_DMG**, drag it into Applications, then right-click → Open on first launch. Previously installed feed builds update themselves."

# --- 4. Push the updated feed so installed copies can see it -------------------
git -C "$REPO_DIR" add appcast.xml
git -C "$REPO_DIR" commit -m "Release $TAG: update Sparkle appcast"
git -C "$REPO_DIR" push origin main

echo "==> Done. $TAG is live and the feed is updated."
