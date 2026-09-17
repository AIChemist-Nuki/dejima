# Dejima

选中文字，连按两下 ⌘C，译文浮现在光标旁边。翻译全程在本地完成，不经过任何服务器。

[English](README.en.md) · [日本語](README.ja.md)

菜单栏常驻，没有 Dock 图标，没有主窗口。翻译走 macOS 自带的 Translation 框架，语言模型是系统级共享的——「翻译」App 下载过的，这里直接能用，反之亦然。

## 为什么要有这个东西

读日文论文的时候，选中 → 切到翻译 App → 粘贴 → 读 → 切回来，这一趟的摩擦足以让人放弃查一个看不懂的词。Dejima 把它压成一个已经长在肌肉记忆里的动作：⌘C ⌘C。

不联网是硬要求。剪贴板里可能是没发表的稿子、别人的私信、公司的内部文档，这些不该经过任何人的服务器。

## 环境要求

| 项目 | 要求 |
|---|---|
| macOS | 15 以上（Translation 框架从这一版起才有公开 API） |
| Xcode | 16 以上（仅构建需要） |
| 辅助功能权限 | 必须，用于监听 ⌘C |
| Apple Intelligence | 可选，仅「润色」功能需要，且要 macOS 26 以上 |

## 下载哪个版本

有两个构建，功能一样，区别只在怎么向系统要一个翻译会话。

| | **Dejima** | **Dejima 26** |
|---|---|---|
| 系统要求 | macOS 15 以上 | macOS 26 以上 |
| 会话来源 | 藏一个 1×1 窗口，从 SwiftUI 的 `.translationTask` 里拿 | `TranslationSession(installedSource:target:)` 直接创建 |
| 语言包没装时 | 弹系统下载框 | 直接报错，提示去菜单里下载 |
| 语种识别不出时 | 交给框架自己判断源语言 | 采用置信度最低的那个猜测 |

**macOS 26 以下只能用 Dejima。** 26 以上两个都能跑，装 Dejima 26 会少一个常驻屏幕角落的隐藏窗口，代价是上面那两条行为差异——都不影响日常使用，但模型没下全的时候前者更省事。

两个包的 bundle ID 是同一个，所以从一个换到另一个，辅助功能授权、开机启动和设置都会保留。

## 构建

装了 XcodeGen 的话：

```bash
brew install xcodegen   # 如果还没装
xcodegen generate
open Dejima.xcodeproj
```

Xcode 的 scheme 选择器里会有 `Dejima` 和 `Dejima26` 两个，选一个 ⌘R。命令行则是：

```bash
xcodebuild -scheme Dejima   -configuration Release build   # macOS 15+
xcodebuild -scheme Dejima26 -configuration Release build   # macOS 26+
```

`Dejima26` 的产物叫 `Dejima26.app`，只是为了两个 target 不互相覆盖；打包发布时改回 `Dejima.app` 就行，bundle 里的名字本来就是 Dejima。

`project.yml` 里的 `DEVELOPMENT_TEAM` 写的是作者自己的 Team ID，换成你的，或者在 Xcode 的 Signing & Capabilities 里改成 Sign to Run Locally。

**尽量用固定的签名身份。** 辅助功能授权是绑在 bundle ID + 代码签名上的，Ad Hoc 签名每次重新编译都会掉权限，得反复去系统设置里重新添加，很烦。

没有 XcodeGen 也能手动建一遍：

1. Xcode → New Project → macOS → App，Interface 选 SwiftUI，命名 `Dejima`
2. 删掉模板生成的 `ContentView.swift` 和 `DejimaApp.swift`
3. 把 `Sources/` 根目录下的 11 个文件拖进去，再从 `TranslationLegacy/` 和 `Translation26/` 里**二选一**（前者要求 macOS 15，后者 26）
4. Target → Info 里加一行 `Application is agent (UIElement)` = `YES`
5. Target → Signing & Capabilities 里**删掉 App Sandbox**（沙盒和全局按键监听冲突）

