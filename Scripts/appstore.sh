#!/bin/bash
#
# Archives the sandboxed App Store build and exports a signed installer package.
#
#   ./Scripts/appstore.sh            export dist/Dejima-X.Y.Z-AppStore.pkg
#   ./Scripts/appstore.sh --upload   export, then upload the build to App Store Connect
#
# Builds the version HEAD is tagged with, so run ./Scripts/release.sh first to
# create the tag. The App Store build comes from the same commit as the DMG.
#
# CFBundleVersion must increase with every upload, even for the same version,
# so it defaults to a UTC timestamp such as 202610261530. Override it with
# BUILD_NUMBER=... when needed.
#
# Signing is automatic: Xcode creates the Apple Distribution certificate and
# App Store provisioning profile for the team. Sign in to Xcode under
# Settings → Accounts first, or use an App Store Connect API key:
#
#   ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8 \
#   ASC_KEY_ID=XXXXXXXXXX \
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#   ./Scripts/appstore.sh --upload
#
# Create the app record in App Store Connect (bundle ID com.nuki.Dejima)
# before the first upload.

set -euo pipefail

cd "$(dirname "$0")/.."

UPLOAD=0
case "${1:-}" in
    "") ;;
    --upload) UPLOAD=1 ;;
    *) echo "usage: $0 [--upload]" >&2; exit 1 ;;
esac

if [ -n "$(git status --porcelain)" ]; then
    echo "error: uncommitted changes. Commit or stash them first:" >&2
    git status --short >&2
    exit 1
fi

[ -f Dejima.xcodeproj/project.pbxproj ] || {
    echo "error: Dejima.xcodeproj is missing. Restore it from Git." >&2; exit 1
}
xcodebuild -version >/dev/null 2>&1 || {
    echo "error: select a full Xcode installation using xcode-select or DEVELOPER_DIR" >&2; exit 1
}

TAG=$(git tag --points-at HEAD --list 'v[0-9]*' | sort -V | tail -1)
[ -n "$TAG" ] || {
    echo "error: HEAD has no vX.Y.Z tag. Tag it with ./Scripts/release.sh X.Y.Z first." >&2
    echo "       (latest tag: $(git describe --tags --abbrev=0 2>/dev/null || echo none))" >&2
    exit 1
}
VERSION="${TAG#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: '$VERSION' is not a version like 0.3.0" >&2; exit 1
}

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
    echo "error: BUILD_NUMBER '$BUILD_NUMBER' must be up to three dot-separated integers" >&2; exit 1
}

# Both targets share one team; read it from the project instead of repeating it here.
teams=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM = ([A-Z0-9]{10});$/\1/p' Dejima.xcodeproj/project.pbxproj | sort -u)
[ "$(printf '%s\n' "$teams" | grep -c .)" -eq 1 ] || {
    echo "error: expected a single DEVELOPMENT_TEAM in the project, found: ${teams:-none}" >&2; exit 1
}
TEAM_ID="$teams"

auth_args=()
if [ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]; then
    [ -n "${ASC_KEY_PATH:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] || {
        echo "error: set all of ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID, or none" >&2; exit 1
    }
    [ -f "$ASC_KEY_PATH" ] || { echo "error: $ASC_KEY_PATH not found" >&2; exit 1; }
    auth_args=(-authenticationKeyPath "$ASC_KEY_PATH"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

BUILD="$PWD/build/appstore"
DIST="$PWD/dist"
ARCHIVE="$BUILD/Dejima.xcarchive"
PKG="$DIST/Dejima-$VERSION-AppStore.pkg"
SOURCE_PACKAGES="$PWD/build/SourcePackages"

# Show command output only on failure.
quiet() {
    local log="$BUILD/step.log"
    "$@" >"$log" 2>&1 || { echo "error: $1 failed" >&2; cat "$log" >&2; exit 1; }
}

export_options() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$1</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict></plist>
EOF
}

echo "==> Dejima $VERSION ($BUILD_NUMBER) for the App Store"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

# The App Store target has no package dependencies, but the project still
# references Sparkle, so resolve it from the pinned versions.
echo "==> Resolving packages"
quiet xcodebuild -resolvePackageDependencies -project Dejima.xcodeproj \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" -onlyUsePackageVersionsFromResolvedFile

echo "==> Archiving"
xcodebuild \
    -project Dejima.xcodeproj \
    -scheme "Dejima App Store" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD/dd" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
    -disableAutomaticPackageResolution \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ${auth_args[@]+"${auth_args[@]}"} \
    ONLY_ACTIVE_ARCH=NO \
    "MARKETING_VERSION=$VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    archive >"$BUILD/build.log" 2>&1 || {
    echo "error: Dejima failed to archive. Tail of $BUILD/build.log:" >&2
    tail -30 "$BUILD/build.log" >&2
    exit 1
}

