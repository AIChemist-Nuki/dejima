# Dejima Privacy Policy — App Store Edition

Effective date: October 27, 2026.

This policy describes the data handling implemented in Dejima 0.4.1 for the Mac App Store. Dejima is developed by HUANG ZHAOFENG. The separately distributed, direct-download edition may have different update functionality.

## Translation and optional refinement

Dejima uses Apple's Translation framework to translate text on your Mac. If you enable the optional Apple Intelligence refinement feature on a supported Mac, Dejima uses Apple's on-device Foundation Models framework to revise the translation.

Dejima does not send your source text or translations to a developer-operated server. It does not provide an account system or store a translation history. The current source text and translation are held in app memory so they can be displayed and copied.

Translation may require language models to be downloaded through macOS. Model availability, downloads, and other Apple platform services are managed by Apple under Apple's own privacy terms and your system settings.

## Clipboard and Accessibility access

Dejima observes keyboard events to recognize the Command-C double-copy shortcut. When you invoke that shortcut, it reads text from the system clipboard. If copying does not update the clipboard, Dejima may use Accessibility APIs to read the current selection in the foreground app.

This text is used for language detection, translation, optional refinement, and display. Choosing a copy action writes the result to the system clipboard. The clipboard is managed by macOS; Dejima does not clear clipboard contents when you close its translation panel or quit the app.

You can pause monitoring from the Dejima menu and manage its Accessibility access in System Settings.

## Information stored on your Mac

Dejima stores preferences locally, including your translation language choices, whether optional refinement is enabled, and whether language setup has been completed.

To manage feedback reminders, it also stores the bundle identifiers of apps for which a reminder has been shown or muted. Consecutive selection-reading failures are counted in memory. Dejima does not automatically upload these preferences, app identifiers, or failure counts to the developer.

## Optional feedback and support

You can choose to contact the developer through the feedback options offered by Dejima. These open an external service, such as GitHub, your email app, or Xiaohongshu where available.

A prepared report includes your macOS version and Dejima version. A report about a selection-reading problem also includes the source app's name, version, and bundle identifier. Dejima does not include the text you were translating in these prepared reports.

When you choose GitHub feedback, the app passes the report title and diagnostic details in the URL used to open the issue form. For email feedback, it supplies a draft subject and body to your email app. For a channel that cannot prefill a message, it copies the diagnostic report to the clipboard so you can paste it yourself. Dejima does not automatically create a GitHub issue, send an email, or post a message.

If you submit feedback, the developer can receive the information you choose to send and the account or contact information made available by that service. A GitHub issue may be publicly visible. The external service's privacy policy and account settings govern its handling and storage of your information. The app does not implement automated deletion of correspondence held by those services.

## Advertising, tracking, and analytics

The App Store edition contains no advertising SDK, third-party analytics SDK, or developer-operated telemetry service. It does not implement advertising tracking. The App Store edition does not include the direct-download edition's Sparkle update checks or downloads.

Apple may separately process information when you use macOS, the App Store, TestFlight, or Apple's other services. That processing is governed by Apple's policies and your choices for those services.

## Contact

For general questions about Dejima's privacy practices, visit the [Dejima support page on GitHub](https://github.com/AIChemist-Nuki/dejima/issues). GitHub issues are public, so avoid including private information in an issue. The app's feedback menu also offers an email contact option.

## Changes

Updates to this policy will be published on this page. The effective date and version scope above identify the implementation described by this policy.
