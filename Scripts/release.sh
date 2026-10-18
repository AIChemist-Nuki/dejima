#!/bin/bash
#
# Builds both targets and packages them into one DMG.
#
#   ./Scripts/release.sh 0.3.0    tag HEAD as v0.3.0, then build it
#   ./Scripts/release.sh          build the version HEAD is already tagged with
#   ./Scripts/release.sh --local 0.3.0    verify packaging without creating a tag
#
# Uses the git tag for the version and the commit count for the build number.
# Public release builds require a clean working tree. Tags are local; push separately:
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

LOCAL_BUILD=0
if [ "${1:-}" = "--local" ]; then
    [ $# -eq 2 ] || { echo "usage: $0 --local VERSION" >&2; exit 1; }
    LOCAL_BUILD=1
    shift
fi
[ $# -le 1 ] || { echo "usage: $0 [VERSION | --local VERSION]" >&2; exit 1; }

if [ $# -gt 0 ]; then
    VERSION="${1#v}"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "error: '$1' is not a version like 0.3.0" >&2; exit 1
    }
fi

if [ "$LOCAL_BUILD" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
    echo "error: uncommitted changes. Commit or stash them first:" >&2
    git status --short >&2
    exit 1
fi

# Fail before creating a tag if the native project or full Xcode is unavailable.
[ -f Dejima.xcodeproj/project.pbxproj ] || {
    echo "error: Dejima.xcodeproj is missing. Restore it from Git." >&2; exit 1
}
xcodebuild -version >/dev/null 2>&1 || {
    echo "error: select a full Xcode installation using xcode-select or DEVELOPER_DIR" >&2; exit 1
}

if [ "$LOCAL_BUILD" -eq 1 ]; then
    BUILD="$PWD/build/local"
    DMG_SUFFIX="-local"
elif [ $# -gt 0 ]; then
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

if [ "$LOCAL_BUILD" -eq 0 ]; then
    BUILD="$PWD/build/release"
    DMG_SUFFIX=""
fi
STAGE="$BUILD/dmg"
DIST="$PWD/dist"
DMG="$DIST/Dejima-$VERSION$DMG_SUFFIX.dmg"

# The layout uses these names to position icons. Finder displays localized
# names from the .localized directories created below.
FOLDER_NEW="macOS 26+.localized"
FOLDER_OLD="macOS 15-25.localized"

ICON="$PWD/Assets.xcassets/AppIcon.appiconset/icon_512.png"

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

# $1 scheme, $2 built product name, $3 folder inside the DMG
build_one() {
    local scheme="$1" product="$2" folder="$3"
    echo "==> Building $scheme"

    local args=(
        -project Dejima.xcodeproj
        -scheme "$scheme"
        -configuration Release
        -destination 'generic/platform=macOS'
        -derivedDataPath "$BUILD/dd-$scheme"
        ONLY_ACTIVE_ARCH=NO
        "MARKETING_VERSION=$VERSION"
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
    )
    if [ "$LOCAL_BUILD" -eq 1 ]; then
        args+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
            OTHER_CODE_SIGN_FLAGS=--timestamp=none CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
    elif [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
        # Developer ID needs no provisioning profile for a non-sandboxed app
        # distributed outside the App Store, so manual signing is enough.
        args+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
        # Notarization rejects what `xcodebuild build` does by default but
        # `archive` doesn't: a signature without a secure timestamp, and the
        # get-task-allow entitlement it injects so a debugger can attach.
        args+=(OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
    else
        # Allow Xcode to update signing assets only for automatic signing.
        args+=(-allowProvisioningUpdates)
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
    if [ "$LOCAL_BUILD" -eq 1 ]; then
        echo "    signature: ad-hoc (local verification)"
    else
        echo "    signed by: $(codesign -dvv "$STAGE/$folder/Dejima.app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    fi
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

首次使用
1. 从“应用程序”打开 Dejima，按引导授予辅助功能权限。
2. 选择两种常用的翻译语言。若提示缺少语言，点“下载语言”，
   在系统窗口中确认下载；准备完成后点“开始使用”。
   已有可用模型时，无需另行下载。
3. 在支持复制文字的应用中选中文字，快速连按两次 ⌘C，查看译文。

遇到问题
· 打开时提示需要更新的 macOS：改装「macOS 15 到 25」文件夹里的版本。
· 连按两下 ⌘C 没反应：菜单栏图标 → 授予辅助功能权限…
· 提示缺少翻译语言：菜单栏图标 → 翻译语言设置，查看或下载所需语言。

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

First launch
1. Open Dejima from Applications and follow the guide to grant Accessibility access.
2. Choose your two usual translation languages. If languages are missing, click
   “Download languages” and confirm the download in the system dialog. Once ready,
   click “Get started”. No extra download is needed if usable models are available.
3. Select text in an app that supports copying, then quickly press ⌘C twice
   to see the translation.

If something goes wrong
· Says it needs a newer macOS: install the one in the “macOS 15 to 25” folder.
· Pressing ⌘C twice does nothing: menu bar icon → Grant Accessibility access…
· Missing translation languages: menu bar icon → Translation language settings.
  Check or download the languages you need there.

Translation happens entirely on device. Nothing you translate reaches a server.


========================================
日本語
========================================

2つのビルド、片方だけ入れてください

    macOS 26 以降
    macOS 15〜25

macOS のバージョンがわからない場合: 画面左上の ${APPLE_LOGO} → このMacについて。

対応するフォルダを開き、Dejima.app を隣の Applications にドラッグします。

初めて使うとき
1. 「アプリケーション」から Dejima を開き、案内に従ってアクセシビリティ権限を許可します。
2. よく使う翻訳言語を2つ選びます。言語が不足している場合は「言語をダウンロード」を押し、
   システムのダイアログでダウンロードを確認します。準備ができたら「使い始める」を押します。
   利用可能なモデルがある場合は、追加のダウンロードは不要です。
3. テキストをコピーできるアプリで文章を選び、⌘C をすばやく2回押すと訳文が表示されます。

困ったときは
・新しい macOS が必要と表示される: 「macOS 15〜25」フォルダの方を入れてください。
・⌘C を2回押しても反応しない: メニューバーアイコン → アクセシビリティ権限を与える…
・翻訳言語が不足していると表示される: メニューバーアイコン → 翻訳言語の設定。
  必要な言語を確認、ダウンロードできます。

翻訳はすべて端末内で完結します。サーバーには何も送りません。


========================================
한국어
========================================

두 가지 빌드가 있습니다. 하나만 설치하세요

    macOS 26 이상
    macOS 15~25

macOS 버전을 모르겠다면: 화면 왼쪽 위의 ${APPLE_LOGO} → 이 Mac에 관하여.

맞는 폴더를 열고 Dejima.app을 옆에 있는 Applications로 드래그하세요.

처음 사용할 때
1. 응용 프로그램에서 Dejima를 열고 안내에 따라 손쉬운 사용 권한을 허용하세요.
2. 자주 사용하는 번역 언어 두 개를 선택하세요. 언어가 없다는 안내가 나오면
   ‘언어 다운로드’를 누르고 시스템 대화상자에서 다운로드를 확인하세요.
   준비가 끝나면 ‘시작하기’를 누르세요. 사용 가능한 모델이 있으면 추가 다운로드는 필요 없습니다.
3. 텍스트 복사를 지원하는 앱에서 글을 선택하고 ⌘C를 빠르게 두 번 눌러 번역을 확인하세요.

문제가 생겼을 때
· 더 새로운 macOS가 필요하다고 나오면: ‘macOS 15~25’ 폴더의 빌드를 설치하세요.
· ⌘C를 두 번 눌러도 반응이 없으면: 메뉴 막대 아이콘 → 손쉬운 사용 권한 부여…
· 번역 언어가 없다고 나오면: 메뉴 막대 아이콘 → 번역 언어 설정에서
  필요한 언어를 확인하거나 다운로드하세요.

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

if [ "$LOCAL_BUILD" -eq 1 ]; then
    codesign --sign - --timestamp=none "$DMG"
elif [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    # Gatekeeper checks the DMG itself when it is opened, not only the apps in it.
    echo "==> Signing the DMG"
    codesign --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG"
fi

if [ "$LOCAL_BUILD" -eq 1 ]; then
    echo
    echo "Local verification only: ad-hoc signed, not notarized, and no tag created."
    echo "Do not use this DMG for public distribution."
elif [ -n "${NOTARY_PROFILE:-}" ]; then
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