# Catch configuration mistakes before App Review does.
APP="$ARCHIVE/Products/Applications/Dejima.app"
[ -d "$APP" ] || { echo "error: $APP missing from the archive" >&2; exit 1; }
INFO="$APP/Contents/Info.plist"

[ ! -e "$APP/Contents/Frameworks/Sparkle.framework" ] || {
    echo "error: Sparkle.framework is embedded in the App Store build" >&2; exit 1
}
if otool -L "$APP/Contents/MacOS/Dejima" | grep -q Sparkle; then
    echo "error: the App Store binary links Sparkle" >&2; exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print' "$INFO" | grep -q '^ *SU[A-Za-z]* = '; then
    echo "error: Sparkle settings remain in the App Store Info.plist" >&2; exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$INFO" >/dev/null 2>&1 || {
    echo "error: LSApplicationCategoryType is required for the App Store" >&2; exit 1
}

built_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
built_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")
[ "$built_version" = "$VERSION" ] && [ "$built_number" = "$BUILD_NUMBER" ] || {
    echo "error: built version $built_version ($built_number) doesn't match $VERSION ($BUILD_NUMBER)" >&2; exit 1
}
echo "    version:   $built_version ($built_number)"
echo "    minimum:   $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
echo "    sparkle:   not included"

echo "==> Exporting the installer package"
export_options export > "$BUILD/ExportOptions.plist"
quiet xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$BUILD/export" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" -allowProvisioningUpdates ${auth_args[@]+"${auth_args[@]}"}
[ -f "$BUILD/export/Dejima.pkg" ] || { echo "error: Dejima.pkg missing after export" >&2; exit 1; }

signature=$(pkgutil --check-signature "$BUILD/export/Dejima.pkg" 2>&1) || {
    echo "error: the installer package is not signed:" >&2
    printf '%s\n' "$signature" >&2
    exit 1
}
installer_identity=$(printf '%s\n' "$signature" | sed -nE 's/^[[:space:]]*1\. (.*)$/\1/p' | head -1)
echo "    installer: $installer_identity"

# Export re-signs for distribution, so check the app the package installs.
quiet pkgutil --expand-full "$BUILD/export/Dejima.pkg" "$BUILD/expanded"
SHIPPED_APP=$(find "$BUILD/expanded" -maxdepth 4 -type d -name Dejima.app | head -1)
[ -n "$SHIPPED_APP" ] || { echo "error: Dejima.app missing from the installer package" >&2; exit 1; }
codesign --verify --strict --deep "$SHIPPED_APP"
signing_details=$(codesign -dvv "$SHIPPED_APP" 2>&1)
printf '%s\n' "$signing_details" | grep -q '^Authority=Apple Distribution: ' || {
    echo "error: the packaged app is not signed with an Apple Distribution identity" >&2; exit 1
}
printf '%s\n' "$signing_details" | grep -q 'flags=.*runtime' || {
    echo "error: Dejima is missing hardened runtime" >&2; exit 1
}
entitlements=$(codesign -d --entitlements :- "$SHIPPED_APP" 2>/dev/null)
[ "$(printf '%s' "$entitlements" | plutil -extract com.apple.security.app-sandbox raw - 2>/dev/null)" = true ] || {
    echo "error: the App Store build is not sandboxed" >&2; exit 1
}
[ "$(printf '%s' "$entitlements" | plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null)" != true ] || {
    echo "error: the App Store build allows debugging (get-task-allow)" >&2; exit 1
}
echo "    signed by: $(printf '%s\n' "$signing_details" | sed -n 's/^Authority=//p' | head -1)"
echo "    sandbox:   on"
rm -rf "$BUILD/expanded"
mv -f "$BUILD/export/Dejima.pkg" "$PKG"

if [ "$UPLOAD" -eq 1 ]; then
    echo "==> Uploading to App Store Connect"
    export_options upload > "$BUILD/UploadOptions.plist"
    quiet xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$BUILD/upload" \
        -exportOptionsPlist "$BUILD/UploadOptions.plist" -allowProvisioningUpdates ${auth_args[@]+"${auth_args[@]}"}
    echo "    Uploaded. The build appears in App Store Connect after processing."
fi

echo
echo "==> Verified package"
echo "    $PKG"
if [ "$UPLOAD" -eq 0 ]; then
    echo
    echo "Upload with ./Scripts/appstore.sh --upload, or drag the package into Transporter."
fi
