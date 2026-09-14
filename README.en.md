# Dejima

Select text, press ⌘C twice, and the translation appears next to your pointer. Everything runs locally; nothing leaves the machine.

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

## Building

With XcodeGen:

```bash
brew install xcodegen   # if you don't have it
xcodegen generate
open Dejima.xcodeproj
```

Then ⌘R.

`DEVELOPMENT_TEAM` in `project.yml` is the author's own Team ID. Replace it with yours, or switch to "Sign to Run Locally" under Signing & Capabilities in Xcode.

**Use a stable signing identity.** The Accessibility grant is tied to the bundle ID plus the code signature, so an ad-hoc signature loses the permission on every rebuild and you have to re-add the app in System Settings again and again.

Without XcodeGen, set it up by hand:

1. Xcode → New Project → macOS → App, Interface: SwiftUI, name it `Dejima`
2. Delete the generated `ContentView.swift` and `DejimaApp.swift`
3. Drag in the 9 files from `Sources/`
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

## How it works

Four things that aren't obvious, all also noted in the code:

**Observe, don't register a hotkey.** This uses `NSEvent.addGlobalMonitorForEvents` rather than `RegisterEventHotKey`. The latter swallows ⌘C and breaks normal copying; a monitor cannot consume events at all, which is exactly what's wanted here. The price is the Accessibility permission. A global monitor also stays silent while Dejima itself is frontmost, so a local monitor runs alongside it. The match requires the modifiers to be *exactly* ⌘ — not ⌘⇧C, ⌘⌥C, or ⌃⌘C.

**The pasteboard has to be polled.** When the second ⌘C is observed, the keystroke hasn't reached the frontmost app yet, so the pasteboard still holds the old value. Dejima records `changeCount`, then checks every 20 ms for up to 300 ms. The window for the second press defaults to 0.45 s (`doublePressWindow` in `UserDefaults`).

**There's a hidden 1×1 window.** A `TranslationSession` is only handed to you inside SwiftUI's `.translationTask` modifier — there is no "give me a session" call. A menu bar app has no natural view to hang that on, so a fully transparent 1×1 window sits permanently in the corner of the screen. It has to be genuinely on screen: `orderOut` or moving it off-screen makes SwiftUI treat the view as never having appeared, and the task never runs. Also, translating the same language pair twice produces an equal configuration that SwiftUI would skip, so `invalidate()` has to be called explicitly.

**The panel doesn't steal focus.** The `NSPanel` carries `.nonactivatingPanel`, so showing it doesn't pull focus away from whatever you were reading and your caret stays put. Its position is clamped to keep the whole window on the screen the pointer is on.

Long text is split into 1200-character chunks along paragraph boundaries, translated in order, and joined back with blank lines.

## Code layout

| File | Responsibility |
|---|---|
| `DejimaApp` | `@main` entry point, `MenuBarExtra` |
| `Controller` | `AppDelegate` plus the wiring: permission, monitor toggling, translation orchestration |
| `DoubleCopyMonitor` | Global key monitoring, double-press detection, pasteboard reading |
| `LanguageRouter` | Language detection and direction decisions |
| `TranslationHub` | Wraps Apple's view-bound API as a plain `async` function; owns the hidden host window and the chunking |
| `Polisher` | Optional Apple Intelligence refinement |
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
