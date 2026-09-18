# Dejima

Select text, press ⌘C twice, and the translation appears next to your pointer. Translation happens entirely on device — nothing you translate goes through a server.

[简体中文](README.md) · [日本語](README.ja.md)

Dejima lives in the menu bar — no Dock icon, no main window. Translation goes through macOS's built-in Translation framework, and the language models are shared system-wide: anything you downloaded for the Translate app works here, and the other way around.

## Why this exists

Reading a paper in a language you're still learning, the loop is: select → switch to a translator → paste → read → switch back. That friction is enough to make you skip the word you didn't understand. Dejima collapses it into a gesture already in your muscle memory: ⌘C ⌘C.

Staying offline is a hard requirement. Your clipboard holds unpublished drafts, other people's messages, internal documents — none of that should pass through anyone's server.

## Requirements

| | |
|---|---|
| macOS | 15 or later (the Translation framework's public API starts there) |
| Xcode | 16 or later (to build) |
| Accessibility permission | Required, to watch for ⌘C |
| Apple Intelligence | Optional, only for the refine pass, and needs macOS 26 or later |

## Which build to download

There are two, identical in features. The only difference is how they ask the system for a translation session.

| | **Dejima** | **Dejima 26** |
|---|---|---|
| Requires | macOS 15+ | macOS 26+ |
| Gets its session from | a hidden 1×1 window carrying SwiftUI's `.translationTask` | `TranslationSession(installedSource:target:)`, directly |
| With a language pack missing | the system's download prompt | an error pointing at the menu item that installs them |
| When the language can't be identified | leaves the source for the framework to guess | commits to the best guess available |

**Below macOS 26, Dejima is the only option.** At 26 and above either works; Dejima 26 spares you a hidden window parked in the corner of the screen, at the cost of the two behaviour differences above. Neither matters day to day, but the first build is easier to live with while you're still downloading models.

Both share a bundle identifier, so moving from one to the other keeps your Accessibility grant, login item and settings.

## Building

With XcodeGen:

```bash
brew install xcodegen   # if you don't have it
xcodegen generate
open Dejima.xcodeproj
```

Xcode's scheme picker will offer `Dejima` and `Dejima26`; choose one and ⌘R. From the command line:

```bash
xcodebuild -scheme Dejima   -configuration Release build   # macOS 15+
xcodebuild -scheme Dejima26 -configuration Release build   # macOS 26+
```

`Dejima26` builds to `Dejima26.app` purely so the two targets don't overwrite each other; packaging renames it to `Dejima.app`, which is what the bundle calls itself anyway.

## Packaging a release

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=dejima \
./Scripts/release.sh
```

That leaves `dist/Dejima-<version>.dmg`, holding one folder per minimum macOS version, each with a `Dejima.app` and an Applications alias:

```
Dejima 0.1.0
├── macOS 15-25/
│   ├── Dejima.app
│   └── Applications →
├── macOS 26+/
│   ├── Dejima.app
│   └── Applications →
└── Read Me.txt
```

Both are named `Dejima.app`; the folder is what distinguishes them, so nothing lands in `/Applications` with a version number stuck to its name. Installing the wrong one is harmless — macOS refuses to launch a build that needs a newer system and says which one it needs.

**Signing is not optional.** The Apple Development certificate the project defaults to only runs on your own machine; Gatekeeper blocks it for everyone who downloads it. Publishing needs a Developer ID Application certificate plus notarization. Store the notary credentials once:

```bash
xcrun notarytool store-credentials dejima \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

The script runs without those two variables too; you just get a DMG only you can open, and it says so when it finishes.

**Every release**, bump `MARKETING_VERSION` in `project.yml` (both targets share the one template) and tag as `v0.1.0`. The update check compares against the version inside the bundle, so forgetting means people who installed the new build are still told there's a new build.

`DEVELOPMENT_TEAM` in `project.yml` is the author's own Team ID. Replace it with yours, or switch to "Sign to Run Locally" under Signing & Capabilities in Xcode.

**Use a stable signing identity.** The Accessibility grant is tied to the bundle ID plus the code signature, so an ad-hoc signature loses the permission on every rebuild and you have to re-add the app in System Settings again and again.

Without XcodeGen, set it up by hand:

1. Xcode → New Project → macOS → App, Interface: SwiftUI, name it `Dejima`
2. Delete the generated `ContentView.swift` and `DejimaApp.swift`
3. Drag in the 11 files at the root of `Sources/`, plus **one** of `TranslationLegacy/` or `Translation26/` (macOS 15 and 26 respectively)
4. Target → Info, add `Application is agent (UIElement)` = `YES`
5. Target → Signing & Capabilities, **remove App Sandbox** (the sandbox and global key monitoring don't get along)

## First run

**1. Grant Accessibility access.** Click the menu bar icon → `Grant Accessibility access…`, then enable Dejima under System Settings → Privacy & Security → Accessibility. Restart the app afterwards.

**2. Download the language models.** `Check language models…` in the menu opens the Translation Languages pane in System Settings. Grab one per language you need. Each pack is 1–3 GB.

Without a model, the first translation triggers the system's download prompt — but since the host window is invisible, that prompt can end up in an odd place and behave strangely. Better to download ahead of time.

**3. Try it.** Select a sentence in a foreign language and press ⌘C twice.

## The menu

| Item | What it does |
|---|---|
| `Grant Accessibility access…` | Only shown when the permission is missing. Triggers the system prompt and opens the Accessibility pane |
| `Pause / Resume ⌘C ⌘C` | Temporarily stops the monitor. Handy while writing code, where you copy constantly |
| `Translate into` | Your primary language, Simplified Chinese by default |
| `Unless it already is, then` | Where to go when the text is already in the primary language. Japanese by default |
| `Refine with Apple Intelligence` | Optional second pass, off by default. Only appears if the device supports it |
| `Open at login` | Start Dejima when you log in |
| `Check for updates automatically` | Asks GitHub for the latest version at most once a day. **Off by default** |
| `Check for updates…` | Check once, now |
| `Check language models…` | Opens the Translation Languages pane to download and manage models |
| `Quit Dejima` (⌘Q) | Quit |

The panel has a copy button. Click outside it or press Esc to dismiss.

## Which way it translates

Two settings, and between them they cover both everyday cases:

| Detected language | Translated into |
|---|---|
| Japanese / English / anything else | Primary language (default: Simplified Chinese) |
| The primary language itself | Secondary language (default: Japanese) |
| Couldn't tell | Primary language, with the source left for the framework to guess |

So Japanese and English both become Chinese, while Chinese becomes Japanese. Reading papers and drafting a reply both work without touching a setting.

Detection uses `NLLanguageRecognizer`. Its guesses on short strings aren't trustworthy, so there's a gate: the result counts only if confidence is above 0.4 or the text is longer than 12 characters. Otherwise it's treated as "couldn't tell". For routing purposes, `zh-Hans` and `zh` are the same language.

The offered languages live in `LanguageRouter.choices` — currently Simplified and Traditional Chinese, Japanese, English, Korean, German, French, Spanish, and Russian. Apple supports more; trim or extend to taste.

## What touches the network

**Nothing you translate ever leaves the machine.** Translation goes through the local Translation framework, refinement through on-device Apple Intelligence. Neither one connects to anything.

Exactly one thing in the app makes a network request: the update check, which asks GitHub's releases API for the latest version number.

- `Check for updates…` fires once, when you pick it
- `Check for updates automatically` is **off by default**; turned on, it looks at most once a day, at launch
- The request carries nothing beyond the HTTP call itself — no identifier, no usage, and certainly none of your text

The code is in `Sources/Updater.swift`, under 180 lines, and reads in one sitting. If you'd rather not have it, leave both settings off or delete the file.

## How it works

Four things that aren't obvious, all also noted in the code:

**Observe, don't register a hotkey.** This uses `NSEvent.addGlobalMonitorForEvents` rather than `RegisterEventHotKey`. The latter swallows ⌘C and breaks normal copying; a monitor cannot consume events at all, which is exactly what's wanted here. The price is the Accessibility permission. A global monitor also stays silent while Dejima itself is frontmost, so a local monitor runs alongside it. The match requires the modifiers to be *exactly* ⌘ — not ⌘⇧C, ⌘⌥C, or ⌃⌘C.

**The pasteboard has to be polled.** When the second ⌘C is observed, the keystroke hasn't reached the frontmost app yet, so the pasteboard still holds the old value. Dejima records `changeCount`, then checks every 20 ms for up to 300 ms. The window for the second press defaults to 0.45 s (`doublePressWindow` in `UserDefaults`).

**There's a hidden 1×1 window** (macOS 15 build only; the 26 build doesn't need one — see the comparison above)**.** A `TranslationSession` is only handed to you inside SwiftUI's `.translationTask` modifier — there is no "give me a session" call. A menu bar app has no natural view to hang that on, so a fully transparent 1×1 window sits permanently in the corner of the screen. It has to be genuinely on screen: `orderOut` or moving it off-screen makes SwiftUI treat the view as never having appeared, and the task never runs. Also, translating the same language pair twice produces an equal configuration that SwiftUI would skip, so `invalidate()` has to be called explicitly.

**The panel doesn't steal focus.** The `NSPanel` carries `.nonactivatingPanel`, so showing it doesn't pull focus away from whatever you were reading and your caret stays put. Its position is clamped to keep the whole window on the screen the pointer is on.

Long text is split into 1200-character chunks along paragraph boundaries, translated in order, and joined back with blank lines.

## Code layout

| File | Responsibility |
|---|---|
| `DejimaApp` | `@main` entry point, `MenuBarExtra` |
| `Controller` | `AppDelegate` plus the wiring: permission, monitor toggling, translation orchestration |
| `DoubleCopyMonitor` | Global key monitoring, double-press detection, pasteboard reading |
| `LanguageRouter` | Language detection and direction decisions |
| `TranslationLegacy/TranslationHub` | macOS 15 build: wraps Apple's view-bound API as a plain `async` function; owns the hidden host window |
| `Translation26/TranslationHub` | macOS 26 build: creates a session directly. Same API, no window |
| `Polisher` | Optional Apple Intelligence refinement |
| `TextCleaner` | Repairs hard line breaks from PDF copies |
| `LoginItem` | Launch at login |
| `Updater` | The update check — the only networking in the app |
| `ResultPanel` | `ResultModel` plus the non-activating floating panel |
| `ResultView` | Panel contents: translation on top, original underneath |
| `MenuBarView` | Menu contents |

About the refine pass: Apple's NMT model is fast and offline, but it flattens technical and academic prose. With this on, the on-device LLM receives the original and the draft, fixes terminology and phrasing, and is told to leave proper nouns, gene and protein names, chemical names, units, and citations exactly as written. Still offline, still free, roughly a second slower. Anything that goes wrong silently falls back to the draft.

## Known rough edges

- **Pasteboard timing.** Apps like WeChat, Pages, and Keynote write to the pasteboard on their own schedule, so occasionally you get the previous contents. Easydict hit the same problem; its answer is to read the selection through Accessibility first and fall back to the pasteboard.
- **Pressing ⌘C twice with nothing selected** will, after the 300 ms timeout, translate whatever is already on the pasteboard — i.e. the last thing you copied.
- **Long text loses context across chunks**; paragraphs can't see each other. The refine pass recovers some of it.
- **Short mixed Chinese/Japanese strings get misdetected.** The same characters exist in both languages and `NLLanguageRecognizer` does get it wrong. Adjust the language pair in the menu and copy again.
- **No history.** A translation only lives in the panel; dismiss it and it's gone. Hit copy if you want to keep it.

## Possible additions

- Accessibility as a fallback for reading the selection (`AXUIElementCopyAttributeValue` with `kAXSelectedTextAttribute`), sidestepping the pasteboard timing problem
- A glossary that pins chosen terms to fixed translations, fed to the refine instructions
- A small floating icon after selecting text, so no keystroke is needed
- Translation history plus one-click export to Anki

## About the name

Dejima was an artificial island in the harbour of Nagasaki. Through the two centuries Japan spent closed to the outside world, it was the country's only channel for foreign trade — a very small port, but everything from outside came through it.

## References

- WWDC24 "Meet the Translation API" — the official word on `translationTask` and `Configuration.invalidate()`
- [SwiftyCrow](https://github.com/PangMo5/SwiftyCrow) — an open-source screenshot translator on the same framework; worth comparing how it handles model downloads
- [Easydict](https://github.com/tisfeng/Easydict) — its text-capture strategy (Accessibility > AppleScript > synthetic ⌘C) is worth copying
