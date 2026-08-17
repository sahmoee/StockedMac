import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated enum MacAIBackend: String, CaseIterable, Identifiable {
    case automatic = "Automatic — Apple on-device first"
    case managed = "Stocked managed service"
    case custom = "My private Worker"
    var id: String { rawValue }
}

nonisolated enum MacAIProvider: String, CaseIterable, Identifiable {
    case anthropic = "Anthropic — Claude"
    case openAI = "OpenAI — ChatGPT models"
    var id: String { rawValue }
    var headerValue: String { self == .openAI ? "openai" : "anthropic" }
}

nonisolated enum MacAIConfiguration {
    private static let backendKey = "stockedmac.ai.backend"
    private static let endpointKey = "stockedmac.ai.endpoint"
    private static let modelKey = "stockedmac.ai.model"
    private static let providerKey = "stockedmac.ai.provider"
    private static let managedUnlockKey = "stockedmac.ai.managedSettingsUnlocked"
    private static let service = "com.sowens.StockedMac.ai"
    private static let account = "worker-token"

    static var backend: MacAIBackend {
        get { MacAIBackend(rawValue: UserDefaults.standard.string(forKey: backendKey) ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: backendKey) }
    }
    static var provider: MacAIProvider {
        get { MacAIProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .anthropic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }
    static var managedSettingsUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: managedUnlockKey) }
        set { UserDefaults.standard.set(newValue, forKey: managedUnlockKey) }
    }
    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }
    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: endpointKey) }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set {
            let safe = String(newValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
                .filter { $0.isLetter || $0.isNumber || "-_.:/".contains($0) }
            UserDefaults.standard.set(safe, forKey: modelKey)
        }
    }
    static var baseURL: URL? {
        if backend == .custom, let value = URL(string: endpoint), value.scheme == "https" { return value }
        guard managedSettingsUnlocked else { return nil }
        return URL(string: MacBuildConfig.receiptWorkerURL)
    }
    static var token: String { readToken() ?? "" }

    static func saveToken(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    static func apply(to request: inout URLRequest) {
        if backend == .custom, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if !model.isEmpty { request.setValue(model, forHTTPHeaderField: "X-AI-Model") }
        request.setValue(provider.headerValue, forHTTPHeaderField: "X-AI-Provider")
        request.setValue(backend == .custom ? "custom-worker" : "managed", forHTTPHeaderField: "X-AI-Agent")
    }
    private static func readToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
