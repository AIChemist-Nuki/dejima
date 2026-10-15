<img src="Assets.xcassets/AppIcon.appiconset/icon_128.png" alt="Dejima" width="64" align="right">

# Dejima

**Local translation on your Mac. Just press ⌘C twice.**

Select text and press ⌘C twice to see the translation beside your pointer. Dejima works without an app's right-click Translate menu or switching apps. Once the required models are ready, you can translate offline.

[简体中文](README.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Dejima's English-to-Chinese translation panel](docs/images/translation.jpg)

*Dejima v0.2.8, English interface.*

**[Download Dejima](https://github.com/AIChemist-Nuki/dejima/releases/latest)** · macOS 15 or later

## Get started in three steps

### 1. Install and allow access

Open the downloaded DMG and choose the folder for your system: **macOS 15 to 25** or **macOS 26 or later**. Drag `Dejima.app` to Applications before launching it.

Follow the app's guide to open the Accessibility list in System Settings. Drag Dejima into the list and enable access. The guide closes automatically when access is granted.

<img src="docs/images/accessibility.jpg" alt="Dejima's Accessibility guide in English" width="420">

### 2. Choose your translation languages

Click the Dejima icon in the menu bar at the top of your screen and set two options:

- **Translate into:** the language you usually want to read.
- **Unless it already is, then:** the language to use when the source is already in the first language.

For example, choose **Simplified Chinese** and **English**: English translates into Chinese, and Chinese into English. The source language is detected automatically; you do not need to set it.

The defaults are Simplified Chinese and Japanese. Change them as needed.

### 3. Select, ⌘C, ⌘C

Select a passage you can copy in a webpage or document. Hold ⌘ and quickly press C twice. The translation appears beside your pointer; click outside the panel or press Esc to return to reading.

**If a language model is missing**

If a translation appears, skip the downloads. If macOS prompts you to download languages, follow that prompt. If Dejima says a language pair has not been downloaded:

1. Choose **Check language models…** in the Dejima menu to open **Language & Region** in System Settings. This button only opens settings; it does not download anything.
2. Click **Translation Languages…**, then **Download** beside both the source and target languages named in the message. For English to Simplified Chinese, you need both English and Simplified Chinese.
3. Wait for the downloads to finish, return to the original text, and press **⌘C twice** again.

<img src="docs/images/languages.jpg" alt="Translation language downloads in macOS System Settings, in English" width="420">

*Language downloads, shown in English. Click Download beside each required language.*

## Make it your own

- **Language detection.** The source language may be misidentified for short text.
- **Copy or pin.** Copy the translation with the copy button, or pin the panel to keep it open when clicking elsewhere. Esc still closes it.
- **Extra refinement.** **Refine with Apple Intelligence** adds a separate pass after translation. It is off by default and appears only on macOS 26 or later with an available model. If refinement fails, the draft translation is kept.
- **Interface language.** Follows your system language: English, Simplified Chinese, Japanese, or Korean. Other languages fall back to English.

See the [translation app comparison](docs/Comparison.md).

<details>
<summary>Nothing happens after pressing ⌘C twice?</summary>

Check that the text can be copied, that the running copy of Dejima has Accessibility access, and that monitoring is not paused in the menu. If the panel reports a missing language model, follow the download steps above.

</details>

## Privacy

Translation and refinement run on device. Language model downloads need internet access.

Update checks contact GitHub without sending translated text, usage reports, or an app-generated identifier. Automatic checks are off by default. When enabled, they run at launch if 24 hours have passed since the last successful check; failures may be retried on the next launch.

## About the name

Dejima is named after the [artificial island in Nagasaki](https://nagasakidejima.jp/history/) that served as a gateway for trade, knowledge, and cultural exchange between Japan and Western Europe during the Edo period.

## Development

See [Development](docs/Development.md) for build requirements, differences between the two versions, and release packaging.

MIT licensed. See [LICENSE](LICENSE).
