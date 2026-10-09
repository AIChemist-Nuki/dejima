#!/bin/bash
#
# Builds both targets and packages them into one DMG.
#
#   ./Scripts/release.sh 0.3.0    tag HEAD as v0.3.0, then build it
#   ./Scripts/release.sh          build the version HEAD is already tagged with
#
# Uses the git tag for the version and the commit count for the build number.
# Requires a clean working tree. Tags are created locally; push them separately:
#
#   git push origin main v0.3.0
#
# Each macOS build is packaged as Dejima.app in its own folder.
# Scripts/dmg-window.swift generates the backgrounds and Finder layouts.
#
# Public distribution requires Developer ID signing and notarization.
# Otherwise the script uses the project's signing settings:
#
#   CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=dejima \
#   ./Scripts/release.sh
#
# Store notarization credentials before publishing:
#
#   xcrun notarytool store-credentials dejima \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
    echo "error: uncommitted changes. Commit or stash them first:" >&2
    git status --short >&2
    exit 1
fi

if [ $# -gt 0 ]; then
    VERSION="${1#v}"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "error: '$1' is not a version like 0.3.0" >&2; exit 1
    }
    if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
        echo "error: tag v$VERSION already exists" >&2
        exit 1
    fi
    git tag "v$VERSION"
    echo "==> Tagged HEAD as v$VERSION"
else
    TAG=$(git tag --points-at HEAD --list 'v[0-9]*' | sort -V | tail -1)
    [ -n "$TAG" ] || {
        echo "error: HEAD has no vX.Y.Z tag. Pass the new version: ./Scripts/release.sh 0.3.0" >&2
        echo "       (latest tag: $(git describe --tags --abbrev=0 2>/dev/null || echo none))" >&2
        exit 1
    }
    VERSION="${TAG#v}"
fi
BUILD_NUMBER=$(git rev-list --count HEAD)

BUILD="$PWD/build/release"
STAGE="$BUILD/dmg"
DIST="$PWD/dist"
DMG="$DIST/Dejima-$VERSION.dmg"

# The layout uses these names to position icons. Finder displays localized
# names from the .localized directories created below.
FOLDER_NEW="macOS 26+.localized"
FOLDER_OLD="macOS 15-25.localized"

ICON="$PWD/Assets.xcassets/AppIcon.appiconset/icon_512.png"

command -v xcodegen >/dev/null || { echo "error: xcodegen not installed (brew install xcodegen)" >&2; exit 1; }

# Show command output only on failure.
quiet() {
    local log="$BUILD/step.log"
    "$@" >"$log" 2>&1 || { echo "error: $1 failed" >&2; cat "$log" >&2; exit 1; }
}

# Keep the Swift module cache inside the writable build directory.
swift_tool() {
    quiet swift -module-cache-path "$BUILD/module-cache" "$@"
}

echo "==> Dejima $VERSION ($BUILD_NUMBER)"
rm -rf "$BUILD"
mkdir -p "$STAGE" "$DIST"
xcodegen generate >/dev/null

# $1 scheme, $2 built product name, $3 folder inside the DMG
build_one() {
    local scheme="$1" product="$2" folder="$3"
    echo "==> Building $scheme"

    local args=(
        -project Dejima.xcodeproj
        -scheme "$scheme"
        -configuration Release
        -derivedDataPath "$BUILD/dd-$scheme"
        # Allow Xcode to update signing assets when using automatic signing.
        -allowProvisioningUpdates
        "MARKETING_VERSION=$VERSION"
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
    )
    if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
        # Developer ID needs no provisioning profile for a non-sandboxed app
        # distributed outside the App Store, so manual signing is enough.
        args+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
    fi
    xcodebuild "${args[@]}" build >"$BUILD/$scheme.log" 2>&1 || {
        echo "error: $scheme failed to build. Tail of $BUILD/$scheme.log:" >&2
        tail -30 "$BUILD/$scheme.log" >&2
        exit 1
    }

    local app="$BUILD/dd-$scheme/Build/Products/Release/$product.app"
    [ -d "$app" ] || { echo "error: $app missing after a successful build" >&2; exit 1; }

    mkdir -p "$STAGE/$folder"
    cp -R "$app" "$STAGE/$folder/Dejima.app"
    ln -s /Applications "$STAGE/$folder/Applications"

    codesign --verify --strict --deep "$STAGE/$folder/Dejima.app"
    echo "    signed by: $(codesign -dvv "$STAGE/$folder/Dejima.app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    echo "    version:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGE/$folder/Dejima.app/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$STAGE/$folder/Dejima.app/Contents/Info.plist"))"
    echo "    minimum:   $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$STAGE/$folder/Dejima.app/Contents/Info.plist")"
}

build_one Dejima   Dejima   "$FOLDER_OLD"
build_one Dejima26 Dejima26 "$FOLDER_NEW"

