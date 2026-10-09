# Dejima

A macOS menu bar translator. Select text and press ⌘C twice to show a translation near the pointer.

[简体中文](README.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

Dejima uses Apple's Translation framework and runs without a Dock icon or main window. Translation runs on device after the required language models are downloaded.

## Install

Download `Dejima-<version>.dmg` from [Releases](https://github.com/AIChemist-Nuki/dejima/releases/latest). Open the folder for your system and drag `Dejima.app` to Applications.

| macOS version | Folder in the DMG |
|---|---|
| 26 or later | macOS 26 or later |
| 15 to 25 | macOS 15 to 25 |

Launch the app from Applications before granting permissions.

## First run

1. Follow the Accessibility guide. Open System Settings, drag the Dejima icon from the guide into the Accessibility list, and enable it. This permission lets the app detect ⌘C.
2. Choose **Check language models…** in the menu bar menu. In System Settings, download the languages you need.
3. Select some text and press ⌘C twice in quick succession.

The guide closes and monitoring starts when permission is granted. If translation does not start, check that Accessibility access is enabled for the copy of Dejima you are running and that monitoring is not paused.

The macOS 26 build reports an error if a language model is missing. The older build can request a download, but its system prompt may be hard to find. Downloading models before use avoids this.

## Use

Set a primary and secondary language in the menu:

| Source text | Translation |
|---|---|
| In the primary language | Secondary language |
| In another language | Primary language |

The defaults are Simplified Chinese and Japanese. For example, English and Japanese translate into Chinese; Chinese translates into Japanese. Short text can be difficult to identify correctly.

Use the panel's copy button to copy the translation. Click outside the panel or press Esc to close it. Pin the panel to keep it open when clicking elsewhere; Esc still closes it. Monitoring can be paused from the menu.

The interface follows the system language and supports English, Simplified Chinese, Japanese, and Korean. Other system languages use English.

### Optional refinement

**Refine with Apple Intelligence** is available on macOS 26 or later when the on-device model is ready. It is off by default.

When enabled, it reviews the source text and draft translation to revise the wording. Results can vary. If refinement fails or returns an empty result, Dejima keeps the draft.

## Privacy and updates

Translation and refinement run on device. Downloading language models requires an internet connection.

Update checks contact GitHub's releases API. They do not include translated text, usage reports, or an app-generated identifier.

- **Check for updates…** starts a manual check.
- **Check for updates automatically** is off by default. When enabled, Dejima checks at launch if at least 24 hours have passed since the last successful check. Failed checks may be retried on a later launch.

The update code is in [Sources/Updater.swift](Sources/Updater.swift).

## Build

Use Xcode 26 or later with the macOS 26 SDK or later, and XcodeGen. From the repository root:

```bash
brew install xcodegen
xcodegen generate
open Dejima.xcodeproj
```

Choose the `Dejima` or `Dejima26` scheme, configure signing, then run. See [Development](docs/Development.md) for target differences, signing, and release packaging.

## About

The name comes from Dejima, an artificial island in Nagasaki.

MIT licensed. See [LICENSE](LICENSE).