## 第一次运行

**1. 给辅助功能权限。** 点菜单栏图标 → `Grant Accessibility access…`，然后在系统设置 → 隐私与安全性 → 辅助功能里打开 Dejima。给完之后需要重启一次 app。

**2. 下载语言模型。** 菜单里的 `Check language models…` 会打开系统设置的翻译语言面板，把要用的语言各下一个（比如日语、简体中文、英语）。每个语言包 1–3 GB。

没下模型的话，第一次翻译会弹系统下载框——但因为宿主窗口是隐藏的，这个弹框的位置和行为可能有点怪，所以建议提前在系统设置里下好。

**3. 试一下。** 随便选一段日文，连按两下 ⌘C。

## 菜单项

| 菜单项 | 作用 |
|---|---|
| `Grant Accessibility access…` | 只在没权限时出现。会弹系统授权框，并打开辅助功能设置面板 |
| `Pause / Resume ⌘C ⌘C` | 临时停掉监听。写代码要大量复制粘贴的时候有用 |
| `Translate into` | 主语言，默认简体中文 |
| `Unless it already is, then` | 如果检测到的已经是主语言，就改译成这个，默认日语 |
| `Refine with Apple Intelligence` | 可选的二次润色，默认关闭。只有设备支持时才显示这一项 |
| `Open at login` | 登录时自动启动 |
| `Check for updates automatically` | 每天最多查一次 GitHub 有没有新版本，**默认关闭** |
| `Check for updates…` | 手动查一次 |
| `Check language models…` | 打开系统设置的翻译语言面板，在那里下载和管理模型 |
| `Quit Dejima` (⌘Q) | 退出 |

浮窗上有个复制按钮；点窗口外面或者按 Esc 关掉它。

## 翻译方向

只有两个设置，但覆盖了两种日常场景：

| 识别到的语言 | 译成 |
|---|---|
| 日语 / 英语 / 其他任何语言 | 主语言（默认简体中文） |
| 主语言本身 | 备用语言（默认日语） |
| 识别不出来 | 主语言，源语言交给框架自己判断 |

也就是说：日文和英文都会变成中文，而中文会变成日文。读论文和写回信都不用切设置。

语种识别用 `NLLanguageRecognizer`。短句的判断结果不可靠，所以加了道门槛：置信度超过 0.4，或者文本长于 12 个字符，才采信识别结果；否则当作「识别不出来」处理。`zh-Hans` 和 `zh` 在方向判断里算同一种语言。

可选的语言在 `LanguageRouter.choices` 里，目前是简繁中文、日、英、韩、德、法、西、俄。Apple 支持的更多，按自己需要加减。

## 联网情况

**你翻译的任何内容都不会离开这台机器。** 翻译走的是 macOS 本地的 Translation 框架，润色走的是端上的 Apple Intelligence，两者都不联网。

整个 app 里只有一处会发出网络请求：检查更新，去 GitHub 的 releases API 问一句最新版本号。

- 手动的 `Check for updates…` 只在你点的时候发一次
- `Check for updates automatically` **默认关闭**；打开后每天最多查一次，在启动时进行
- 请求里除了 HTTP 本身没有任何内容——不带标识、不带用量、更不带你翻译过的文字

代码在 `Sources/Updater.swift`，一共不到 180 行，可以自己看一遍。不想要就把这两项留在关闭状态，或者直接删掉这个文件。

## 工作原理

四个不太直觉的地方，代码注释里也都写了：

**监听，而不是注册热键。** 用 `NSEvent.addGlobalMonitorForEvents` 而不是 `RegisterEventHotKey`。后者会吞掉 ⌘C，正常复制就废了；前者从设计上就无法拦截事件，正好符合需求，代价是要辅助功能权限。另外全局监听在自己的 app 处于前台时是收不到事件的，所以还并了一个 local monitor。判定要求修饰键**恰好**是 ⌘，⌘⇧C、⌘⌥C 这些都不算。

