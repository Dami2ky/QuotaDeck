import Foundation

// MARK: - GLM / Z.ai Coding Plan

/// 查询协议与 ZCode 官方一致:
///   GET {base}/api/monitor/usage/quota/limit   Authorization: Bearer <coding-plan api key>
///   响应 data.limits: [{ type: "TIME_LIMIT" | ..., unit, number, usage, currentValue,
///                        remaining, percentage, nextResetTime, usageDetails }]
///   GET https://zcode.z.ai/api/v1/mcp/usage → { total_usage:{used,limit,remaining}, next_refresh_at }
/// 无 key 时回退:读 ~/.zcode/cli/db/db.sqlite 本地估算 5 小时窗口。
public struct GLMProvider: QuotaProvider {
    public let id = "glm"
    public let displayName = "GLM / Z.ai"
    let http = SimpleHTTP()

    public init() {}

    public func isConfigured(_ cfg: AppConfig) -> Bool {
        cfg.glm.enabled && (!cfg.glm.apiKey.isEmpty || cfg.glm.useLocalFallback)
    }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(
            id: id, name: displayName,
            subtitle: cfg.glm.teamContext ? "BigModel Coding Plan · 团队版" : "BigModel Coding Plan",
            state: .ok
        )
        var raws: [String] = []

        var gotRemote = false
        if !cfg.glm.apiKey.isEmpty {
            do {
                let win = try await fetchQuotaLimit(cfg, &raws)
                status.windows.append(contentsOf: win)
                gotRemote = !win.isEmpty
            } catch {
                raws.append("quota/limit 失败: \(error.localizedDescription)")
            }
            if cfg.glm.mcpEnabled {
                if let mcp = try? await fetchMcpUsage(cfg, &raws) {
                    status.windows.append(mcp)
                }
            }
        }

        if !gotRemote, cfg.glm.useLocalFallback, let snap = ZCodeLocal.snapshot() {
            // 本地估算:5 小时窗口 + 周(7 天滚动)窗口
            let limit = max(1, cfg.glm.assumed5hPromptLimit)
            let frac = max(0, 1.0 - Double(snap.promptsInWindow) / Double(limit))
            status.windows.append(QuotaWindow(
                kind: .fiveHour,
                remainingFraction: frac,
                remainingText: TimeFormat.countdown(to: snap.windowClosesAt) ?? "窗口未开启",
                resetsAt: snap.windowClosesAt,
                detail: "本地估算:窗口内 \(snap.promptsInWindow)/\(limit) prompts · 近24h \(snap.promptsIn24h)",
                source: .localEstimate
            ))
            let wLimit = max(1, cfg.glm.assumedWeeklyPromptLimit)
            let wFrac = max(0, 1.0 - Double(snap.promptsIn7d) / Double(wLimit))
            status.windows.append(QuotaWindow(
                kind: .weekly,
                remainingFraction: wFrac,
                detail: "本地估算:近7天 \(snap.promptsIn7d)/\(wLimit) prompts",
                source: .localEstimate
            ))
            status.subtitle = (status.subtitle ?? "") + " · 本地估算"
            raws.append("本地数据库: \(ZCodeLocal.dbURL.path)")
            if let avail = snap.planEntryAvailable {
                raws.append("套餐缓存: \(avail ? "有可用套餐入口" : "无可用套餐入口")")
            }
        }

