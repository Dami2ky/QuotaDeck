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
    /// 本地估算时假定的周(7 天滚动)prompt 上限
    public var assumedWeeklyPromptLimit: Int
    public var quotaBase: String
    /// MCP 额度查询(需要 ZCode 凭据,通常失败,仅尝试)
    public var mcpEnabled: Bool

    public init(
        enabled: Bool = true,
        apiKey: String = "",
        teamContext: Bool = false,
        useLocalFallback: Bool = true,
        assumed5hPromptLimit: Int = 120,
        assumedWeeklyPromptLimit: Int = 500,
        quotaBase: String = "https://open.bigmodel.cn",
        mcpEnabled: Bool = false
    ) {
        self.enabled = enabled
        self.apiKey = apiKey
        self.teamContext = teamContext
        self.useLocalFallback = useLocalFallback
        self.assumed5hPromptLimit = assumed5hPromptLimit
        self.assumedWeeklyPromptLimit = assumedWeeklyPromptLimit
        self.quotaBase = quotaBase
        self.mcpEnabled = mcpEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, apiKey, teamContext, useLocalFallback
        case assumed5hPromptLimit, assumedWeeklyPromptLimit, quotaBase, mcpEnabled
    }

    /// 手写解码:老配置缺新字段(如周上限)时回退默认值
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        teamContext = try c.decodeIfPresent(Bool.self, forKey: .teamContext) ?? false
        useLocalFallback = try c.decodeIfPresent(Bool.self, forKey: .useLocalFallback) ?? true
        assumed5hPromptLimit = try c.decodeIfPresent(Int.self, forKey: .assumed5hPromptLimit) ?? 120
        assumedWeeklyPromptLimit = try c.decodeIfPresent(Int.self, forKey: .assumedWeeklyPromptLimit) ?? 500
        quotaBase = try c.decodeIfPresent(String.self, forKey: .quotaBase) ?? "https://open.bigmodel.cn"
        mcpEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? false
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
    /// 各家显示顺序(集成页拖动调整,总览/菜单栏/诊断同步生效)
    public var providerOrder: [String]
    public var glm: GLMConfig
    public var minimax: KeyedProviderConfig
    public var deepseek: KeyedProviderConfig
    public var relays: [RelayConfig]
    public var kimi: KeyedProviderConfig
    public var grok: KeyedProviderConfig
    public var codex: KeyedProviderConfig

    public init(
        refreshIntervalSec: Int = 60,
        providerOrder: [String] = ["glm", "minimax", "deepseek", "relays", "kimi", "grok", "codex"],
        glm: GLMConfig = GLMConfig(),
        minimax: KeyedProviderConfig = KeyedProviderConfig(),
        deepseek: KeyedProviderConfig = KeyedProviderConfig(),
        relays: [RelayConfig] = [],
        kimi: KeyedProviderConfig = KeyedProviderConfig(),
        grok: KeyedProviderConfig = KeyedProviderConfig(),
        codex: KeyedProviderConfig = KeyedProviderConfig()
    ) {
        self.refreshIntervalSec = refreshIntervalSec
        self.providerOrder = providerOrder
        self.glm = glm
        self.minimax = minimax
        self.deepseek = deepseek
        self.relays = relays
        self.kimi = kimi
        self.grok = grok
        self.codex = codex
    }

    private enum CodingKeys: String, CodingKey {
        case refreshIntervalSec, providerOrder, glm, minimax, deepseek, relays, kimi, grok, codex
    }

    /// 手写解码:老配置缺少新增字段(如 minimax/deepseek)时回退默认值,避免整份配置被重置
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalSec = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSec) ?? 60
        providerOrder = try c.decodeIfPresent([String].self, forKey: .providerOrder)
            ?? ["glm", "minimax", "deepseek", "relays", "kimi", "grok", "codex"]
        glm = try c.decodeIfPresent(GLMConfig.self, forKey: .glm) ?? GLMConfig()
        minimax = try c.decodeIfPresent(KeyedProviderConfig.self, forKey: .minimax) ?? KeyedProviderConfig()
        deepseek = try c.decodeIfPresent(KeyedProviderConfig.self, forKey: .deepseek) ?? KeyedProviderConfig()
        relays = try c.decodeIfPresent([RelayConfig].self, forKey: .relays) ?? []
        kimi = try c.decodeIfPresent(KeyedProviderConfig.self, forKey: .kimi) ?? KeyedProviderConfig()
        grok = try c.decodeIfPresent(KeyedProviderConfig.self, forKey: .grok) ?? KeyedProviderConfig()
        codex = try c.decodeIfPresent(KeyedProviderConfig.self, forKey: .codex) ?? KeyedProviderConfig()
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
            var merged = cfg
            migrateMinimax(cfg: &merged)
            return merged
        }
        var cfg = AppConfig()
        if cfg.relays.isEmpty, let detected = detectClaudeRelay() {
            cfg.relays = [detected]
        }
        migrateMinimax(cfg: &cfg)
        try? cfg.save()
        return cfg
    }

    /// MiniMax 直连迁移(幂等):
    /// 1) 旧版把 Claude Code 的 MiniMax 通道(api.minimaxi.com/anthropic)当中转站导入过,
    ///    它不是 new-api 类站点、查不了计费接口——把 key 搬给 MiniMax provider 后停用该条目;
    /// 2) 若 MiniMax 还没有 key,直接从 ~/.claude/settings.json 借 MiniMax 通道的 token。
    static func migrateMinimax(cfg: inout AppConfig) {
        let hosts: Set<String> = ["api.minimaxi.com", "api.minimax.io"]
        var changed = false
        for idx in cfg.relays.indices where cfg.relays[idx].enabled {
            guard let host = URL(string: cfg.relays[idx].baseUrl)?.host?.lowercased(),
                  hosts.contains(host) else { continue }
            if cfg.minimax.apiKey.isEmpty, !cfg.relays[idx].apiKey.isEmpty {
                cfg.minimax.apiKey = cfg.relays[idx].apiKey
                cfg.minimax.enabled = true
            }
            cfg.relays[idx].enabled = false
            changed = true
        }
        if cfg.minimax.apiKey.isEmpty,
           let base = claudeAnthropicValue("ANTHROPIC_BASE_URL"),
           let host = URL(string: base)?.host?.lowercased(),
           hosts.contains(host),
           let token = claudeAnthropicValue("ANTHROPIC_AUTH_TOKEN") {
            cfg.minimax.apiKey = token
            cfg.minimax.enabled = true
            changed = true
        }
        if changed { try? cfg.save() }
    }

    static func claudeAnthropicValue(_ key: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let env = obj["env"] as? [String: String]
        else { return nil }
        let v = env[key] ?? ""
        return v.isEmpty ? nil : v
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
        // MiniMax 官方直连通道走专用 provider,不当中转站导入
        if let host = URL(string: base)?.host?.lowercased(),
           host == "api.minimaxi.com" || host == "api.minimax.io" { return nil }
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