# $1 folder, followed by language/name pairs for Finder's .localized lookup.
localize_folder() {
    local folder="$1"; shift
    local key="${folder%.localized}"
    mkdir -p "$STAGE/$folder/.localized"
    while [ $# -gt 0 ]; do
        printf '"%s" = "%s";\n' "$key" "$2" >"$STAGE/$folder/.localized/$1.strings"
        shift 2
    done
}
localize_folder "$FOLDER_NEW" en "macOS 26 or later" zh-Hans "macOS 26 或更新" \
    ja "macOS 26 以降" ko "macOS 26 이상"
localize_folder "$FOLDER_OLD" en "macOS 15 to 25" zh-Hans "macOS 15 到 25" \
    ja "macOS 15〜25" ko "macOS 15~25"

echo "==> Drawing the window backgrounds"
mkdir -p "$STAGE/.background"
swift_tool Scripts/dmg-window.swift art "$STAGE/.background" "$VERSION" "$ICON"
# Combine 1x and 2x backgrounds into a single HiDPI TIFF for Finder.
for art in root folder; do
    quiet tiffutil -cathidpicheck \
        "$STAGE/.background/$art.png" "$STAGE/.background/$art@2x.png" \
        -out "$STAGE/.background/$art.tiff"
    rm -f "$STAGE/.background/$art.png" "$STAGE/.background/$art@2x.png"
done

# Encode the Apple logo (U+F8FF) explicitly to preserve it in source editors.
APPLE_LOGO=$(printf '\xef\xa3\xbf')
cat > "$STAGE/Read Me.txt" <<EOF
Dejima $VERSION
https://github.com/AIChemist-Nuki/dejima


========================================
中文
========================================

两个版本，装一个就行

    macOS 26 或更新
    macOS 15 到 25

不知道自己是哪个版本：点屏幕左上角的 ${APPLE_LOGO} → 关于本机。

打开对应的文件夹，把 Dejima.app 拖到旁边的 Applications 上。

遇到问题
· 打开时提示需要更新的 macOS：改装「macOS 15 到 25」文件夹里的版本。
· 连按两下 ⌘C 没反应：菜单栏图标 → 授予辅助功能权限…
· 提示语言模型没下载：菜单栏图标 → 查看语言模型…

翻译全程在本地完成，不经过任何服务器。


========================================
English
========================================

Two builds, install one

    macOS 26 or later
    macOS 15 to 25

Not sure which macOS you have: click ${APPLE_LOGO} in the top-left corner of the screen
→ About This Mac.

Open the matching folder, drag Dejima.app onto the Applications alias beside it.

If something goes wrong
· Says it needs a newer macOS: install the one in the “macOS 15 to 25” folder.
· Pressing ⌘C twice does nothing: menu bar icon → Grant Accessibility access…
· Says a language model isn't downloaded: menu bar icon → Check language models…

Translation happens entirely on device. Nothing you translate reaches a server.


========================================
日本語
========================================

2つのビルド、片方だけ入れてください

    macOS 26 以降
    macOS 15〜25

macOS のバージョンがわからない場合: 画面左上の ${APPLE_LOGO} → このMacについて。

対応するフォルダを開き、Dejima.app を隣の Applications にドラッグします。

困ったときは
・新しい macOS が必要と表示される: 「macOS 15〜25」フォルダの方を入れてください。
・⌘C を2回押しても反応しない: メニューバーアイコン → アクセシビリティ権限を与える…
・言語モデルがないと表示される: メニューバーアイコン → 言語モデルを確認…

翻訳はすべて端末内で完結します。サーバーには何も送りません。


========================================
한국어
========================================

두 가지 빌드가 있습니다. 하나만 설치하세요

    macOS 26 이상
    macOS 15~25

macOS 버전을 모르겠다면: 화면 왼쪽 위의 ${APPLE_LOGO} → 이 Mac에 관하여.

맞는 폴더를 열고 Dejima.app을 옆에 있는 Applications로 드래그하세요.

문제가 생겼을 때
· 더 새로운 macOS가 필요하다고 나오면: ‘macOS 15~25’ 폴더의 빌드를 설치하세요.
· ⌘C를 두 번 눌러도 반응이 없으면: 메뉴 막대 아이콘 → 손쉬운 사용 권한 부여…
· 언어 모델이 없다고 나오면: 메뉴 막대 아이콘 → 언어 모델 확인…

번역은 모두 기기 안에서 이루어집니다. 번역한 내용은 어떤 서버로도 전송되지 않습니다.
EOF

echo "==> Creating $DMG"
# Create, populate, then compress the image to avoid the ENOTEMPTY error
# encountered with hdiutil create -srcfolder on macOS 27.
RW="$BUILD/rw.dmg"
rm -f "$DMG" "$RW"

SIZE=$(( $(du -sm "$STAGE" | cut -f1) * 3 / 2 + 50 ))
quiet diskutil image create blank --size "${SIZE}m" --volumeName "Dejima $VERSION" "$RW"

# Use the default volume mount location for Finder's background alias records.
MOUNT=$(hdiutil attach "$RW" -nobrowse -noverify -noautoopen | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | head -1)
[ -n "$MOUNT" ] || { echo "error: could not tell where $RW mounted" >&2; exit 1; }

# -R keeps the Applications symlinks as symlinks, and the trailing /. takes
# the hidden .background folder along with everything else.
cp -R "$STAGE"/. "$MOUNT"/

echo "==> Laying out the DMG windows"
swift_tool Scripts/dmg-window.swift layout "$MOUNT" "$FOLDER_NEW" "$FOLDER_OLD" "$ICON"
sync

hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null
quiet diskutil image create from "$RW" --format UDZO "$DMG"
rm -f "$RW"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "==> Gatekeeper check"
    spctl -a -t open --context context:primary-signature -v "$DMG"
else
    echo
    echo "NOT notarized. This DMG will open on your own machine and be blocked"
    echo "on everyone else's. See the header of this script for how to sign with"
    echo "a Developer ID certificate and notarize."
fi

echo
echo "==> $DMG"
ls -lh "$DMG" | awk '{print "    " $5}'
