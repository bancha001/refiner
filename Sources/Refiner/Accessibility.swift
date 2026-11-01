import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// A text selection captured in another app.
struct TextTarget {
    let app: NSRunningApplication
    /// Nil when the text was read by copying rather than through Accessibility.
    let element: AXUIElement?
    let text: String
    let range: CFRange?
    /// Selection bounds in Cocoa screen coordinates (bottom-left origin), when the app reports them.
    let bounds: CGRect?
    /// False for read-only text (web pages, received mail…), which can be simplified but not replaced.
    let isEditable: Bool
}

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Reads the selection from the focused element of the frontmost app.
    static func captureSelection() -> TextTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid(),
              let element = focusedElement(),
              !isSecure(element),
              let text: String = attribute(element, kAXSelectedTextAttribute),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let range = selectedRange(element)
        return TextTarget(app: app, element: element, text: text, range: range,
                          bounds: range.flatMap { bounds(of: $0, in: element) },
                          isEditable: isEditable(element))
    }

    /// Fallback for apps that don't expose their selection (e.g. Chrome page text): copy it with ⌘C,
    /// read the clipboard, then put the clipboard back.
    static func copySelection(from app: NSRunningApplication, completion: @escaping (TextTarget?) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard()
        let before = pasteboard.changeCount
        postCommandKey(kVK_ANSI_C)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pasteboard.changeCount != before else { return completion(nil) }
            let text = pasteboard.string(forType: .string) ?? ""
            restorePasteboard(saved)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return completion(nil) }
            completion(TextTarget(app: app, element: nil, text: text, range: nil, bounds: nil, isEditable: false))
        }
    }

    /// Puts `newText` in place of the captured selection. Tries the Accessibility API first and
    /// falls back to a clipboard paste for apps (often web views) that ignore AX writes.
    static func replace(_ target: TextTarget, with newText: String) {
        guard target.isEditable, let element = target.element else { return }
        target.app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            // Only restore the range if the selection was lost; web editors count offsets differently.
            let current: String? = attribute(element, kAXSelectedTextAttribute)
            if current != target.text, var range = target.range, let value = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
            // Web editors such as Gmail handle a paste reliably (and keep undo); AX writes are hit-or-miss.
            if isBrowser(target.app) {
                paste(newText)
                return
            }
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, newText as CFString)
            if result != .success || !valueContains(element, newText) {
                paste(newText)
            }
        }
    }

    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium",
    ]

    static func isBrowser(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return chromiumBrowsers.contains(id) || id == "com.apple.Safari" || id == "org.mozilla.firefox"
    }

    /// Chromium browsers and Electron apps only expose web content to AX when asked.
    static func enableAccessibility(for app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let result = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result != .success, let id = app.bundleIdentifier, chromiumBrowsers.contains(id) {
            // Older Chromium builds only respond to the flag VoiceOver sets.
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    // MARK: - Helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        for name in [kAXSelectedTextAttribute, kAXValueAttribute] {
            if AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success, settable.boolValue {
                return true
            }
        }
        let role: String? = attribute(element, kAXRoleAttribute)
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let subrole: String? = attribute(element, kAXSubroleAttribute)
        return subrole == kAXSecureTextFieldSubrole
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    private static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var range = range
        var value: CFTypeRef?
        guard let axRange = AXValueCreate(.cfRange, &range),
              AXUIElementCopyParameterizedAttributeValue(
                  element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        // AX uses a top-left origin on the primary screen; Cocoa uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// True when the field's value contains `text`, or when the value can't be read (trust the AX write).
    private static func valueContains(_ element: AXUIElement, _ text: String) -> Bool {
        guard let value: String = attribute(element, kAXValueAttribute) else { return true }
        return value.contains(text)
    }

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandKey(kVK_ANSI_V)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { restorePasteboard(saved) }
    }

    private static func postCommandKey(_ keyCode: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Copies every item and type on the clipboard so it can be restored exactly, images included.
    private static func snapshotPasteboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restorePasteboard(_ items: [NSPasteboardItem]) {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items)
    }
}
