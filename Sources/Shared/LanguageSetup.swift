import SwiftUI
import Translation

@MainActor
@Observable
final class LanguageSetupModel {
    enum State: Equatable {
        case checking, ready, needsDownload, downloading, unsupported, failed
    }

    struct Request {
        let generation: Int
        let source: String
        let target: String
    }

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedLanguageSetup")
    }

    var primary = LanguageRouter.primary {
        didSet {
            LanguageRouter.primary = primary
            refresh()
        }
    }
    var secondary = LanguageRouter.secondary {
        didSet {
            LanguageRouter.secondary = secondary
            refresh()
        }
    }
    private(set) var state: State = .checking
    private(set) var configuration: TranslationSession.Configuration?
    private(set) var request: Request?

    private var generation = 0
    private var checkTask: Task<Void, Never>?
    private var missingPair: (source: String, target: String)?

    @discardableResult
    func synchronizePreferences() -> Bool {
        let savedPrimary = LanguageRouter.primary
        let savedSecondary = LanguageRouter.secondary
        guard primary != savedPrimary || secondary != savedSecondary else { return false }
        if primary != savedPrimary { primary = savedPrimary }
        if secondary != savedSecondary { secondary = savedSecondary }
        return true
    }

    func refresh() {
        cancel()
        state = .checking
        let current = generation
        checkTask = Task { [weak self] in
            guard let self else { return }
            await self.check(generation: current)
        }
    }

    func cancel() {
        generation += 1
        checkTask?.cancel()
        checkTask = nil
        configuration = nil
        request = nil
    }

    func download() {
        guard state == .needsDownload, let pair = missingPair else { return }
        checkTask?.cancel()
        generation += 1
        request = Request(generation: generation, source: pair.source, target: pair.target)
        state = .downloading
        let source = Locale.Language(identifier: pair.source)
        let target = Locale.Language(identifier: pair.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = .init(source: source, target: target)
        }
    }

    /// Runs off the main actor: TranslationSession isn't Sendable, so it must
    /// stay in the task that received it.
    nonisolated func prepare(using session: TranslationSession, request: Request?) async {
        guard let request, await isCurrent(request) else { return }
        do {
            try await session.prepareTranslation()
            guard !Task.isCancelled else { return }
            await didPrepare(request)
        } catch {
            await didFailPreparing(request)
        }
    }

    private func isCurrent(_ request: Request) -> Bool {
        request.generation == generation
    }

    private func didPrepare(_ request: Request) {
        guard isCurrent(request) else { return }
        // Preparation can return while a system download is still in progress.
        checkTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, request.generation == self.generation {
                await self.check(generation: request.generation, waitingFor: request)
                guard self.state == .downloading else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func didFailPreparing(_ request: Request) {
        guard isCurrent(request) else { return }
        state = .failed
    }

    func finish() -> Bool {
        guard !synchronizePreferences(), state == .ready else { return false }
        UserDefaults.standard.set(true, forKey: "hasCompletedLanguageSetup")
        cancel()
        return true
    }

    private func check(generation current: Int, waitingFor request: Request? = nil) async {
        guard !Task.isCancelled, current == generation else { return }
        guard primary != secondary else {
            state = .unsupported
            missingPair = nil
            return
        }
        let pairs = [(source: secondary, target: primary), (source: primary, target: secondary)]
        let availability = LanguageAvailability()
        var missing: [(source: String, target: String)] = []
        for pair in pairs {
            let status = await availability.status(from: Locale.Language(identifier: pair.source),
                                                   to: Locale.Language(identifier: pair.target))
            guard !Task.isCancelled, current == generation else { return }
            switch status {
            case .installed:
                break
            case .supported:
                missing.append(pair)
            case .unsupported:
                missingPair = nil
                state = .unsupported
                return
            @unknown default:
                missingPair = nil
                state = .failed
                return
            }
        }
        missingPair = missing.first
        if missing.isEmpty {
            state = .ready
        } else if let request, missing.contains(where: { $0.source == request.source && $0.target == request.target }) {
            state = .downloading
        } else {
            state = .needsDownload
        }
    }
}

struct LanguageSetupView: View {
    @Bindable var model: LanguageSetupModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose your languages")
                .font(.headline)
            Text("Dejima switches between these two languages automatically. Other source languages may need downloads later.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Translate into", selection: $model.primary) {
                languages
            }
            Picker("Unless it already is, then", selection: $model.secondary) {
                languages
            }

            status
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)

            HStack {
                Button("Set up later", action: onClose)
                Spacer()
                switch model.state {
                case .ready:
                    Button("Get started") {
                        if model.finish() { onClose() }
                    }
                    .keyboardShortcut(.defaultAction)
                case .needsDownload:
                    Button("Download languages") { model.download() }
                        .keyboardShortcut(.defaultAction)
                case .failed:
                    Button("Try again") { model.refresh() }
                case .downloading:
                    Button("Check again") { model.refresh() }
                case .checking, .unsupported:
                    EmptyView()
                }
            }
        }
        .padding(20)
        .frame(width: PermissionGuide.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            model.refresh()
            // Follow changes made from the menu bar while this window is open.
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                model.synchronizePreferences()
            }
        }
        .onDisappear { model.cancel() }
        // @Sendable keeps the action off the main actor; see prepare(using:request:).
        .translationTask(model.configuration) { @Sendable [request = model.request] session in
            await model.prepare(using: session, request: request)
        }
    }

    private var languages: some View {
        ForEach(LanguageRouter.choices, id: \.self) { code in
            Text(LanguageRouter.displayName(code)).tag(code)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .checking:
            Label {
                Text("Checking languages…")
            } icon: {
                ProgressView().controlSize(.small)
            }
        case .ready:
            Label("These languages are ready on this Mac.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsDownload:
            Text("Download these languages to translate on this Mac.")
        case .downloading:
            Label {
                Text("Waiting for languages to be ready…")
            } icon: {
                ProgressView().controlSize(.small)
            }
        case .unsupported:
            Text("This language pair isn't supported. Choose two different languages.")
        case .failed:
            Text("The languages aren't ready. Try again or finish setting up later.")
        }
    }
}