**剪贴板要轮询。** 监听到第二下 ⌘C 的时候，这个按键还没送到前台 App，剪贴板里还是旧内容。所以先记下 `changeCount`，每 20 ms 查一次，最多等 300 ms。两次 ⌘C 的间隔窗口默认 0.45 秒（`UserDefaults` 的 `doublePressWindow` 可以改）。

**藏了一个 1×1 的窗口**（仅 macOS 15 版；26 版不需要，见上面的版本对比）**。** `TranslationSession` 只能从 SwiftUI 的 `.translationTask` 修饰符里拿到，没有「直接给我一个 session」的 API。菜单栏 App 没有天然的视图可以挂，所以塞了一个全透明的 1×1 窗口常驻屏幕角落。它必须真的在屏幕上——`orderOut` 或者移到屏幕外，SwiftUI 就认为视图从未出现，task 永远不会跑。另外同一组语言对再次翻译时，configuration 因为相等而不会触发重跑，必须显式调 `invalidate()`。

**浮窗不抢焦点。** `NSPanel` 带 `.nonactivatingPanel`，所以它弹出来的时候不会把焦点从你正在读的东西上夺走，光标留在原处。位置会做边界收敛，保证整个窗口留在指针所在的那块屏幕里。

长文本按段落切成 1200 字符一块顺序翻译，再用空行拼回来。

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
| `TextCleaner` | 修复从 PDF 复制来的硬换行 |
| `LoginItem` | 开机启动 |
| `Updater` | 检查更新，全 app 唯一的联网点 |
| `ResultPanel` | `ResultModel` + 不抢焦点的浮窗 |
| `ResultView` | 浮窗里的内容：译文在上，原文在下 |
| `MenuBarView` | 菜单内容 |

关于润色：Apple 的 NMT 模型快且离线，但会把技术和学术文本的语气压平。开了这一项之后，端上的大模型会拿到原文和初译稿，修术语和措辞，并被要求原样保留专有名词、基因和蛋白名、化学名、单位和文献引注。仍然离线，仍然免费，大约慢一秒。任何一步出错都静默回退到初译稿。

## 已知的粗糙之处

- **剪贴板时序。** 微信、Pages、Keynote 这类 App 写剪贴板的时机不一样，偶尔会读到上一次的内容。Easydict 遇到过同样的问题，它的解法是优先走 Accessibility 取词、失败再回退剪贴板。
- **没选中东西的时候连按 ⌘C**，300 ms 超时之后会拿现有的剪贴板内容去翻译，也就是翻译上一次复制的东西。
- **长文本语境是断开的**，段落之间互相看不见。开润色能补回来一些。
- **中日混排的短句**容易判错——汉字在两种语言里长得一样，`NLLanguageRecognizer` 也会犯错。这种情况下可以手动改一下菜单里的语言对再复制一次。
- **没有历史记录。** 译文只活在浮窗里，关掉就没了。要留就先点复制。

## 之后可能加的

- Accessibility 取词兜底（`AXUIElementCopyAttributeValue` 拿 `kAXSelectedTextAttribute`），绕开剪贴板时序问题
- 术语表：让特定词强制固定译法，喂给润色的 instructions
- 划词后的浮动小图标，不按键也能触发
- 翻译历史 + 一键导出到 Anki

## 关于这个名字

出島是江户时代长崎港里的一座人工岛。锁国的两百年间，它是日本唯一对外通商的窗口——一个很小的口岸，但外面的东西都从这里进来。

## 参考

- WWDC24「Meet the Translation API」——`translationTask` / `Configuration.invalidate()` 的官方说明
- [SwiftyCrow](https://github.com/PangMo5/SwiftyCrow) —— 同样基于 Translation 框架的开源截图翻译，可以对照它怎么处理模型下载
- [Easydict](https://github.com/tisfeng/Easydict) —— 取词策略（Accessibility > AppleScript > 模拟 ⌘C）值得抄
