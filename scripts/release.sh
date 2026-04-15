#!/bin/bash
# MioIsland Release Script
# Usage: ./scripts/release.sh v2.0.2
#
# Ships unsigned builds with Sparkle EdDSA signing for auto-updates.
# Users must right-click → Open or run
# `xattr -dr com.apple.quarantine` on first launch. Gatekeeper + the
# Homebrew cask's postflight handle this transparently.
#
# Signing / notarization were removed after Apple's statusCode 7000
# server-side issue kept recurring and blocking releases.

set -e

VERSION="${1:?Usage: $0 <version>}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="$PROJECT_DIR/.sparkle-keys"
RELEASE_DIR="$PROJECT_DIR/releases"

# Auto-detect DerivedData path
DD_BASE="$HOME/Library/Developer/Xcode/DerivedData"
BUILD_DIR=$(find "$DD_BASE" -maxdepth 1 -name "ClaudeIsland-*" -type d 2>/dev/null | head -1)
if [ -z "$BUILD_DIR" ]; then
  echo "ERROR: No ClaudeIsland DerivedData found. Build the project first."
  exit 1
fi
BUILD_DIR="$BUILD_DIR/Build/Products/Release"
APP_PATH="$BUILD_DIR/Mio Island.app"
ZIP_PATH="$PROJECT_DIR/MioIsland-${VERSION}.zip"
DMG_PATH="$PROJECT_DIR/MioIsland-${VERSION}.dmg"

echo "=== MioIsland Release $VERSION ==="

# 1. Update version in Xcode project
CLEAN_VERSION="${VERSION#v}"  # v2.0.2 -> 2.0.2
echo ">>> Setting version to $CLEAN_VERSION..."
sed -i '' "s/MARKETING_VERSION = [0-9.]*/MARKETING_VERSION = $CLEAN_VERSION/g" \
  "$PROJECT_DIR/ClaudeIsland.xcodeproj/project.pbxproj"

# 2. Build (unsigned, universal)
#
# ARCHS + ONLY_ACTIVE_ARCH are critical: xcodebuild defaults to building
# only the current machine's architecture, which would ship an arm64-only
# binary to Intel Mac users — who then see "Mio Island can't be opened"
# with no recoverable error (xattr won't help, it's a pure architecture
# mismatch). Force a universal build so the same zip works on both archs.
echo ">>> Building Release (unsigned, universal arm64+x86_64)..."
cd "$PROJECT_DIR"
xcodebuild -scheme ClaudeIsland -configuration Release build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -1

