import AppKit
import SwiftUI

/// The translation is the hero; the original sits underneath as reference.
/// Everything else stays quiet — this window appears on top of whatever you
/// were reading, so it should read like a caption, not an app.
struct ResultView: View {
    @ObservedObject var model: ResultModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    output
                    Divider().opacity(0.5)
                    Text(model.sourceText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.routeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            Spacer()

            if case .done(let text) = model.state {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy translation")
            }
        }
    }

    @ViewBuilder
    private var output: some View {
        switch model.state {
        case .translating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…").foregroundStyle(.secondary)
            }
            .font(.body)

        case .done(let text):
            Text(text)
                .font(.system(size: 15))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Translation failed", systemImage: "exclamationmark.triangle")
                    .font(.body.weight(.medium))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
