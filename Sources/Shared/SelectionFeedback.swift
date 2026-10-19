import AppKit
import SwiftUI

/// Where users can reach the author. Leave a value empty to hide that channel.
enum FeedbackContact {
    static let githubIssues = "https://github.com/AIChemist-Nuki/dejima/issues/new"
    static let email = "zhaofeng.huang@cddlab.io"
    static let xiaohongshu = "https://xhslink.cn/o/JF0zOkubLo"
}

/// Diagnostic details attached to feedback. Never includes the selected text.
struct FeedbackReport: Hashable {
    /// An app whose selections Dejima couldn't read.
    struct SourceApp: Hashable {
        let name: String
        let bundleID: String
        let version: String

        init(_ app: NSRunningApplication) {
            name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            bundleID = app.bundleIdentifier ?? "unknown"
            version = app.bundleURL
                .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
                ?? "?"
        }
    }

    /// `nil` for general feedback sent from the menu.
    let app: SourceApp?

    static let general = FeedbackReport(app: nil)

    static var dejimaVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var title: String {
        app.map { "Can't read selected text in \($0.name)" } ?? "Dejima feedback"
    }

    var body: String {
        var lines: [String] = []
        if let app {
            lines += ["App: \(app.name) \(app.version)", "Bundle ID: \(app.bundleID)"]
        }
        lines += ["macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                  "Dejima: \(Self.dejimaVersion)"]
        return lines.joined(separator: "\n")
    }
}

/// A place to send feedback. Add new channels to `all`.
struct FeedbackChannel: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    /// Channels that can't prefill a message get the report on the clipboard.
    let prefillsReport: Bool
    let url: (FeedbackReport) -> URL?

    static let all: [FeedbackChannel] = [github, email, xiaohongshu]

    /// Opens the channel. Returns `true` if the report was copied to the
    /// clipboard because the channel can't prefill it.
    @MainActor
    @discardableResult
    func send(_ report: FeedbackReport) -> Bool {
        guard let url = url(report) else { return false }
        if !prefillsReport {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(report.body, forType: .string)
        }
        NSWorkspace.shared.open(url)
        return !prefillsReport
    }

    static let github = FeedbackChannel(id: "github", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                                        prefillsReport: true) { report in
        guard !FeedbackContact.githubIssues.isEmpty,
              var components = URLComponents(string: FeedbackContact.githubIssues) else { return nil }
        components.queryItems = [URLQueryItem(name: "title", value: report.title),
                                 URLQueryItem(name: "body", value: report.body)]
        return components.url
    }

    static let email = FeedbackChannel(id: "email", title: "Email", systemImage: "envelope",
                                       prefillsReport: true) { report in
        guard !FeedbackContact.email.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FeedbackContact.email
        components.queryItems = [URLQueryItem(name: "subject", value: report.title),
                                 URLQueryItem(name: "body", value: report.body)]
        return components.url
    }

    static let xiaohongshu = FeedbackChannel(id: "xiaohongshu", title: "Xiaohongshu", systemImage: "book",
                                             prefillsReport: false) { _ in
        // Offered only to users translating into Chinese (Simplified or Traditional).
        guard LanguageRouter.primary.hasPrefix("zh"), !FeedbackContact.xiaohongshu.isEmpty else { return nil }
        return URL(string: FeedbackContact.xiaohongshu)
    }
}

/// Counts consecutive unreadable selections per app and decides when to ask
/// for feedback.
@MainActor
final class SelectionFeedback {
    struct Prompt: Identifiable, Hashable {
        let id = UUID()
        let app: FeedbackReport.SourceApp
        /// "Don't remind me" is offered only after an app has been prompted once.
        let offersMute: Bool

        var report: FeedbackReport { FeedbackReport(app: app) }
    }

    static let failureThreshold = 5

    private static let promptedKey = "feedbackPromptedApps"
    private static let mutedKey = "feedbackMutedApps"

    /// Kept in memory: a relaunch starts a fresh streak.
    private var failures: [String: Int] = [:]

    func recordSuccess(in app: NSRunningApplication?) {
        guard let id = app?.bundleIdentifier else { return }
        failures[id] = nil
    }

    /// Returns a prompt once the app reaches the failure threshold.
    func recordFailure(in app: NSRunningApplication?) -> Prompt? {
        guard let app, let id = app.bundleIdentifier,
              !Self.ids(forKey: Self.mutedKey).contains(id) else { return nil }

        let count = failures[id, default: 0] + 1
        guard count >= Self.failureThreshold else {
            failures[id] = count
            return nil
        }
        failures[id] = nil

        let offersMute = Self.ids(forKey: Self.promptedKey).contains(id)
        Self.insert(id, forKey: Self.promptedKey)
        return Prompt(app: FeedbackReport.SourceApp(app), offersMute: offersMute)
    }

    static func mute(_ bundleID: String) {
        insert(bundleID, forKey: mutedKey)
    }

    /// Re-enables prompts for every muted app. Apps keep their prompted
    /// status, so "Don't remind me" stays available.
    static var hasMutedApps: Bool {
        !ids(forKey: mutedKey).isEmpty
    }

    static func restoreReminders() {
        UserDefaults.standard.removeObject(forKey: mutedKey)
    }

    private static func ids(forKey key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func insert(_ id: String, forKey key: String) {
        var stored = ids(forKey: key)
        guard stored.insert(id).inserted else { return }
        UserDefaults.standard.set(stored.sorted(), forKey: key)
    }
}