# 3. Bundle built-in plugins into the .app.
BUNDLED_PLUGINS_SRC="$PROJECT_DIR/ClaudeIsland/Resources/Plugins"
BUNDLED_PLUGINS_DST="$APP_PATH/Contents/Resources/Plugins"
if [ -d "$BUNDLED_PLUGINS_SRC" ]; then
  echo ">>> Copying bundled plugins..."
  rm -rf "$BUNDLED_PLUGINS_DST"
  mkdir -p "$BUNDLED_PLUGINS_DST"
  for b in "$BUNDLED_PLUGINS_SRC"/*.bundle; do
    [ -d "$b" ] || continue
    cp -R "$b" "$BUNDLED_PLUGINS_DST/"
    echo "    $(basename "$b")"
  done
fi

# 4. Ad-hoc sign.
echo ">>> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_PATH"

# 5. Package ZIP (ALWAYS ditto, never zip — regular zip adds ._* AppleDouble files)
echo ">>> Packaging ZIP..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "    ZIP: $(du -h "$ZIP_PATH" | cut -f1)"

# 6. Create DMG with Applications link
echo ">>> Creating DMG..."
rm -f "$DMG_PATH"
if command -v create-dmg &> /dev/null; then
  create-dmg \
    --volname "Mio Island" \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Mio Island.app" 150 200 \
    --app-drop-link 450 200 \
    --hide-extension "Mio Island.app" \
    "$DMG_PATH" \
    "$APP_PATH" 2>&1 | tail -3
else
  DMG_STAGING=$(mktemp -d)
  cp -R "$APP_PATH" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"
  hdiutil create -volname "Mio Island" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
  rm -rf "$DMG_STAGING"
fi
echo "    DMG: $(du -h "$DMG_PATH" | cut -f1)"

# 7. Sparkle EdDSA signing
#    Signs the DMG so Sparkle can verify update integrity.
#    Requires .sparkle-keys/eddsa_private_key — run generate-keys.sh first.
SPARKLE_SIGN=""
POSSIBLE_SIGN_PATHS=(
  "$HOME/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
  "/usr/local/bin/sign_update"
)
for path_pattern in "${POSSIBLE_SIGN_PATHS[@]}"; do
  for path in $path_pattern; do
    if [ -x "$path" ]; then
      SPARKLE_SIGN="$path"
      break 2
    fi
  done
done

SPARKLE_SIG=""
if [ -n "$SPARKLE_SIGN" ] && [ -f "$KEYS_DIR/eddsa_private_key" ]; then
  echo ">>> Signing DMG with Sparkle EdDSA..."
  SPARKLE_SIG=$("$SPARKLE_SIGN" "$DMG_PATH" --ed-key-file "$KEYS_DIR/eddsa_private_key" 2>&1)
  echo "    Signature: ${SPARKLE_SIG:0:40}..."
elif [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
  echo ">>> SKIP Sparkle signing: no key at $KEYS_DIR/eddsa_private_key"
  echo "    Run ./scripts/generate-keys.sh to set up Sparkle signing"
else
  echo ">>> SKIP Sparkle signing: sign_update tool not found"
  echo "    Build the project in Xcode first to download Sparkle package"
fi

# 8. Generate appcast.xml
mkdir -p "$RELEASE_DIR"
DMG_SIZE=$(stat -f%z "$DMG_PATH")
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
DOWNLOAD_URL="https://github.com/MioMioOS/MioIsland/releases/download/${VERSION}/MioIsland-${VERSION}.dmg"

# Parse sparkleEdSignature and sparkleLength from sign_update output
ED_SIG=$(echo "$SPARKLE_SIG" | grep -oE 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//' || true)
SIG_LENGTH=$(echo "$SPARKLE_SIG" | grep -oE 'length="[^"]*"' | sed 's/length="//;s/"//' || true)
[ -z "$SIG_LENGTH" ] && SIG_LENGTH="$DMG_SIZE"

echo ">>> Generating appcast.xml..."
cat > "$APPCAST_PATH" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mio Island Updates</title>
    <link>https://miomioos.github.io/MioIsland/appcast.xml</link>
    <description>Mio Island update feed</description>
    <language>en</language>
    <item>
      <title>Mio Island $CLEAN_VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$CLEAN_VERSION</sparkle:version>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        length="$SIG_LENGTH"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIG"
      />
    </item>
  </channel>
</rss>
APPCAST_EOF
echo "    Appcast: $APPCAST_PATH"

# 9. Deploy appcast.xml to landing-page branch (GitHub Pages)
echo ">>> Deploying appcast.xml to landing-page..."
CURRENT_BRANCH=$(git branch --show-current)
git stash --quiet 2>/dev/null || true
git checkout landing-page --quiet 2>/dev/null
cp "$APPCAST_PATH" "$PROJECT_DIR/landing/public/appcast.xml"
git add "$PROJECT_DIR/landing/public/appcast.xml"
git commit -m "chore: update appcast.xml for $VERSION" --quiet || true
git push origin landing-page --quiet 2>/dev/null || echo "    (push landing-page manually: git push origin landing-page)"
git checkout "$CURRENT_BRANCH" --quiet 2>/dev/null
git stash pop --quiet 2>/dev/null || true
echo "    Deployed to landing/public/appcast.xml"

# 10. Commit version bump and tag
echo ">>> Tagging $VERSION..."
git add "$PROJECT_DIR/ClaudeIsland.xcodeproj/project.pbxproj"
git commit -m "$VERSION: Release" --allow-empty || true
git tag "$VERSION"

echo ""
echo "=== Done! ==="
echo "DMG:     $DMG_PATH"
echo "ZIP:     $ZIP_PATH"
echo "Appcast: $APPCAST_PATH (deployed to GitHub Pages)"
echo ""
echo "Next steps:"
echo "  git push origin main --tags"
echo "  gh release create $VERSION \"$DMG_PATH\" \"$ZIP_PATH\" --title \"$VERSION — Mio Island\""
