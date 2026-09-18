#!/bin/bash
#
# Builds both targets and packages them into one DMG.
#
#   ./Scripts/release.sh
#
# The DMG holds two folders, one per minimum macOS version, each with a
# Dejima.app and an Applications alias to drag it onto. Both apps are named
# Dejima.app — the folder is what tells them apart, so nothing ends up in
# /Applications with a version number stuck to its name.
#
# SIGNING. Without arguments this signs with whatever the project is set to,
# which is an Apple Development certificate: fine on your own machine, refused
# by Gatekeeper everywhere else. A build other people can open needs a
# Developer ID certificate and notarization:
#
#   CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=dejima \
#   ./Scripts/release.sh
#
# Create the notary profile once, beforehand:
#
#   xcrun notarytool store-credentials dejima \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*: *"\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

BUILD="$PWD/build/release"
STAGE="$BUILD/dmg"
DIST="$PWD/dist"
DMG="$DIST/Dejima-$VERSION.dmg"

command -v xcodegen >/dev/null || { echo "error: xcodegen not installed (brew install xcodegen)" >&2; exit 1; }

# Run something noisy, and only show its output if it actually fails.
quiet() {
    local log="$BUILD/step.log"
    "$@" >"$log" 2>&1 || { echo "error: $1 failed" >&2; cat "$log" >&2; exit 1; }
}

echo "==> Dejima $VERSION"
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
    echo "    minimum:   $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$STAGE/$folder/Dejima.app/Contents/Info.plist")"
}

build_one Dejima   Dejima   "macOS 15-25"
build_one Dejima26 Dejima26 "macOS 26+"

# Most people never open this; the folder names carry the decision. It's here
# for the ones who do.
cat > "$STAGE/Read Me.txt" <<EOF
Dejima $VERSION
https://github.com/AIChemist-Nuki/dejima


两个版本，装一个就行 / Two builds, install one / 2つのビルド、片方だけ

    macOS 26+        系统是 macOS 26 或更新
    macOS 15-25      系统是 macOS 15 到 25

不知道自己是哪个版本：左上角苹果菜单 → 关于本机。
Not sure which macOS you have: Apple menu → About This Mac.
macOS のバージョン: アップルメニュー → このMacについて。

打开对应的文件夹，把 Dejima.app 拖到旁边的 Applications 上。
Open the matching folder, drag Dejima.app onto the Applications alias beside it.
対応するフォルダを開き、Dejima.app を隣の Applications にドラッグします。


装错了不要紧
Getting it wrong is harmless
間違えても問題ありません

系统版本不够时 macOS 会直接拒绝启动，并告诉你需要哪个版本，不会有任何损坏。
换另一个文件夹里的重装即可。
macOS refuses to launch a build that needs a newer system and says so. Nothing
breaks. Install the one from the other folder instead.
要件を満たさないビルドは macOS が起動を拒否し、必要なバージョンを表示します。
もう一方のフォルダから入れ直してください。


两个版本有什么区别
What's different
違いは何か

功能完全一样。区别只在内部如何向系统申请翻译会话：macOS 26 的接口可以直接
创建会话，省掉一个常驻屏幕角落的隐藏窗口。代价是语言包没下载时会直接报错，
而不是弹出系统的下载框。
Identical in features. They differ only in how a translation session is obtained
internally: the macOS 26 API creates one directly, which avoids a hidden helper
window parked on screen. In exchange, a missing language pack raises an error
instead of opening the system's download prompt.
機能は同じです。違いは内部で翻訳セッションを取得する方法だけです。macOS 26
の API は直接生成できるため、画面に常駐する隠しウィンドウが不要になります。
その代わり、言語パック未導入時はシステムのダウンロードダイアログではなく
エラーになります。


第一次运行
First run
初回起動

需要辅助功能权限，用于监听 ⌘C。菜单栏图标 → Grant Accessibility access…
Needs Accessibility permission, to watch for ⌘C. Menu bar icon → Grant
Accessibility access…
⌘C の監視のためアクセシビリティ権限が必要です。メニューバーアイコン →
Grant Accessibility access…

还需要在系统设置里下载语言模型。菜单里的 Check language models… 会带你过去。
You also need language models. Check language models… in the menu opens the
right pane in System Settings.
言語モデルのダウンロードも必要です。メニューの Check language models… から
システム設定の該当パネルが開きます。


翻译全程在本地完成，不经过任何服务器。
Translation happens entirely on device. Nothing you translate reaches a server.
翻訳はすべて端末内で完結します。サーバーには何も送りません。
EOF

echo "==> Creating $DMG"
# Built in three steps rather than one `hdiutil create -srcfolder`, because
# that is broken on macOS 27 — it fails with ENOTEMPTY even for a blank image.
# `diskutil image create` works but cannot produce a compressed image from a
# folder, so: make a writable one large enough, fill it, convert it.
RW="$BUILD/rw.dmg"
MOUNT="$BUILD/mnt"
rm -f "$DMG" "$RW"
rm -rf "$MOUNT"
mkdir -p "$MOUNT"

SIZE=$(( $(du -sm "$STAGE" | cut -f1) * 3 / 2 + 50 ))
quiet diskutil image create blank --size "${SIZE}m" --volumeName "Dejima $VERSION" "$RW"
quiet hdiutil attach "$RW" -nobrowse -mountpoint "$MOUNT"
# -R keeps the Applications symlinks as symlinks.
cp -R "$STAGE"/* "$MOUNT"/
hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null
quiet diskutil image create from "$RW" --format UDZO "$DMG"
rm -f "$RW"
rmdir "$MOUNT" 2>/dev/null || true

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
