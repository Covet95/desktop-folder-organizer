#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="DesktopFolderWidget"
WIDGET_NAME="DesktopFolderSummaryWidgetExtension"
BUNDLE_NAME="文档整理"
BUILD_DIR="build"
APP="$BUILD_DIR/$BUNDLE_NAME.app"
STAGING_APP="$BUILD_DIR/.$BUNDLE_NAME.app.staging.$$"
BACKUP_APP="$BUILD_DIR/.$BUNDLE_NAME.app.backup.$$"
WIDGET_BUNDLE="$STAGING_APP/Contents/PlugIns/$WIDGET_NAME.appex"

SWIFTC="${SWIFTC:-swiftc}"
ARCHS="${ARCHS:-universal}"
MINIMUM_MACOS_VERSION="${MINIMUM_MACOS_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

cleanup() {
    if [[ -d "$BACKUP_APP" && ! -e "$APP" ]]; then
        mv "$BACKUP_APP" "$APP"
    fi
    rm -rf "$STAGING_APP"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
rm -rf "$STAGING_APP" "$BACKUP_APP"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$WIDGET_BUNDLE/Contents/MacOS"

compile_arch() {
    local arch="$1"
    local output="$2"
    "$SWIFTC" \
        -target "$arch-apple-macosx$MINIMUM_MACOS_VERSION" \
        -swift-version 5 \
        -O \
        -parse-as-library \
        Sources/*.swift Shared/*.swift \
        -o "$output"
}

compile_widget_arch() {
    local arch="$1"
    local output="$2"
    "$SWIFTC" \
        -target "$arch-apple-macosx$MINIMUM_MACOS_VERSION" \
        -swift-version 5 \
        -O \
        -application-extension \
        -parse-as-library \
        Shared/*.swift WidgetExtension/*.swift \
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
        compile_widget_arch arm64 "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME.arm64"
        compile_widget_arch x86_64 "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME.x86_64"
        lipo -create \
            "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME.arm64" \
            "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME.x86_64" \
            -output "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME"
        rm "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME.arm64" "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME.x86_64"
        ;;
    arm64|x86_64)
        compile_arch "$ARCHS" "$STAGING_APP/Contents/MacOS/$APP_NAME"
        compile_widget_arch "$ARCHS" "$WIDGET_BUNDLE/Contents/MacOS/$WIDGET_NAME"
        ;;
    *)
        echo "Unsupported ARCHS value: $ARCHS (use arm64, x86_64, or universal)" >&2
        exit 2
        ;;
esac

cp Info.plist "$STAGING_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGING_APP/Contents/Resources/AppIcon.icns"
cp WidgetExtension/Info.plist "$WIDGET_BUNDLE/Contents/Info.plist"

# App extensions must be signed first, then their containing application.
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --entitlements WidgetExtension/WidgetExtension.entitlements \
        --sign "$CODESIGN_IDENTITY" "$WIDGET_BUNDLE"
    codesign --force --options runtime --timestamp --entitlements App.entitlements \
        --sign "$CODESIGN_IDENTITY" "$STAGING_APP"
else
    codesign --force --entitlements WidgetExtension/WidgetExtension.entitlements --sign - "$WIDGET_BUNDLE"
    codesign --force --entitlements App.entitlements --sign - "$STAGING_APP"
fi

codesign --verify --deep --strict "$STAGING_APP"

# Replace the previous app only after compilation and signing have succeeded.
if [[ -e "$APP" ]]; then
    mv "$APP" "$BACKUP_APP"
fi
mv "$STAGING_APP" "$APP"
rm -rf "$BACKUP_APP"
trap - EXIT

echo "Built: $APP"
echo "Architectures: $ARCHS"
echo "WidgetKit extension: $WIDGET_NAME.appex"
echo "Minimum macOS: $MINIMUM_MACOS_VERSION"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
    echo "Signing: ad-hoc (local testing only; not suitable for public distribution)"
else
    echo "Signing: $CODESIGN_IDENTITY"
fi
