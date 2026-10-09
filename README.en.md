# Dejima

A macOS menu bar translator. Select text and press ⌘C twice to translate it near the pointer.

[简体中文](README.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

## Install

Requires macOS 15 or later. Download the DMG from [Releases](https://github.com/AIChemist-Nuki/dejima/releases/latest), open the folder for your macOS version, and drag `Dejima.app` to Applications.

1. Launch Dejima. Follow the guide to add it to the Accessibility list in System Settings and enable access.
2. Choose **Check language models…** from the menu and download the languages you need.
3. Select text and press ⌘C twice in quick succession.

Dejima runs in the menu bar, without a Dock icon or main window. If it does not respond, check Accessibility access for the running copy and make sure monitoring is not paused.

## Use

- Set a primary and secondary language in the menu. Text in the primary language translates into the secondary; other text translates into the primary. The defaults are Simplified Chinese and Japanese. Short text may be misidentified.
- Copy the result with the copy button. Click outside the panel or press Esc to close it. Pin it to keep it open when clicking elsewhere; Esc still closes it.
- **Refine with Apple Intelligence** is optional and off by default. It needs macOS 26 or later and an available Apple Intelligence model. If refinement fails, the draft translation is kept.
- The interface follows the system language: English, Simplified Chinese, Japanese, or Korean. Other languages fall back to English.

## Privacy

Translation and refinement run on device. Language model downloads need internet access.

Update checks contact GitHub without sending translated text, usage reports, or an app-generated identifier. Automatic checks are off by default. When enabled, they run at launch if 24 hours have passed since the last successful check; failures may be retried on the next launch.

## Build

Requires Xcode 26 or later with the macOS 26 SDK or later, and XcodeGen.

```bash
brew install xcodegen
xcodegen generate
open Dejima.xcodeproj
```

Choose the `Dejima` or `Dejima26` scheme and configure signing. See [Development](docs/Development.md) for build differences and release packaging.

MIT licensed. See [LICENSE](LICENSE).
