# Kotoba

选中文字，连按两下 ⌘C，翻译浮窗出现在鼠标旁边。全部本地运行，走苹果自己的 Translation 框架。

菜单栏常驻，没有 Dock 图标，没有主窗口。

## 环境要求

- macOS 15 以上（Translation 框架的公开 API 从这一版开始）
- Xcode 16 以上
- 「优化」模式额外需要 macOS 26 + Apple Intelligence（可选，默认关闭）

## 构建

有 XcodeGen 的话：

```bash
brew install xcodegen        # 如果还没装
cd Kotoba
xcodegen generate
open Kotoba.xcodeproj
```

没有也行，手动建一遍：

1. Xcode → New Project → macOS → App，Interface 选 SwiftUI，命名 `Kotoba`
2. 删掉模板生成的 `ContentView.swift` 和 `KotobaApp.swift`
3. 把 `Sources/` 里的 8 个文件拖进去
4. Target → Info 里加一行 `Application is agent (UIElement)` = `YES`
5. Target → Signing & Capabilities 里**删掉 App Sandbox**（沙盒和辅助功能监听冲突）

签名建议填自己的 Team ID。辅助功能授权是绑定在代码签名上的，Ad Hoc 签名每次重新编译都会掉权限，得反复去系统设置里重新添加，很烦。

## 第一次运行

**1. 给辅助功能权限。** 点菜单栏图标 → Grant Accessibility access，然后在系统设置 → 隐私与安全性 → 辅助功能里打开 Kotoba。给完之后需要重启一次 app。

**2. 下载语言模型。** 菜单里的 Check language models 会打开系统设置的翻译语言面板。日语、简体中文、英语各下一个。模型是系统级共享的，「翻译」App 下过的这里直接能用，反之亦然。每个语言包 1–3 GB。

没下模型的话第一次翻译会弹系统下载框——但因为宿主窗口是隐藏的，这个弹框的位置和行为可能有点怪，所以还是建议提前在系统设置里下好。

**3. 试一下。** 随便选一段日文，连按两下 ⌘C。

## 语言方向

菜单里两个选项：

- **Translate into** —— 目标语言，默认简体中文
- **Unless it already is, then** —— 如果检测到的就是目标语言，改译成这个，默认日语

也就是说日文和英文都会变成中文，中文会变成日文。读论文和写回信两种场景都不用切设置。语种检测用 `NLLanguageRecognizer`，短句置信度不够的时候会交给框架自己判断源语言。

## 代码结构

| 文件 | 职责 |
|---|---|
| `DoubleCopyMonitor` | 全局按键监听 + 双击判定 + 剪贴板读取 |
| `LanguageRouter` | 语种检测和翻译方向决策 |
| `TranslationHub` | 把苹果的视图绑定 API 包成普通 `async` 函数 |
| `ResultPanel` / `ResultView` | 不抢焦点的浮窗 |
| `Polisher` | 可选的 Apple Intelligence 二次润色 |
| `Controller` | 把上面这些串起来 |

三个不太直觉的地方，都在代码注释里写了：

**监听而不是注册。** 用 `NSEvent.addGlobalMonitorForEvents` 而不是 `RegisterEventHotKey`。后者会吞掉 ⌘C，正常复制就废了；前者从设计上就无法拦截事件，正好符合需求，代价是要辅助功能权限。

**剪贴板要轮询。** 监听到第二下 ⌘C 的时候，这个按键还没送到前台 App，剪贴板里还是旧内容。所以记下 `changeCount`，每 20ms 查一次，最多等 300ms。有些 App 没选中内容时不会写剪贴板，超时就用现有内容兜底。

**隐藏的 1×1 窗口。** `TranslationSession` 只能从 SwiftUI 的 `.translationTask` 修饰符里拿到，没有「直接给我一个 session」的 API。菜单栏 App 没有天然的视图可以挂，所以塞了一个透明的 1×1 窗口常驻屏幕角落。它必须真的在屏幕上——`orderOut` 或者移到屏幕外，SwiftUI 就认为视图没出现过，task 永远不会跑。另外同一组语言对再次翻译时，configuration 因为相等而不会触发重跑，必须显式调 `invalidate()`。

## 已知的粗糙之处

- **微信、Pages、Keynote 这类 App** 对剪贴板的写入时机不一样，偶尔会读到上一次的内容。Easydict 遇到过同样的问题，它的解法是优先走 Accessibility 取词、失败再回退到剪贴板。如果常用的 App 有问题，可以照这个思路加一层。
- **浮窗关闭**靠点击外部或 Esc。因为是 `.nonactivatingPanel`，键盘事件走的是全局监听，如果没给辅助功能权限，Esc 会失效。
- **长文本**按段落切成 1200 字符一块顺序翻译，段落间语境是断开的。开 Polisher 能补回来一些。
- **Polisher 部分最可能需要你自己调。** FoundationModels 的 API 我不能在这里编译验证，如果签名对不上，看 Xcode 的报错改一下 `session.respond(to:)` 那几行；整块用 `#if canImport` 包着，实在不行删掉也不影响主流程。

## 接下来可以加的

- Accessibility 取词兜底（`AXUIElementCopyAttributeValue` 拿 `kAXSelectedTextAttribute`），绕开剪贴板时序问题
- 术语表：SHMT2、folate、docking 这类词强制固定译法，喂给 Polisher 的 instructions
- 划词后的浮动小图标，不用按键
- 翻译历史 + 一键导出到 Anki，配合你的日语背单词流程

## 参考

- WWDC24「Meet the Translation API」——`translationTask` / `Configuration.invalidate()` 的官方说明
- [SwiftyCrow](https://github.com/PangMo5/SwiftyCrow) —— 同样用 Translation 框架的开源截图翻译，可以对照它怎么处理模型下载
- [Easydict](https://github.com/tisfeng/Easydict) —— 取词策略（Accessibility > AppleScript > 模拟 ⌘C）值得抄
