import AppKit
import Foundation

/// Asks GitHub whether there's a newer release.
///
/// This is the only code in Dejima that touches the network, and it only runs
/// when someone asks for it: the menu item, or the daily check that is off by
/// default. It sends nothing but the HTTP request itself — no text you
/// translated, no identifier, no usage. Translation stays entirely on device
/// either way.
@MainActor
enum Updater {
    private static let repository = "AIChemist-Nuki/dejima"
    private static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"

    /// Don't ask GitHub more than once a day on the automatic path.
    private static let interval: TimeInterval = 60 * 60 * 24

    private static var isChecking = false

    static var checksAutomatically: Bool {
        get { UserDefaults.standard.bool(forKey: automaticKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The menu item. Always reports back, including "nothing to do".
    static func checkNow() {
        check(announceResult: true)
    }

    /// Called at launch. Silent unless there's something worth saying, and only
    /// when the person opted in and we haven't looked today.
    static func checkInBackgroundIfDue() {
        guard checksAutomatically else { return }
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < interval {
            return
        }
        check(announceResult: false)
    }

    private static func check(announceResult: Bool) {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            do {
                let release = try await latestRelease()
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)

                if isNewer(release.version, than: currentVersion) {
                    presentUpdate(release)
                } else if announceResult {
                    presentUpToDate()
                }
            } catch {
                // A failed background check is not worth interrupting anyone.
                if announceResult { presentFailure(error) }
            }
        }
    }

    // MARK: - Network

    private static func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        // A cached answer would hide a release published since the last look.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        switch http.statusCode {
        case 200: return try JSONDecoder().decode(Release.self, from: data)
        case 404: throw UpdateError.noReleases
        default: throw UpdateError.http(http.statusCode)
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        /// Tags are published as "v0.2.0"; only the number is comparable.
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Numeric comparison, so 0.10.0 correctly beats 0.9.0.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        remote.compare(local, options: .numeric) == .orderedDescending
    }

    // MARK: - Reporting

    private static func presentUpdate(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Dejima \(release.version) is available"
        alert.informativeText = "You're running \(currentVersion)."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        if runModal(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private static func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "Dejima is up to date"
        alert.informativeText = "\(currentVersion) is the latest release."
        alert.addButton(withTitle: "OK")
        _ = runModal(alert)
    }

    private static func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        _ = runModal(alert)
    }

    /// An agent app isn't frontmost and has no window to hang a sheet on, so
    /// the alert needs the app brought up first or it appears behind whatever
    /// you were reading.
    private static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}

enum UpdateError: LocalizedError {
    case badResponse
    case noReleases
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "GitHub returned something unexpected."
        case .noReleases:
            return "There are no published releases yet."
        case .http(let code):
            return "GitHub returned HTTP \(code)."
        }
    }
}
