import Foundation

// MARK: - 额度窗口模型

public enum WindowKind: String, Codable, CaseIterable {
    case fiveHour = "5小时"
    case weekly = "周额度"
    case mcp = "MCP"
    case balance = "余额"
    case other = "其他"

    public var defaultLabel: String {
        switch self {
        case .fiveHour: return "5小时余量"
        case .weekly: return "周余量"
        case .mcp: return "MCP额度"
        case .balance: return "余额"
        case .other: return "额度"
        }
    }
}

/// 一条额度信息:5小时窗口 / 周窗口 / MCP / 余额
public struct QuotaWindow: Identifiable, Codable, Hashable {
    public var kind: WindowKind
    public var label: String
    /// 剩余比例 0...1,nil 表示未知(不画进度条)
    public var remainingFraction: Double?
    /// 人类可读的剩余描述,如 "2小时5分"、"$12.34"
    public var remainingText: String?
    /// 窗口重置/关闭时刻
    public var resetsAt: Date?
    /// 明细,如 "已用 30 / 120 prompts(本地估算)"
    public var detail: String?

    public var id: String { kind.rawValue + "|" + label }

    public init(
        kind: WindowKind,
        label: String? = nil,
        remainingFraction: Double? = nil,
        remainingText: String? = nil,
        resetsAt: Date? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.label = label ?? kind.defaultLabel
        self.remainingFraction = remainingFraction
        self.remainingText = remainingText
        self.resetsAt = resetsAt
        self.detail = detail
    }
}

// MARK: - Provider 状态

public enum ProviderState: String, Codable {
    case ok
    case notConfigured
    case error
    case disabled

    public var label: String {
        switch self {
        case .ok: return "正常"
        case .notConfigured: return "未配置"
        case .error: return "异常"
        case .disabled: return "已停用"
        }
    }
}

public struct ProviderStatus: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var subtitle: String?
    public var state: ProviderState
    public var windows: [QuotaWindow]
    public var lastUpdated: Date?
    public var errorMessage: String?
    /// 诊断用:最近一次原始响应(截断)
    public var rawResponse: String?

    public init(
        id: String,
        name: String,
        subtitle: String? = nil,
        state: ProviderState = .ok,
        windows: [QuotaWindow] = [],
        lastUpdated: Date? = nil,
        errorMessage: String? = nil,
        rawResponse: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.state = state
        self.windows = windows
        self.lastUpdated = lastUpdated
        self.errorMessage = errorMessage
        self.rawResponse = rawResponse
    }

    /// 所有窗口里最紧张的一个,用于菜单栏摘要
    public var mostCritical: QuotaWindow? {
        windows.filter { $0.remainingFraction != nil }
            .min { ($0.remainingFraction ?? 1) < ($1.remainingFraction ?? 1) }
    }
}

// MARK: - 时间格式化

public enum TimeFormat {
    /// 把"距重置还有多久"格式化为 "2小时5分" / "4天3小时"
    public static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let sec = date.timeIntervalSince(now)
        guard sec > 0 else { return nil }
        let m = Int(sec) / 60
        if m < 60 { return "\(m)分钟" }
        let h = m / 60
        if h < 48 { return "\(h)小时\(m % 60)分" }
        let d = h / 24
        return "\(d)天\(h % 24)小时"
    }
}
