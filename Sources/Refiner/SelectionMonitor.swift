import AppKit

/// Watches typing and mouse selection in other apps and reports when an editable field
/// has a non-empty selection.
@MainActor
final class SelectionMonitor {
    var onSelection: ((TextTarget) -> Void)?
    var onClear: (() -> Void)?

    private var monitors: [Any] = []
    private var pending: DispatchWorkItem?

    func start() {
        guard monitors.isEmpty else { return }
        if let mouse = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.schedule(after: 0.12)
        }) { monitors.append(mouse) }
        // Covers shift+arrow selection, ⌘A, and clearing the pill once the user keeps typing.
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: { [weak self] _ in
            self?.schedule(after: 0.25)
        }) { monitors.append(keys) }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                AX.enableAccessibility(for: app)
            }
        }
        // Apps that were already running and frontmost never send an activation notification.
        for app in NSWorkspace.shared.runningApplications where AX.isBrowser(app) {
            AX.enableAccessibility(for: app)
        }
        if let app = NSWorkspace.shared.frontmostApplication { AX.enableAccessibility(for: app) }
    }

    private func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func check() {
        if let target = AX.captureSelection() {
            onSelection?(target)
        } else {
            onClear?()
        }
    }
}
