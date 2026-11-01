import AppKit
import SwiftUI

/// Lets SwiftUI buttons respond to the first click in a panel that never activates the app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Places a window just below `anchor` (or above it when there's no room), kept on screen.
func position(_ window: NSWindow, near anchor: CGRect?) {
    let anchor = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
    let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
    let size = window.frame.size
    var origin = CGPoint(x: anchor.minX, y: anchor.minY - size.height - 6)
    if let visible = screen?.visibleFrame {
        if origin.y < visible.minY { origin.y = min(anchor.maxY + 6, visible.maxY - size.height) }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
    }
    window.setFrameOrigin(origin)
}

// MARK: - Floating ✨ button

final class PillPanel: NSPanel {
    var onClick: (() -> Void)?
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 96, height: 30),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = FirstMouseHostingView(rootView: PillView(title: "Refine") { [weak self] in self?.onClick?() })
    }

    override var canBecomeKey: Bool { false }

    func show(near anchor: CGRect?, title: String) {
        (contentView as? FirstMouseHostingView<PillView>)?.rootView =
            PillView(title: title) { [weak self] in self?.onClick?() }
        position(self, near: anchor)
        orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }
}

private struct PillView: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .help("Refine selected text (⌥⌘R)")
    }
}

// MARK: - Refine panel

@MainActor
final class RefineModel: ObservableObject {
    @Published var target: TextTarget?
    @Published var mode: RefineMode = .improve
    @Published var instruction = ""
    @Published var suggestions: [String] = []
    @Published var isLoading = false
    @Published var error: String?

    var onFinish: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private var task: Task<Void, Never>?

    var isEditable: Bool { target?.isEditable ?? true }
    var modes: [RefineMode] { isEditable ? RefineMode.editing : RefineMode.reading }

    func load(_ target: TextTarget) {
        self.target = target
        mode = target.isEditable ? .improve : .simplify
        instruction = ""
        refine()
    }

    func select(_ mode: RefineMode) {
        self.mode = mode
        refine()
    }

    func refine() {
        guard let text = target?.text else { return }
        task?.cancel()
        isLoading = true
        error = nil
        suggestions = []
        // Writers pick from alternatives; readers just want one clear version.
        let mode = mode, instruction = instruction, count = isEditable ? Settings.suggestionCount : 1
        task = Task {
            do {
                let result = try await ClaudeClient().refine(text, mode: mode, instruction: instruction, count: count)
                guard !Task.isCancelled else { return }
                suggestions = result
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func use(_ suggestion: String) {
        guard let target else { return }
        onFinish?()
        AX.replace(target, with: suggestion)
    }

    func copy(_ suggestion: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestion, forType: .string)
    }

    func cancel() {
        task?.cancel()
        isLoading = false
    }
}

final class RefinePanel: NSPanel {
    let model = RefineModel()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        title = "Refine"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = FirstMouseHostingView(rootView: RefineView(model: model))
        model.onFinish = { [weak self] in self?.close() }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        model.cancel()
        super.close()
    }

    func present(_ target: TextTarget) {
        title = target.isEditable ? "Refine" : "Simplify"
        model.load(target)
        position(self, near: target.bounds)
        makeKeyAndOrderFront(nil)
    }
}

private struct RefineView: View {
    @ObservedObject var model: RefineModel
    @AppStorage(Settings.fontSizeKey) private var fontSize = Settings.defaultFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(model.target?.text ?? "")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: fontSize * 5)

            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.select($0) })) {
                ForEach(model.modes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                TextField(model.isEditable
                          ? "Extra instruction (optional), e.g. sound more confident"
                          : "Extra instruction (optional), e.g. answer in Thai",
                          text: $model.instruction)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.refine() }
                Button("Refine") { model.refine() }
                    .disabled(model.isLoading)
            }

            Divider()

            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .padding(.top, 14)
        .font(.system(size: fontSize))
        .frame(minWidth: 420, minHeight: 360)
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            ProgressView("Refining…")
        } else if let error = model.error {
            VStack(spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if model.target != nil, Settings.apiKey == nil {
                    Button("Open Settings") { model.onOpenSettings?() }
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SuggestionRow(index: index, text: suggestion,
                                      onUse: model.isEditable ? { model.use(suggestion) } : nil,
                                      onCopy: { model.copy(suggestion) })
                    }
                }
            }
        }
    }
}

private struct SuggestionRow: View {
    let index: Int
    let text: String
    /// Nil for read-only text, which can't be replaced.
    let onUse: (() -> Void)?
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                if let onUse {
                    Button("Use", action: onUse)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .help("Replace the selection (⌘\(index + 1))")
                    Button("Copy", action: onCopy).buttonStyle(.link)
                } else {
                    Button("Copy", action: onCopy)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("Copy (⇧⌘C)")
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
