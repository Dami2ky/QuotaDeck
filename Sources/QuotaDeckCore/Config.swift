import Foundation

// MARK: - 配置模型

public struct RelayConfig: Codable, Hashable {
    public var rid: UUID
    public var name: String
    public var baseUrl: String
    public var apiKey: String
    public var enabled: Bool

    public init(name: String, baseUrl: String = "", apiKey: String = "", enabled: Bool = true) {
        self.rid = UUID()
        self.name = name
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.enabled = enabled
    }
}

public struct GLMConfig: Codable, Hashable {
    public var enabled: Bool
    /// BigModel Coding Plan 的 API Key(bigmodel.cn 控制台获取)
    public var apiKey: String
    /// 团队版套餐(接口加 ?type=2)
    public var teamContext: Bool
    /// 无 key 时用 ~/.zcode 本地数据库估算 5 小时窗口
    public var useLocalFallback: Bool
    /// 本地估算时假定的 5 小时 prompt 上限
    public var assumed5hPromptLimit: Int
    public var quotaBase: String
    /// MCP 额度查询(需要 ZCode 凭据,通常失败,仅尝试)
    public var mcpEnabled: Bool

    public init(
        enabled: Bool = true,
        apiKey: String = "",
        teamContext: Bool = false,
        useLocalFallback: Bool = true,
        assumed5hPromptLimit: Int = 120,
        quotaBase: String = "https://open.bigmodel.cn",
        mcpEnabled: Bool = false
    ) {
        self.enabled = enabled
        self.apiKey = apiKey
        self.teamContext = teamContext
        self.useLocalFallback = useLocalFallback
        self.assumed5hPromptLimit = assumed5hPromptLimit
        self.quotaBase = quotaBase
        self.mcpEnabled = mcpEnabled
    }
}

public struct KeyedProviderConfig: Codable, Hashable {
    public var enabled: Bool
    public var apiKey: String

    public init(enabled: Bool = false, apiKey: String = "") {
        self.enabled = enabled
        self.apiKey = apiKey
    }
}

public struct AppConfig: Codable, Equatable {
    public var refreshIntervalSec: Int
    public var glm: GLMConfig
    public var relays: [RelayConfig]
    public var kimi: KeyedProviderConfig
    public var grok: KeyedProviderConfig
    public var codex: KeyedProviderConfig

    public init(
        refreshIntervalSec: Int = 60,
        glm: GLMConfig = GLMConfig(),
        relays: [RelayConfig] = [],
        kimi: KeyedProviderConfig = KeyedProviderConfig(),
        grok: KeyedProviderConfig = KeyedProviderConfig(),
        codex: KeyedProviderConfig = KeyedProviderConfig()
    ) {
        self.refreshIntervalSec = refreshIntervalSec
        self.glm = glm
        self.relays = relays
        self.kimi = kimi
        self.grok = grok
        self.codex = codex
    }
}

// MARK: - 配置读写

public enum ConfigStore {
    public static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("QuotaDeck", isDirectory: true)
        migrateLegacyPlanBarDir(dir)
        return dir
    }

    /// 旧版(PlanBar 时期)的配置目录自动迁移
    static func migrateLegacyPlanBarDir(_ newDir: URL) {
        let fm = FileManager.default
        let legacy = newDir.deletingLastPathComponent().appendingPathComponent("PlanBar", isDirectory: true)
        guard !fm.fileExists(atPath: newDir.path),
              fm.fileExists(atPath: legacy.path) else { return }
        try? fm.moveItem(at: legacy, to: newDir)
    }

    public static var configURL: URL { appSupportDir.appendingPathComponent("config.json") }

    /// 读取配置;不存在则生成默认配置(尝试从 Claude Code 设置导入中转站)
    public static func load() -> AppConfig {
        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        var cfg = AppConfig()
        if cfg.relays.isEmpty, let detected = detectClaudeRelay() {
            cfg.relays = [detected]
        }
        try? cfg.save()
        return cfg
    }

    public static func save(_ cfg: AppConfig) {
        try? cfg.save()
    }

    /// 从 ~/.claude/settings.json 的 env 里探测 Claude Code 正在使用的中转站
    static func detectClaudeRelay() -> RelayConfig? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let env = obj["env"] as? [String: String]
        else { return nil }
        guard let base = env["ANTHROPIC_BASE_URL"], !base.isEmpty,
              let token = env["ANTHROPIC_AUTH_TOKEN"], !token.isEmpty
        else { return nil }
        var b = base
        if b.hasSuffix("/") { b.removeLast() }
        return RelayConfig(
            name: "自动导入 · Claude Code",
            baseUrl: b,
            apiKey: token,
            enabled: true
        )
    }
}

extension AppConfig {
    /// 写入磁盘并收紧权限(内含 API key)
    public func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: ConfigStore.appSupportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        try data.write(to: ConfigStore.configURL, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ConfigStore.configURL.path)
    }
}
