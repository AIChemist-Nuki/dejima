import AppKit
import SwiftUI

/// Version, updates, and feedback in one window.
struct AboutView: View {
    static let windowID = "about"

    @ObservedObject private var updater = Updater.shared
    /// Read on appear and after restoring; mutes change from result panels.
    @State private var hasMutedApps = SelectionFeedback.hasMutedApps
    @State private var copiedReport = false

    private var channels: [FeedbackChannel] {
        FeedbackChannel.all.filter { $0.url(.general) != nil }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text(verbatim: "Dejima")
                    .font(.title2.weight(.semibold))
                Text("Version \(FeedbackReport.dejimaVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Form {
                Section("Updates") {
                    LabeledContent {
                        Button(updater.updateAvailable
                               ? LocalizedStringKey("Install update")
                               : LocalizedStringKey("Check for updates")) {
                            updater.checkNow()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    } label: {
                        Text(updater.updateAvailable
                             ? LocalizedStringKey("Update available")
                             : LocalizedStringKey("Software update"))
                    }
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.checksAutomatically },
                        set: { updater.setChecksAutomatically($0) }
                    ))
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(channels) { channel in
                            Button {
                                if channel.send(.general) { copiedReport = true }
                            } label: {
                                Label(channel.title, systemImage: channel.systemImage)
                            }
                        }
                    }
                    LabeledContent {
                        Button("Restore") {
                            SelectionFeedback.restoreReminders()
                            hasMutedApps = SelectionFeedback.hasMutedApps
                        }
                        .disabled(!hasMutedApps)
                    } label: {
                        Text("Feedback reminders")
                        Text(hasMutedApps
                             ? LocalizedStringKey("Turned off for some apps.")
                             : LocalizedStringKey("On for all apps."))
                    }
                } header: {
                    Text("Send Feedback")
                } footer: {
                    Text(copiedReport
                         ? LocalizedStringKey("Diagnostic info copied. Paste it into your message.")
                         : LocalizedStringKey("Feedback includes version info, never the text you translate."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .padding(.top, 24)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { hasMutedApps = SelectionFeedback.hasMutedApps }
    }
}

#Preview {
    AboutView()
}
