import Foundation

// MARK: - Kimi Coding Plan

/// 官方接口:GET https://api.kimi.com/coding/v1/usages  Authorization: Bearer sk-kimi-...
/// (Key 在 Kimi Code 控制台创建,不是 Moonshot 开放平台的 key)
public struct KimiProvider: QuotaProvider {
    public let id = "kimi"
    public let displayName = "Kimi"
    let http = SimpleHTTP()

    public init() {}

    public func isConfigured(_ cfg: AppConfig) -> Bool { !cfg.kimi.apiKey.isEmpty }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(id: id, name: displayName, subtitle: "Kimi Coding Plan", state: .ok)
        guard isConfigured(cfg) else {
            status.state = .notConfigured
            status.errorMessage = "需要 Kimi Code 控制台的 sk-kimi- Key"
            return status
        }
        do {
            let (data, resp) = try await http.get(
                "https://api.kimi.com/coding/v1/usages",
                headers: SimpleHTTP.bearer(cfg.kimi.apiKey)
            )
            status.rawResponse = SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode)
            guard let obj = JSON.parse(data) else {
                throw HTTPError.httpStatus(resp.statusCode, "响应非 JSON")
            }
            let windows = parseUsages(obj)
            if windows.isEmpty, let err = JSON.string(obj, "error_message") ?? JSON.string(obj, "message") {
                status.state = .error
                status.errorMessage = err
            }
            status.windows = windows
            status.lastUpdated = Date()
            return status
        } catch {
            status.state = .error
            status.errorMessage = error.localizedDescription
            status.lastUpdated = Date()
            return status
        }
    }

    /// 响应结构随版本变化,做宽松解析:递归找带 used/limit 类字段的对象
    func parseUsages(_ obj: Any) -> [QuotaWindow] {
        var result: [QuotaWindow] = []
        walk(obj, &result, depth: 0)
        return result
    }

    private func walk(_ node: Any, _ out: inout [QuotaWindow], depth: Int) {
        guard depth < 5, out.count < 6 else { return }
        if let arr = node as? [Any] {
            for item in arr { walk(item, &out, depth: depth + 1) }
            return
        }
        guard let dict = node as? [String: Any] else { return }

        let used = JSON.double(dict, "used") ?? JSON.double(dict, "usage")
        let limit = JSON.double(dict, "limit") ?? JSON.double(dict, "quota") ?? JSON.double(dict, "total")
        let remaining = JSON.double(dict, "remaining")
        if used != nil || remaining != nil, limit != nil || remaining != nil {
            let tag = JSON.string(dict, "type") ?? JSON.string(dict, "window") ?? JSON.string(dict, "name") ?? ""
            let lower = tag.lowercased()
            let kind: WindowKind = {
                if lower.contains("week") || lower.contains("周") { return .weekly }
                if lower.contains("hour") || lower.contains("5h") || lower.contains("小时") { return .fiveHour }
                return .other
            }()
            let cap = limit ?? ((used ?? 0) + (remaining ?? 0))
            var frac: Double? = nil
            if cap > 0 {
                if let r = remaining { frac = min(1, max(0, r / cap)) }
                else if let u = used { frac = min(1, max(0, 1 - u / cap)) }
            }
            out.append(QuotaWindow(
                kind: kind,
                label: tag.isEmpty ? kind.defaultLabel : tag,
                remainingFraction: frac,
                remainingText: remaining.map { "剩 \(String(format: "%.0f", $0))" },
                resetsAt: JSON.date(dict, "reset_at") ?? JSON.date(dict, "resetAt") ?? JSON.date(dict, "expired_at"),
                detail: "已用 \(String(format: "%.0f", used ?? 0)) / 上限 \(String(format: "%.0f", cap))"
            ))
            return
        }
        for (_, v) in dict { walk(v, &out, depth: depth + 1) }
    }
}

// MARK: - Grok(xAI)

/// xAI 官方管理接口查余额/credits:
///   GET https://api.x.ai/v1/api-key  Authorization: Bearer <xai key>
public struct GrokProvider: QuotaProvider {
    public let id = "grok"
    public let displayName = "Grok"
    let http = SimpleHTTP()

    public init() {}

