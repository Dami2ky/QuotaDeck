import Foundation

// MARK: - Provider 协议与注册表

public protocol QuotaProvider {
    var id: String { get }
    var displayName: String { get }
    /// 是否已配置(决定显示"未配置"还是发起请求)
    func isConfigured(_ cfg: AppConfig) -> Bool
    func fetch(_ cfg: AppConfig) async -> ProviderStatus
}

extension QuotaProvider {
    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        ProviderStatus(id: id, name: displayName, state: .error, errorMessage: "该接入未实现")
    }
}

public enum ProviderRegistry {
    static let knownFamilies = ["glm", "minimax", "deepseek", "relays", "kimi", "grok", "codex"]

    /// 归一化用户排序:剔除未知项,缺失的家族按默认顺序补到末尾
    public static func normalizedOrder(_ order: [String]) -> [String] {
        var seen = Set<String>()
        var out = order.filter { knownFamilies.contains($0) && seen.insert($0).inserted }
        for f in knownFamilies where !seen.contains(f) {
            out.append(f)
            seen.insert(f)
        }
        return out
    }

    /// 按配置装配全部 Provider(顺序 = 用户排序)
    public static func providers(for cfg: AppConfig) -> [QuotaProvider] {
        var groups: [String: [QuotaProvider]] = [:]
        if cfg.glm.enabled { groups["glm"] = [GLMProvider()] }
        if cfg.minimax.enabled { groups["minimax"] = [MiniMaxProvider()] }
        if cfg.deepseek.enabled { groups["deepseek"] = [DeepSeekProvider()] }
        let activeRelays = cfg.relays.filter(\.enabled).map { RelayProvider(relay: $0) }
        if !activeRelays.isEmpty { groups["relays"] = activeRelays }
        if cfg.kimi.enabled { groups["kimi"] = [KimiProvider()] }
        if cfg.grok.enabled { groups["grok"] = [GrokProvider()] }
        if cfg.codex.enabled { groups["codex"] = [CodexProvider()] }
        return normalizedOrder(cfg.providerOrder).flatMap { groups[$0] ?? [] }
    }

    /// 未配置/停用的家也展示出来(置灰),让用户知道可以开;顺序同用户排序
    public static func placeholderStatuses(for cfg: AppConfig) -> [ProviderStatus] {
        var byFamily: [String: [ProviderStatus]] = [:]
        if !cfg.glm.enabled {
            byFamily["glm"] = [ProviderStatus(id: "glm", name: "GLM / Z.ai", state: .disabled)]
        }
        if !cfg.minimax.enabled {
            byFamily["minimax"] = [ProviderStatus(id: "minimax", name: "MiniMax", subtitle: "Token Plan · 直连", state: .notConfigured)]
        }
        if !cfg.deepseek.enabled {
            byFamily["deepseek"] = [ProviderStatus(id: "deepseek", name: "DeepSeek", subtitle: "开放平台余额", state: .notConfigured)]
        }
        if !cfg.kimi.enabled {
            byFamily["kimi"] = [ProviderStatus(id: "kimi", name: "Kimi", subtitle: "Coding Plan", state: .notConfigured)]
        }
        if !cfg.grok.enabled {
            byFamily["grok"] = [ProviderStatus(id: "grok", name: "Grok", subtitle: "xAI", state: .notConfigured)]
        }
        if !cfg.codex.enabled {
            byFamily["codex"] = [ProviderStatus(id: "codex", name: "Codex", subtitle: "ChatGPT 订阅", state: .notConfigured)]
        }
        return normalizedOrder(cfg.providerOrder).flatMap { byFamily[$0] ?? [] }
    }
}
