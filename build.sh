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
TEAM_ID="${TEAM_ID:-}"
APP_GROUP_ID="${APP_GROUP_ID:-}"

if [[ -n "$TEAM_ID" && ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "TEAM_ID must be the 10-character Apple Developer Team ID." >&2
    exit 2
fi

if [[ -n "$TEAM_ID" ]]; then
    APP_GROUP_ID="${APP_GROUP_ID:-$TEAM_ID.com.covet.DesktopFolderWidget}"
else
    APP_GROUP_ID="${APP_GROUP_ID:-group.com.covet.DesktopFolderWidget}"
fi

if [[ -n "$CODESIGN_IDENTITY" && -z "$TEAM_ID" ]]; then
    echo "TEAM_ID is required for a team-signed WidgetKit build." >&2
    echo "Use the Team ID shown in Xcode > Settings > Accounts." >&2
    exit 2
fi

if [[ ! "$APP_GROUP_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "APP_GROUP_ID contains unsupported characters." >&2
    exit 2
fi

APP_ENTITLEMENTS="$BUILD_DIR/.app-entitlements.$$"
WIDGET_ENTITLEMENTS="$BUILD_DIR/.widget-entitlements.$$"

cleanup() {
    if [[ -d "$BACKUP_APP" && ! -e "$APP" ]]; then
        mv "$BACKUP_APP" "$APP"
    fi
    rm -rf "$STAGING_APP"
    rm -f "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"
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

# Keep the host app, WidgetKit extension, and signed entitlements on one group ID.
cp App.entitlements "$APP_ENTITLEMENTS"
cp WidgetExtension/WidgetExtension.entitlements "$WIDGET_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $APP_GROUP_ID" "$APP_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $APP_GROUP_ID" "$WIDGET_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :DFWAppGroupIdentifier string $APP_GROUP_ID" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DFWAppGroupIdentifier string $APP_GROUP_ID" "$WIDGET_BUNDLE/Contents/Info.plist"

# App extensions must be signed first, then their containing application.
# Apple Development signing is sufficient for this Mac-only build; no Developer ID
# certificate, notarization, or hardened-runtime distribution setup is required.
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --entitlements "$WIDGET_ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" "$WIDGET_BUNDLE"
    codesign --force --entitlements "$APP_ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" "$STAGING_APP"
else
    codesign --force --entitlements "$WIDGET_ENTITLEMENTS" --sign - "$WIDGET_BUNDLE"
    codesign --force --entitlements "$APP_ENTITLEMENTS" --sign - "$STAGING_APP"
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    for signed_bundle in "$WIDGET_BUNDLE" "$STAGING_APP"; do
        signed_team_id="$(codesign -dv --verbose=4 "$signed_bundle" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
        if [[ "$signed_team_id" != "$TEAM_ID" ]]; then
            echo "Signing team mismatch for $signed_bundle: expected $TEAM_ID, got ${signed_team_id:-none}." >&2
            exit 1
        fi
    done
fi

codesign --verify --deep --strict "$STAGING_APP"

# Replace the previous app only after compilation and signing have succeeded.
if [[ -e "$APP" ]]; then
    mv "$APP" "$BACKUP_APP"
fi
mv "$STAGING_APP" "$APP"
rm -rf "$BACKUP_APP"
rm -f "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"
trap - EXIT

echo "Built: $APP"
echo "Architectures: $ARCHS"
echo "WidgetKit extension: $WIDGET_NAME.appex"
echo "Minimum macOS: $MINIMUM_MACOS_VERSION"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
    echo "Signing: ad-hoc (local preview; team-backed widget sharing is unavailable)"
else
    echo "Signing: $CODESIGN_IDENTITY"
fi
echo "App Group: $APP_GROUP_ID"