    public func isConfigured(_ cfg: AppConfig) -> Bool { !cfg.grok.apiKey.isEmpty }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(id: id, name: displayName, subtitle: "xAI API", state: .ok)
        guard isConfigured(cfg) else {
            status.state = .notConfigured
            status.errorMessage = "需要 xAI API Key(console.x.ai)"
            return status
        }
        do {
            let (data, resp) = try await http.get(
                "https://api.x.ai/v1/api-key",
                headers: SimpleHTTP.bearer(cfg.grok.apiKey)
            )
            status.rawResponse = SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode)
            guard let obj = JSON.parse(data) else {
                throw HTTPError.httpStatus(resp.statusCode, "响应非 JSON")
            }
            // credits 信息常见形态:{credits_used, credits_remaining, balance, ...} 或嵌套 credits:{...}
            let body = JSON.dict(obj)?["data"] ?? obj
            var used: Double? = nil
            var remain: Double? = nil
            if let credits = JSON.dict(body)?["credits"] {
                used = JSON.double(credits, "used") ?? JSON.double(credits, "credits_used")
                remain = JSON.double(credits, "remaining") ?? JSON.double(credits, "balance")
            }
            used = used ?? JSON.double(body, "credits_used")
            remain = remain ?? JSON.double(body, "credits_remaining") ?? JSON.double(body, "balance")
            guard remain != nil || used != nil else {
                status.state = .error
                status.errorMessage = "未能从响应中解析余额(结构可能变化,原始响应见诊断)"
                return status
            }
            let r = remain ?? 0
            let u = used ?? 0
            status.windows = [
                QuotaWindow(
                    kind: .balance,
                    label: "预估余额",
                    remainingFraction: (r + u) > 0 ? min(1, r / (r + u)) : nil,
                    remainingText: String(format: "%.2f USD", r),
                    detail: String(format: "已消耗 %.2f USD", u)
                )
            ]
            status.lastUpdated = Date()
            return status
        } catch {
            status.state = .error
            status.errorMessage = error.localizedDescription
            status.lastUpdated = Date()
            return status
        }
    }
}

// MARK: - Codex(ChatGPT 订阅)

/// 非官方接口(社区通用):GET https://chatgpt.com/backend-api/rate_limits
/// 凭据优先读 ~/.codex/auth.json 的 access_token(订阅模式),否则提示未配置。
public struct CodexProvider: QuotaProvider {
    public let id = "codex"
    public let displayName = "Codex"
    let http = SimpleHTTP()

    public init() {}

    public func isConfigured(_ cfg: AppConfig) -> Bool {
        !cfg.codex.apiKey.isEmpty || localAccessToken() != nil
    }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(id: id, name: displayName, subtitle: "ChatGPT 订阅", state: .ok)

        let token: String?
        if !cfg.codex.apiKey.isEmpty {
            token = cfg.codex.apiKey
        } else if let local = localAccessToken() {
            token = local
            status.subtitle = "ChatGPT 订阅 · 本机 ~/.codex"
        } else {
            status.state = .notConfigured
            status.errorMessage = "本机 ~/.codex 为 API Key/中转模式,无订阅额度;如需查询请在集成页填 ChatGPT 访问令牌"
            status.rawResponse = "~/.codex/auth.json 仅含 OPENAI_API_KEY"
            return status
        }

        do {
            let (data, resp) = try await http.get(
                "https://chatgpt.com/backend-api/rate_limits",
                headers: SimpleHTTP.bearer(token!)
            )
            status.rawResponse = SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode)
            guard let obj = JSON.parse(data) else {
                throw HTTPError.httpStatus(resp.statusCode, "响应非 JSON")
            }
            status.windows = parseRateLimits(obj)
            if status.windows.isEmpty {
                status.state = .error
                status.errorMessage = "未能解析 rate_limits(非官方接口,结构可能变化)"
            }
            status.lastUpdated = Date()
            return status
        } catch {
            status.state = .error
            status.errorMessage = error.localizedDescription
            status.lastUpdated = Date()
            return status
        }
    }

    /// 典型字段:codex_5h_updates_used / window / weekly_limits
    func parseRateLimits(_ obj: Any) -> [QuotaWindow] {
        var out: [QuotaWindow] = []
        guard let dict = obj as? [String: Any] else { return out }
        for (key, value) in dict {
            let lower = key.lowercased()
            guard let v = value as? [String: Any] else { continue }
            if lower.contains("5h") || lower.contains("five") {
                out.append(limitWindow(v, kind: .fiveHour))
            } else if lower.contains("week") {
                out.append(limitWindow(v, kind: .weekly))
            }
        }
        return out
    }

    func limitWindow(_ v: [String: Any], kind: WindowKind) -> QuotaWindow {
        let used = JSON.double(v, "used") ?? JSON.double(v, "updates_used")
        let cap = JSON.double(v, "limit") ?? JSON.double(v, "window")
        let frac: Double? = (used != nil && cap != nil && cap! > 0)
            ? min(1, max(0, 1 - used! / cap!)) : nil
        return QuotaWindow(
            kind: kind,
            remainingFraction: frac,
            remainingText: TimeFormat.countdown(to: JSON.date(v, "resets_at") ?? JSON.date(v, "reset_at")),
            resetsAt: JSON.date(v, "resets_at") ?? JSON.date(v, "reset_at"),
            detail: "已用 \(used.map { String(format: "%.0f", $0) } ?? "?") / \(cap.map { String(format: "%.0f", $0) } ?? "?")"
        )
    }

    func localAccessToken() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let obj = JSON.parse(data),
              let tokens = JSON.dict(obj)?["tokens"],
              let access = JSON.string(tokens, "access_token")
        else { return nil }
        return access
    }
}
