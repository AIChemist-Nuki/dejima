# Dejima

选中文字，连按两下 ⌘C，译文浮现在光标旁边。翻译全程在本地完成，不经过任何服务器。

[English](README.en.md) · [日本語](README.ja.md)

菜单栏常驻，没有 Dock 图标，也没有主窗口。翻译走 macOS 自带的 Translation 框架，语言模型是系统级共享的——「翻译」App 下载过的，这里直接能用，反之亦然。

读外文资料的时候，选中 → 切到翻译 App → 粘贴 → 读 → 切回来，这一趟的摩擦足以让人放弃查一个看不懂的词。Dejima 把它压成一个已经长在肌肉记忆里的动作：⌘C ⌘C。剪贴板里可能是没发表的稿子、别人的私信、公司的内部文档，所以不联网是硬要求。

## 关于这个名字

出島是江户时代长崎港里的一座人工岛。锁国的两百年间，它是日本唯一对外通商的窗口——一个很小的口岸，但外面的东西都从这里进来。

## 下载

到 [Releases](https://github.com/AIChemist-Nuki/dejima/releases/latest) 下载 `Dejima-<版本号>.dmg`，打开后按自己的系统版本选一个文件夹，把里面的 `Dejima.app` 拖到旁边的 Applications 上。

| 文件夹 | 适用 |
|---|---|
| `macOS 15-25` | macOS 15 到 25 |
| `macOS 26+` | macOS 26 或更新 |

装错了不要紧：系统版本不够时 macOS 会直接拒绝启动，并告诉你该装哪个。

两份构建功能完全一样，区别只在怎么向系统要一个翻译会话。macOS 26 的接口可以直接创建会话，省掉一个常驻屏幕角落的隐藏窗口；代价是语言包没装时直接报错，而不是弹系统的下载框。两者 bundle ID 相同，互相替换时辅助功能授权、开机启动和设置都会保留。

还需要辅助功能权限，用于监听 ⌘C。可选的「润色」另外需要 Apple Intelligence 和 macOS 26 以上。

## 第一次运行

**1. 给辅助功能权限。** 没有权限时启动会弹出引导窗口：点按钮打开辅助功能面板，把窗口里那个 Dejima 图标**直接拖进列表**，再打开开关。

拖的是正在运行的 bundle 本身，所以不会加错。这个授权绑定到具体 bundle，列表里加进去的如果是替身、或者 Downloads 里的另一份拷贝，看起来加上了但实际不生效。如果 app 还不在 Applications 里，引导窗口会提醒你先挪过去——挪动之后授权会失效。

开关打开后引导窗口自己关闭，监听立刻生效，通常不用重启。手动再打开这个窗口：菜单栏图标 → `Grant Accessibility access…`。

**2. 下载语言模型。** 菜单里的 `Check language models…` 会打开系统设置的翻译语言面板，把要用的语言各下一个（比如日语、简体中文、英语）。每个语言包 1–3 GB。

没下模型的话，第一次翻译会弹系统下载框——但因为宿主窗口是隐藏的，这个弹框的位置和行为可能有点怪，建议提前下好。

**3. 试一下。** 随便选一段外文，连按两下 ⌘C。

## 翻译方向

菜单里只有两个设置，覆盖两种日常场景：

| 识别到的语言 | 译成 |
|---|---|
| 日语 / 英语 / 其他任何语言 | 主语言（默认简体中文） |
| 主语言本身 | 备用语言（默认日语） |
| 识别不出来 | 主语言，源语言交给框架自己判断 |

也就是说：日文和英文都会变成中文，而中文会变成日文。读论文和写回信都不用切设置。

语种识别用 `NLLanguageRecognizer`。短句的判断不可靠，所以加了道门槛：置信度超过 0.4，或者文本长于 12 个字符，才采信识别结果。`zh-Hans` 和 `zh` 在方向判断里算同一种语言。可选的语言在 `LanguageRouter.choices` 里，目前是简繁中文、日、英、韩、德、法、西、俄，按需要加减。

浮窗上有个复制按钮；点窗口外面或者按 Esc 关掉它。

## 界面语言

跟随系统语言，有简体中文、日语和英语三种，没有单独的设置，其他语言会落到英语。译文和原文本身不受此影响，那取决于上面的翻译方向。

## 联网情况

**你翻译的任何内容都不会离开这台机器。** 翻译走的是 macOS 本地的 Translation 框架，润色走的是端上的 Apple Intelligence，两者都不联网。

整个 app 里只有一处会发出网络请求：检查更新，去 GitHub 的 releases API 问一句最新版本号。

- 手动的 `Check for updates…` 只在你点的时候发一次
- `Check for updates automatically` **默认关闭**；打开后每天最多查一次，在启动时进行
- 请求里除了 HTTP 本身没有任何内容——不带标识、不带用量、更不带你翻译过的文字

代码在 `Sources/Updater.swift`，不到 180 行。不想要就把这两项留在关闭状态，或者直接删掉这个文件。

## 构建

需要 Xcode 16 以上和 XcodeGen：

```bash
brew install xcodegen   # 如果还没装
xcodegen generate
open Dejima.xcodeproj
```

scheme 选择器里会有 `Dejima` 和 `Dejima26` 两个，选一个 ⌘R。命令行则是：

```bash
xcodebuild -scheme Dejima   -configuration Release build   # macOS 15+
xcodebuild -scheme Dejima26 -configuration Release build   # macOS 26+
```

`Dejima26` 的产物叫 `Dejima26.app`，只是为了两个 target 不互相覆盖；打包时会改回 `Dejima.app`。

`project.yml` 里的 `DEVELOPMENT_TEAM` 写的是作者自己的 Team ID，换成你的，或者在 Xcode 的 Signing & Capabilities 里改成 Sign to Run Locally。**尽量用固定的签名身份**：辅助功能授权绑在 bundle ID + 代码签名上，Ad Hoc 签名每次重新编译都会掉权限。

没有 XcodeGen 也能手动建一遍：

1. Xcode → New Project → macOS → App，Interface 选 SwiftUI，命名 `Dejima`
2. 删掉模板生成的 `ContentView.swift` 和 `DejimaApp.swift`
3. 把 `Sources/` 根目录下的文件、`Localizable.xcstrings`、`InfoPlist.xcstrings` 和 `Assets.xcassets` 拖进去，再从 `TranslationLegacy/` 和 `Translation26/` 里**二选一**（前者要求 macOS 15，后者 26）
4. Target → Info 里加一行 `Application is agent (UIElement)` = `YES`
5. Target → Signing & Capabilities 里**删掉 App Sandbox**（沙盒和全局按键监听冲突）

## 打包发布

```bash
CODE_SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" \
NOTARY_PROFILE=dejima \
./Scripts/release.sh
```

产出 `dist/Dejima-<版本号>.dmg`，里面是两个文件夹，各放一份 `Dejima.app` 和一个 Applications 替身：

```
Dejima 0.2.0
├── macOS 15-25/
│   ├── Dejima.app
│   └── Applications →
├── macOS 26+/
│   ├── Dejima.app
│   └── Applications →
└── Read Me.txt
```

两份都叫 `Dejima.app`，靠文件夹区分，装完之后 `/Applications` 里不会留下一个名字带版本号的 app。

**签名是硬要求。** 项目默认的 Apple Development 证书只能在你自己机器上跑，别人下载后会被 Gatekeeper 拒绝。公开发布需要 Developer ID Application 证书 + 公证，公证凭据预先存一次：

```bash
xcrun notarytool store-credentials dejima \
  --apple-id you@example.com --team-id TEAMID --password <app 专用密码>
```

不带这两个环境变量也能跑，得到的是一个只有你自己能打开的 DMG，脚本结束时会提示这一点。

**每次发版**记得改 `project.yml` 里的 `MARKETING_VERSION`（两个 target 共用同一份模板），tag 用 `v0.1.0` 这种格式——更新检查比的是 bundle 里的版本号。

## 代码结构

| 文件 | 职责 |
|---|---|
| `DejimaApp` | `@main` 入口，`MenuBarExtra` |
| `Controller` | `AppDelegate` + 把下面这些串起来：权限、监听开关、翻译任务编排 |
| `DoubleCopyMonitor` | 全局按键监听 + 双击判定 + 剪贴板读取 |
| `LanguageRouter` | 语种识别和翻译方向决策 |
| `TranslationLegacy/TranslationHub` | macOS 15 版：把苹果的视图绑定 API 包成普通 `async` 函数，含隐藏宿主窗口 |
| `Translation26/TranslationHub` | macOS 26 版：直接创建 session，同样的对外 API，没有窗口 |
| `Polisher` | 可选的 Apple Intelligence 二次润色 |
| `PermissionGuide` | 辅助功能授权的引导窗口，可拖拽的 app 图标 |
| `TextCleaner` | 修复从 PDF 复制来的硬换行 |
| `LoginItem` | 开机启动 |
| `Updater` | 检查更新，全 app 唯一的联网点 |
| `ResultPanel` | `ResultModel` + 不抢焦点的浮窗 |
| `ResultView` | 浮窗里的内容：译文在上，原文在下 |
| `MenuBarView` | 菜单内容 |
| `DejimaMark` | 出字标记，菜单栏图标就是它 |

`Scripts/` 下是 app 图标（`app-icon.swift`）、DMG 的窗口背景和布局（`dmg-window.swift`）、打包脚本（`release.sh`）。

## 之后可能加的

- 术语表：让特定词强制固定译法，喂给润色的 instructions
- 把「Refine with Apple Intelligence」做稳。Apple 的 NMT 模型快且离线，但会把技术和学术文本的语气压平；开了这一项之后，端上的大模型会拿到原文和初译稿，修术语和措辞，并被要求原样保留专有名词、基因和蛋白名、化学名、单位和文献引注。仍然离线，大约慢一秒，出错静默回退到初译稿——但效果还不够稳定，所以默认关闭

## 许可证

MIT，见 [LICENSE](LICENSE)。

## 参考

- WWDC24「Meet the Translation API」——`translationTask` / `Configuration.invalidate()` 的官方说明
- [SwiftyCrow](https://github.com/PangMo5/SwiftyCrow) —— 同样基于 Translation 框架的开源截图翻译，可以对照它怎么处理模型下载
