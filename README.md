# Dejima

macOS 菜单栏翻译工具。选中文字，连按两下 ⌘C，在鼠标旁查看译文。

[English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

## 安装

需要 macOS 15 或更新版本。从 [Releases](https://github.com/AIChemist-Nuki/dejima/releases/latest) 下载 DMG，打开对应系统版本的文件夹，将 `Dejima.app` 拖到 Applications。

1. 启动 Dejima，按引导将它加入系统设置的辅助功能列表并开启权限。
2. 在菜单中选择「查看语言模型…」，下载需要的语言。
3. 选中文字，快速连按两下 ⌘C。

应用常驻菜单栏，没有 Dock 图标或主窗口。没有反应时，检查当前运行的 Dejima 是否获得辅助功能权限，以及监听是否已暂停。

## 使用

- 在菜单中设置主语言和备用语言。原文是主语言时译为备用语言，其他情况译为主语言。默认分别为简体中文和日语。短文本可能识别不准。
- 点复制按钮复制译文，点浮窗外或按 Esc 关闭。固定浮窗后，点击外部不会关闭，仍可按 Esc 关闭。
- 「用 Apple Intelligence 润色」默认关闭，需要 macOS 26 或更新版本和可用的 Apple Intelligence 模型。润色失败时保留初译。
- 界面跟随系统语言，支持简体中文、英语、日语和韩语，其他语言使用英语。

## 隐私

翻译和润色在本机完成。下载语言模型需要联网。

检查更新会访问 GitHub，不发送翻译内容、使用记录或应用生成的身份标识。自动检查默认关闭；开启后，若距上次成功检查已满 24 小时，会在启动时检查。失败后可能在下次启动时重试。

## 构建

需要 Xcode 26 或更新版本、macOS 26 或更新版本的 SDK，以及 XcodeGen。

```bash
brew install xcodegen
xcodegen generate
open Dejima.xcodeproj
```

选择 `Dejima` 或 `Dejima26` scheme，配置签名后运行。版本差异和打包步骤见[开发文档](docs/Development.md)（英文）。

MIT 许可证，见 [LICENSE](LICENSE)。
