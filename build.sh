#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="DesktopFolderWidget"
BUNDLE_NAME="文档整理"
BUILD_DIR="build"
APP="$BUILD_DIR/$BUNDLE_NAME.app"
STAGING_APP="$BUILD_DIR/.$BUNDLE_NAME.app.staging.$$"
BACKUP_APP="$BUILD_DIR/.$BUNDLE_NAME.app.backup.$$"

SWIFTC="${SWIFTC:-swiftc}"
ARCHS="${ARCHS:-arm64}"
MINIMUM_MACOS_VERSION="${MINIMUM_MACOS_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

cleanup() {
    if [[ -d "$BACKUP_APP" && ! -e "$APP" ]]; then
        mv "$BACKUP_APP" "$APP"
    fi
    rm -rf "$STAGING_APP"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"

compile_arch() {
    local arch="$1"
    local output="$2"
    "$SWIFTC" \
        -target "$arch-apple-macosx$MINIMUM_MACOS_VERSION" \
        -swift-version 5 \
        -O \
        -parse-as-library \
        Sources/*.swift \
        -o "$output"
}

case "$ARCHS" in
    universal)
        compile_arch arm64 "$STAGING_APP/Contents/MacOS/$APP_NAME.arm64"
        compile_arch x86_64 "$STAGING_APP/Contents/MacOS/$APP_NAME.x86_64"
        lipo -create \
            "$STAGING_APP/Contents/MacOS/$APP_NAME.arm64" \
            "$STAGING_APP/Contents/MacOS/$APP_NAME.x86_64" \
            -output "$STAGING_APP/Contents/MacOS/$APP_NAME"
        rm "$STAGING_APP/Contents/MacOS/$APP_NAME.arm64" "$STAGING_APP/Contents/MacOS/$APP_NAME.x86_64"
        ;;
    arm64|x86_64)
        compile_arch "$ARCHS" "$STAGING_APP/Contents/MacOS/$APP_NAME"
        ;;
    *)
        echo "Unsupported ARCHS value: $ARCHS (use arm64, x86_64, or universal)" >&2
        exit 2
        ;;
esac

cp Info.plist "$STAGING_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGING_APP/Contents/Resources/AppIcon.icns"

# Personal-use release: the interactive AppKit panel is the only UI target.
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$STAGING_APP"
else
    codesign --force --sign - "$STAGING_APP"
fi

codesign --verify --deep --strict "$STAGING_APP"

# Keep the previous output if compilation or signing fails.
if [[ -e "$APP" ]]; then
    mv "$APP" "$BACKUP_APP"
fi
mv "$STAGING_APP" "$APP"
rm -rf "$BACKUP_APP"
trap - EXIT

echo "Built: $APP"
echo "Architectures: $ARCHS"
echo "Minimum macOS: $MINIMUM_MACOS_VERSION"
echo "Signing: ${CODESIGN_IDENTITY:-ad-hoc}"
