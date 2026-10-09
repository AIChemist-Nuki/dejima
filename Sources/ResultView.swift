import AppKit
import SwiftUI

struct ResultView: View {
    @ObservedObject var model: ResultModel
    /// Report content height to resize the result panel.
    var onContentHeightChange: (CGFloat) -> Void
    var onClose: () -> Void

    /// Dimensions shared with ResultPanel.
    enum Layout {
        /// Keep text wrapping stable as translated chunks arrive.
        static let width: CGFloat = 380
        static let padding: CGFloat = 16
        static let headerHeight: CGFloat = 20
        static let headerSpacing: CGFloat = 12
        static let minHeight: CGFloat = 96
        static let maxHeight: CGFloat = 520

        /// Height occupied by padding and the header.
        static var chrome: CGFloat { padding * 2 + headerHeight + headerSpacing }

        static func height(forContent content: CGFloat) -> CGFloat {
            min(max(content + chrome, minHeight), maxHeight)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
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
                // Measure the content height inside the scroll view, before viewport clipping.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    onContentHeightChange(height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.routeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()

            if let text = model.copyableText {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy translation")
            }

            Button {
                model.isPinned.toggle()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
            }
            .foregroundStyle(model.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(model.isPinned
                  ? LocalizedStringKey("Unpin")
                  : LocalizedStringKey("Keep the panel open when you click elsewhere"))

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium))
        .frame(height: Layout.headerHeight)
    }

    @ViewBuilder
    private var output: some View {
        switch model.state {
        case .translating:
            activity("Translating…")

        case .streaming(let text):
            VStack(alignment: .leading, spacing: 10) {
                translation(text)
                activity("Translating the rest…")
            }

        case .refining(let text):
            VStack(alignment: .leading, spacing: 10) {
                translation(text)
                activity("Refining…")
            }

        case .done(let text):
            translation(text)

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

    private func translation(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activity(_ label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.body)
    }
}

#Preview {
    let model = ResultModel()
    model.sourceText = "本研究では、葉酸代謝経路におけるミトコンドリア酵素の役割を検討した。"
    model.routeLabel = "日语 → 中文"
    model.state = .done("本研究探讨了叶酸代谢通路中线粒体酶的作用。")
    return ResultView(model: model, onContentHeightChange: { _ in }, onClose: {})
        .frame(width: ResultView.Layout.width, height: 220)
}
