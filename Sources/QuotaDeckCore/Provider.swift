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
    /// 按配置装配全部 Provider(顺序即界面展示顺序)
    public static func providers(for cfg: AppConfig) -> [QuotaProvider] {
        var list: [QuotaProvider] = []
        if cfg.glm.enabled { list.append(GLMProvider()) }
        for relay in cfg.relays where relay.enabled {
            list.append(RelayProvider(relay: relay))
        }
        if cfg.kimi.enabled { list.append(KimiProvider()) }
        if cfg.grok.enabled { list.append(GrokProvider()) }
        if cfg.codex.enabled { list.append(CodexProvider()) }
        return list
    }

    /// 未配置/停用的家也展示出来(置灰),让用户知道可以开
    public static func placeholderStatuses(for cfg: AppConfig) -> [ProviderStatus] {
        var list: [ProviderStatus] = []
        if !cfg.glm.enabled {
            list.append(ProviderStatus(id: "glm", name: "GLM / Z.ai", state: .disabled))
        }
        if !cfg.kimi.enabled {
            list.append(ProviderStatus(id: "kimi", name: "Kimi", subtitle: "Coding Plan", state: .notConfigured))
        }
        if !cfg.grok.enabled {
            list.append(ProviderStatus(id: "grok", name: "Grok", subtitle: "xAI", state: .notConfigured))
        }
        if !cfg.codex.enabled {
            list.append(ProviderStatus(id: "codex", name: "Codex", subtitle: "ChatGPT 订阅", state: .notConfigured))
        }
        return list
    }
}
