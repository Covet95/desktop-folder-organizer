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
XCODEBUILD="${XCODEBUILD:-xcodebuild}"
ARCHS="${ARCHS:-arm64}"
MINIMUM_MACOS_VERSION="${MINIMUM_MACOS_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
APP_GROUP_ID="${APP_GROUP_ID:-}"

XCODE_PROJECT="$ROOT_DIR/DesktopFolderWidgetExtension.xcodeproj"
XCODE_SCHEME="DesktopFolderSummaryWidgetExtension"
XCODE_DERIVED_DATA="$BUILD_DIR/.widget-derived.$$"

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

if [[ -n "$TEAM_ID" && "$APP_GROUP_ID" != "$TEAM_ID".* ]]; then
    echo "A Personal Team App Group must start with the signing Team ID ($TEAM_ID)." >&2
    exit 2
fi

if [[ ! -d "$XCODE_PROJECT" ]]; then
    echo "Missing Xcode WidgetKit project: $XCODE_PROJECT" >&2
    exit 2
fi

APP_ENTITLEMENTS="$BUILD_DIR/.app-entitlements.$$"
WIDGET_ENTITLEMENTS="$BUILD_DIR/.widget-entitlements.$$"

cleanup() {
    if [[ -d "$BACKUP_APP" && ! -e "$APP" ]]; then
        mv "$BACKUP_APP" "$APP"
    fi
    rm -rf "$STAGING_APP" "$XCODE_DERIVED_DATA"
    rm -f "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
rm -rf "$STAGING_APP" "$BACKUP_APP" "$XCODE_DERIVED_DATA"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"

cp App.entitlements "$APP_ENTITLEMENTS"
cp WidgetExtension/WidgetExtension.entitlements "$WIDGET_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $APP_GROUP_ID" "$APP_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $APP_GROUP_ID" "$WIDGET_ENTITLEMENTS"

# Local Apple Development builds need a debuggable extension process.
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$WIDGET_ENTITLEMENTS"
fi

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

case "$ARCHS" in
    universal)
        compile_arch arm64 "$STAGING_APP/Contents/MacOS/$APP_NAME.arm64"
        compile_arch x86_64 "$STAGING_APP/Contents/MacOS/$APP_NAME.x86_64"
        lipo -create \
            "$STAGING_APP/Contents/MacOS/$APP_NAME.arm64" \
            "$STAGING_APP/Contents/MacOS/$APP_NAME.x86_64" \
            -output "$STAGING_APP/Contents/MacOS/$APP_NAME"
        rm "$STAGING_APP/Contents/MacOS/$APP_NAME.arm64" "$STAGING_APP/Contents/MacOS/$APP_NAME.x86_64"
        WIDGET_ARCHS="arm64 x86_64"
        ;;
    arm64|x86_64)
        compile_arch "$ARCHS" "$STAGING_APP/Contents/MacOS/$APP_NAME"
        WIDGET_ARCHS="$ARCHS"
        ;;
    *)
        echo "Unsupported ARCHS value: $ARCHS (use arm64, x86_64, or universal)" >&2
        exit 2
        ;;
esac

# Build the WidgetKit target with Xcode. WidgetKit extensions require the
# ExtensionKit entry point and linker settings supplied by the native target.
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
WIDGET_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' WidgetExtension/Info.plist)"
WIDGET_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' WidgetExtension/Info.plist)"

if [[ "$APP_VERSION" != "$WIDGET_VERSION" || "$APP_BUILD_NUMBER" != "$WIDGET_BUILD_NUMBER" ]]; then
    echo "Host app and WidgetKit extension versions/build numbers must match." >&2
    exit 2
fi

"$XCODEBUILD" \
    -quiet \
    -project "$XCODE_PROJECT" \
    -scheme "$XCODE_SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$XCODE_DERIVED_DATA" \
    ARCHS="$WIDGET_ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_ENTITLEMENTS="$WIDGET_ENTITLEMENTS" \
    INFOPLIST_FILE="$ROOT_DIR/WidgetExtension/Info.plist" \
    MACOSX_DEPLOYMENT_TARGET="$MINIMUM_MACOS_VERSION" \
    MARKETING_VERSION="$WIDGET_VERSION" \
    CURRENT_PROJECT_VERSION="$WIDGET_BUILD_NUMBER" \
    build

XCODE_WIDGET="$XCODE_DERIVED_DATA/Build/Products/Release/$WIDGET_NAME.appex"
if [[ ! -d "$XCODE_WIDGET" ]]; then
    echo "Xcode did not produce the WidgetKit extension: $XCODE_WIDGET" >&2
    exit 1
fi

mkdir -p "$(dirname "$WIDGET_BUNDLE")"
ditto "$XCODE_WIDGET" "$WIDGET_BUNDLE"

cp Info.plist "$STAGING_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGING_APP/Contents/Resources/AppIcon.icns"

# Keep the host app and WidgetKit extension on the same App Group.
# The extension bundle itself is produced by the native Xcode target.
/usr/libexec/PlistBuddy -c "Add :DFWAppGroupIdentifier string $APP_GROUP_ID" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DFWAppGroupIdentifier string $APP_GROUP_ID" "$WIDGET_BUNDLE/Contents/Info.plist"

# App extensions must be signed first, then their containing application.
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --entitlements "$WIDGET_ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" --timestamp=none --generate-entitlement-der \
        --strip-disallowed-xattrs "$WIDGET_BUNDLE"
    codesign --force --entitlements "$APP_ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" --timestamp=none --generate-entitlement-der \
        --strip-disallowed-xattrs "$STAGING_APP"
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
rm -rf "$BACKUP_APP" "$XCODE_DERIVED_DATA"
rm -f "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS"
trap - EXIT

echo "Built: $APP"
echo "Architectures: $ARCHS"
echo "WidgetKit extension: Xcode native target ($WIDGET_NAME.appex)"
echo "Minimum macOS: $MINIMUM_MACOS_VERSION"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
    echo "Signing: ad-hoc (local preview; team-backed widget sharing is unavailable)"
else
    echo "Signing: $CODESIGN_IDENTITY"
fi
echo "App Group: $APP_GROUP_ID"