        status.rawResponse = raws.joined(separator: "\n\n")
        if status.windows.isEmpty {
            if !cfg.glm.apiKey.isEmpty {
                status.state = .error
                status.errorMessage = "API 查询失败,且本地无用量数据(详见诊断)"
            } else {
                status.state = .notConfigured
                status.errorMessage = "未配置 API Key,仅本地估算(无 ~/.zcode 数据)"
            }
        }
        status.lastUpdated = Date()
        return status
    }

    /// quota/limit 接口 → 窗口列表
    func fetchQuotaLimit(_ cfg: AppConfig, _ raws: inout [String]) async throws -> [QuotaWindow] {
        var base = cfg.glm.quotaBase
        if base.hasSuffix("/") { base.removeLast() }
        var url = base + "/api/monitor/usage/quota/limit"
        if cfg.glm.teamContext { url += "?type=2" }

        let (data, resp) = try await http.get(url, headers: SimpleHTTP.bearer(cfg.glm.apiKey))
        raws.append("[quota/limit] " + SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode))
        guard let obj = JSON.parse(data),
              let dataObj = JSON.dict(obj)?["data"],
              let limits = JSON.array(JSON.dict(dataObj)?["limits"]), !limits.isEmpty
        else { throw HTTPError.httpStatus(resp.statusCode, "响应缺少 data.limits") }

        return limits.map(mapLimit)
    }

    func mapLimit(_ limit: [String: Any]) -> QuotaWindow {
        let type = JSON.string(limit, "type") ?? ""
        let unit = JSON.string(limit, "unit") ?? ""
        let cap = JSON.double(limit, "number")
        let used = JSON.double(limit, "usage") ?? JSON.double(limit, "currentValue")
        let remaining = JSON.double(limit, "remaining")
        let percentage = JSON.double(limit, "percentage")
        let reset = JSON.date(limit, "nextResetTime")

        var kind: WindowKind
        if type.uppercased().contains("TIME") || type.uppercased().contains("FIVE") || type.uppercased().contains("5H") {
            kind = .fiveHour
        } else if type.uppercased().contains("WEEK") {
            kind = .weekly
        } else if type.uppercased().contains("MCP") {
            kind = .mcp
        } else {
            kind = .other
        }
        // unit 数字语义(ClaudeBar 对照验证):3=5h 窗,6=周窗,7=月窗——type 识别不出时按 unit 兜底
        if kind == .other, let u = JSON.double(limit, "unit") {
            if u == 3 { kind = .fiveHour }
            else if u == 6 { kind = .weekly }
        }

        var frac: Double?
        if let r = remaining, let c = cap, c > 0 {
            frac = min(1, max(0, r / c))
        } else if let p = percentage {
            // percentage 语义按"已用百分比"处理(与 ZCode UI 一致),余量 = 1 - p
            frac = min(1, max(0, 1 - p / 100))
        } else if let u = used, let c = cap, c > 0 {
            frac = min(1, max(0, 1 - u / c))
        }

        var detail: String? = nil
        if let u = used, let c = cap {
            detail = "已用 \(fmt(u)) / 上限 \(fmt(c)) \(unit)"
        } else if let r = remaining {
            detail = "剩余 \(fmt(r)) \(unit)"
        } else if let p = percentage {
            detail = "已用 \(fmt(p))%"
        }
        return QuotaWindow(
            kind: kind,
            label: kind.defaultLabel,
            remainingFraction: frac,
            remainingText: TimeFormat.countdown(to: reset) ?? (remaining.map { "剩 \(fmt($0)) \(unit)" }),
            resetsAt: reset,
            detail: detail,
            source: .server
        )
    }

    /// MCP 额度(zcode.z.ai,通常需 ZCode 在线凭据;失败静默)
    func fetchMcpUsage(_ cfg: AppConfig, _ raws: inout [String]) async throws -> QuotaWindow? {
        let url = "https://zcode.z.ai/api/v1/mcp/usage"
        do {
            let (data, resp) = try await http.get(url, headers: SimpleHTTP.bearer(cfg.glm.apiKey))
            raws.append("[mcp/usage] " + SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode))
            guard let obj = JSON.parse(data),
                  let total = JSON.dict(JSON.dict(obj)?["total_usage"]) else { return nil }
            let used = JSON.double(total, "used") ?? 0
            let limitV = JSON.double(total, "limit") ?? 0
            let remaining = JSON.double(total, "remaining")
            let frac: Double? = (limitV > 0 && remaining != nil) ? min(1, max(0, remaining! / limitV)) : nil
            return QuotaWindow(
                kind: .mcp,
                remainingFraction: frac,
                remainingText: remaining.map { "剩 \(fmt($0))" },
                resetsAt: JSON.date(obj, "next_refresh_at"),
                detail: "已用 \(fmt(used)) / 上限 \(fmt(limitV))"
            )
        } catch {
            raws.append("[mcp/usage] 失败(忽略): \(error.localizedDescription)")
            return nil
        }
    }

    func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
