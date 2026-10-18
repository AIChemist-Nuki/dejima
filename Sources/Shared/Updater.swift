import AppKit
import Foundation

/// Checks GitHub releases manually or through an opt-in daily check.
/// The request contains no translation text or usage data.
@MainActor
enum Updater {
    private static let repository = "AIChemist-Nuki/dejima"
    private static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"

    private static let interval: TimeInterval = 60 * 60 * 24

    private static var isChecking = false

    static var checksAutomatically: Bool {
        get { UserDefaults.standard.bool(forKey: automaticKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Manual checks also report failures and up-to-date results.
    static func checkNow() {
        check(announceResult: true)
    }

    /// At launch, check if enabled and due; only announce available updates.
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
        // Bypass cached release metadata.
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

        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Compare numeric components so 0.10.0 sorts after 0.9.0.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        remote.compare(local, options: .numeric) == .orderedDescending
    }

    // MARK: - Reporting

    private static func presentUpdate(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Dejima \(release.version) is available")
        alert.informativeText = String(localized: "You're running \(currentVersion).")
        alert.addButton(withTitle: String(localized: "Open Release Page"))
        alert.addButton(withTitle: String(localized: "Later"))
        if runModal(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private static func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Dejima is up to date")
        alert.informativeText = String(localized: "\(currentVersion) is the latest release.")
        alert.addButton(withTitle: String(localized: "OK"))
        _ = runModal(alert)
    }

    private static func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't check for updates")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        _ = runModal(alert)
    }

    /// Activate the agent app before presenting a modal alert.
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
            return String(localized: "GitHub returned something unexpected.")
        case .noReleases:
            return String(localized: "There are no published releases yet.")
        case .http(let code):
            return String(localized: "GitHub returned HTTP \(code).")
        }
    }
}
