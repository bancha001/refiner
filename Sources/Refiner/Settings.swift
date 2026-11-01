import AppKit
import Security
import SwiftUI

enum Settings {
    static let showPillKey = "showFloatingButton"
    private static let apiKeyAccount = "anthropic-api-key"

    /// The Keychain entry wins; ANTHROPIC_API_KEY is a fallback for launches from a terminal.
    static var apiKey: String? {
        Keychain.read(apiKeyAccount) ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    static func saveAPIKey(_ key: String) {
        Keychain.write(apiKeyAccount, key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static let showPillForReadingKey = "showButtonForReadOnlyText"
    static let fontSizeKey = "panelFontSize"
    static let defaultFontSize = 15.0
    static let modelKey = "model"
    static let suggestionCountKey = "suggestionCount"
    static let defaultSuggestionCount = 3

    /// How many rewrites to offer for text you're writing (1–3). Read-only text always gets one.
    static var suggestionCount: Int {
        let value = UserDefaults.standard.object(forKey: suggestionCountKey) as? Int ?? defaultSuggestionCount
        return min(max(value, 1), 3)
    }

    static var model: ClaudeModel {
        UserDefaults.standard.string(forKey: modelKey).flatMap(ClaudeModel.init(rawValue:)) ?? .opus
    }

    static var showPill: Bool {
        UserDefaults.standard.object(forKey: showPillKey) as? Bool ?? true
    }

    static var showPillForReading: Bool {
        UserDefaults.standard.object(forKey: showPillForReadingKey) as? Bool ?? true
    }
}

enum Keychain {
    private static let service = "com.refiner.app"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ account: String, _ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

struct SettingsView: View {
    @AppStorage(Settings.showPillKey) private var showPill = true
    @AppStorage(Settings.showPillForReadingKey) private var showPillForReading = true
    @AppStorage(Settings.fontSizeKey) private var fontSize = Settings.defaultFontSize
    @AppStorage(Settings.modelKey) private var model = ClaudeModel.opus
    @AppStorage(Settings.suggestionCountKey) private var suggestionCount = Settings.defaultSuggestionCount
    @State private var apiKey = Settings.apiKey ?? ""
    @State private var saved = false
    @State private var trusted = AX.isTrusted

    var body: some View {
        Form {
            Section("Claude API") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic API key")
                    SecureField("Anthropic API key", text: $apiKey, prompt: Text("sk-ant-…"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Save") {
                        Settings.saveAPIKey(apiKey)
                        saved = true
                    }
                    if saved { Text("Saved").foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Model", selection: $model) {
                        ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                    }
                    Text(model.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Behavior") {
                Picker("Suggestions per refine", selection: $suggestionCount) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show ✨ button when text is selected", isOn: $showPill)
                Toggle("Also for read-only text (web pages, received mail)", isOn: $showPillForReading)
                    .disabled(!showPill)
                Stepper("Text size: \(Int(fontSize)) pt", value: $fontSize, in: 12...24)
                LabeledContent("Refine selection", value: "⌥⌘R")
            }
            Section("Permissions") {
                LabeledContent("Accessibility", value: trusted ? "Granted" : "Not granted")
                if !trusted {
                    Button("Open Accessibility Settings") {
                        AX.requestTrust()
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 580)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AX.isTrusted
        }
    }
}
