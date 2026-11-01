import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = SelectionMonitor()
    private let pill = PillPanel()
    private let refinePanel = RefinePanel()
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var pillTarget: TextTarget?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        setUpEditMenu()

        monitor.onSelection = { [weak self] target in self?.selectionChanged(target) }
        monitor.onClear = { [weak self] in self?.hidePill() }
        pill.onClick = { [weak self] in
            guard let self, let target = pillTarget else { return }
            hidePill()
            refinePanel.present(target)
        }
        refinePanel.model.onOpenSettings = { [weak self] in self?.openSettings() }

        hotKey = HotKey(keyCode: kVK_ANSI_R, modifiers: cmdKey | optionKey) { [weak self] in
            self?.refineCurrentSelection()
        }

        startMonitoringWhenTrusted()
        if Settings.apiKey == nil { openSettings() }
    }

    /// Global key monitors need the Accessibility permission, so wait until it's granted.
    private func startMonitoringWhenTrusted() {
        if AX.isTrusted {
            monitor.start()
            return
        }
        AX.requestTrust()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AX.isTrusted else { return }
            timer.invalidate()
            Task { @MainActor in self?.monitor.start() }
        }
    }

    private func selectionChanged(_ target: TextTarget) {
        guard Settings.showPill, !refinePanel.isVisible,
              target.isEditable || Settings.showPillForReading else { return }
        pillTarget = target
        pill.show(near: target.bounds, title: target.isEditable ? "Refine" : "Simplify")
    }

    private func hidePill() {
        pillTarget = nil
        pill.orderOut(nil)
    }

    @objc private func refineCurrentSelection() {
        guard AX.isTrusted else {
            AX.requestTrust()
            return
        }
        if let target = AX.captureSelection() {
            present(target)
            return
        }
        // A browser may only now be building its accessibility tree; give it a moment and retry.
        if let app = NSWorkspace.shared.frontmostApplication { AX.enableAccessibility(for: app) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if let target = AX.captureSelection() {
                self?.present(target)
                return
            }
            // Still nothing (e.g. text on a Chrome page): copy the selection as read-only text.
            guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else {
                NSSound.beep()
                return
            }
            AX.copySelection(from: app) { target in
                if let target { self?.present(target) } else { NSSound.beep() }
            }
        }
    }

    private func present(_ target: TextTarget) {
        hidePill()
        refinePanel.present(target)
    }

    // MARK: - Menu bar

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Refiner")

        let menu = NSMenu()
        let refine = NSMenuItem(title: "Refine Selection", action: #selector(refineCurrentSelection), keyEquivalent: "r")
        refine.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(refine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Refiner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    /// A menu-bar-only app has no visible main menu, but text fields still rely on its
    /// Edit items for ⌘X/⌘C/⌘V/⌘A/⌘Z, so install one that's never shown.
    private func setUpEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem()) // app menu slot
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Refiner Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
