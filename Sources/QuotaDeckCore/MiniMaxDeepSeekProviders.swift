import Foundation

// MARK: - MiniMax 直连(Token Plan)

/// 协议(源自 ClaudeBar 的 provider 定义,其已对照 MiniMax 控制台验证):
///   GET https://api.minimaxi.com/v1/token_plan/remains   Authorization: Bearer <key>
///   响应 { base_resp:{status_code,status_msg}, model_remains:[{
///       model_name,
///       current_interval_total_count, current_interval_usage_count,
///       current_interval_remaining_percent, current_weekly_remaining_percent,
///       start_time, end_time, weekly_start_time, weekly_end_time   ← 毫秒时间戳
///   }] }
/// 两种形态:
///   - Token Plan:count 字段全 0,只有百分比有效
///   - legacy count:坑——current_interval_usage_count 名为"已用"实为「剩余」数
/// 全 0 且无百分比的模型不产出窗口(宁缺勿假 0%)。
public struct MiniMaxProvider: QuotaProvider {
    public let id = "minimax"
    public let displayName = "MiniMax"
    let http = SimpleHTTP()

    public init() {}

    public func isConfigured(_ cfg: AppConfig) -> Bool {
        cfg.minimax.enabled && !cfg.minimax.apiKey.isEmpty
    }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(id: id, name: displayName, subtitle: "Token Plan · 直连", state: .ok)
        guard isConfigured(cfg) else {
            status.state = .notConfigured
            status.errorMessage = "需要 MiniMax 平台 Key(platform.minimaxi.com)"
            return status
        }
        do {
            let (data, resp) = try await http.get(
                "https://api.minimaxi.com/v1/token_plan/remains",
                headers: SimpleHTTP.bearer(cfg.minimax.apiKey)
            )
            status.rawResponse = SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode)
            guard let obj = JSON.parse(data) else {
                throw HTTPError.httpStatus(resp.statusCode, "响应非 JSON")
            }
            if let baseResp = JSON.dict(obj)?["base_resp"],
               let code = JSON.double(baseResp, "status_code"), code != 0 {
                throw HTTPError.httpStatus(resp.statusCode, JSON.string(baseResp, "status_msg") ?? "接口返回错误 \(Int(code))")
            }
            guard let models = JSON.array(JSON.dict(obj)?["model_remains"]), !models.isEmpty else {
                status.state = .error
                status.errorMessage = "无模型额度数据(原始响应见诊断)"
                status.lastUpdated = Date()
                return status
            }
            status.windows = models.flatMap(Self.windows(for:))
            if status.windows.isEmpty {
                status.state = .error
                status.errorMessage = "各模型均无有效余量字段(Key 可能无效或结构变化,见诊断)"
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

    /// 每个模型产 5h + 周两条窗口
    static func windows(for m: [String: Any]) -> [QuotaWindow] {
        let name = JSON.string(m, "model_name") ?? "模型"
        let total = JSON.double(m, "current_interval_total_count") ?? 0
        // 坑:legacy 形态里 usage_count 实为「剩余」数(ClaudeBar 对照控制台验证过)
        let remainingCount = JSON.double(m, "current_interval_usage_count")
        let pct5 = JSON.double(m, "current_interval_remaining_percent")
        let pctWeekly = JSON.double(m, "current_weekly_remaining_percent")
        var out: [QuotaWindow] = []

        // count 形态优先(total>0 才可信),否则退回百分比形态
        let frac5: Double?
        let text5: String?
        if total > 0, let rc = remainingCount {
            frac5 = min(1, max(0, rc / total))
            text5 = "剩 \(Int(rc))/\(Int(total))"
        } else if let p = pct5 {
            frac5 = min(1, max(0, p / 100))
            text5 = TimeFormat.countdown(to: JSON.date(m, "end_time"))
        } else {
            frac5 = nil
            text5 = nil
        }
        if let f = frac5 {
            out.append(QuotaWindow(
                kind: .fiveHour,
                label: name,
                remainingFraction: f,
                remainingText: text5,
                resetsAt: JSON.date(m, "end_time"),
                source: .server
            ))
        }

        if let p = pctWeekly {
            out.append(QuotaWindow(
                kind: .weekly,
                label: name + " · 周",
                remainingFraction: min(1, max(0, p / 100)),
                resetsAt: JSON.date(m, "weekly_end_time"),
                source: .server
            ))
        }
        return out
    }
}

// MARK: - DeepSeek 开放平台余额

/// 官方接口:GET https://api.deepseek.com/user/balance   Authorization: Bearer sk-...
/// 响应 { is_available: Bool, balance_infos: [{ currency: "CNY",
///        total_balance: "110.00", granted_balance: "10.00", topped_up_balance: "100.00" }] }
/// (金额为字符串,支持多币种条目)
public struct DeepSeekProvider: QuotaProvider {
    public let id = "deepseek"
    public let displayName = "DeepSeek"
    let http = SimpleHTTP()

    public init() {}

    public func isConfigured(_ cfg: AppConfig) -> Bool {
        cfg.deepseek.enabled && !cfg.deepseek.apiKey.isEmpty
    }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(id: id, name: displayName, subtitle: "开放平台 · 按量余额", state: .ok)
        guard isConfigured(cfg) else {
            status.state = .notConfigured
            status.errorMessage = "需要 DeepSeek 开放平台 sk- Key(platform.deepseek.com)"
            return status
        }
        do {
            let (data, resp) = try await http.get(
                "https://api.deepseek.com/user/balance",
                headers: SimpleHTTP.bearer(cfg.deepseek.apiKey)
            )
            status.rawResponse = SimpleHTTP.diagnoseText(data, statusCode: resp.statusCode)
            guard let obj = JSON.parse(data),
                  let infos = JSON.array(JSON.dict(obj)?["balance_infos"]), !infos.isEmpty else {
                throw HTTPError.httpStatus(resp.statusCode, "响应缺少 balance_infos")
            }
            let available = (JSON.dict(obj)?["is_available"] as? Bool) ?? true
            var windows: [QuotaWindow] = []
            for info in infos {
                guard let total = JSON.double(info, "total_balance") else { continue }
                let currency = JSON.string(info, "currency") ?? ""
                let symbol = currency == "CNY" ? "¥" : (currency == "USD" ? "$" : "")
                let granted = JSON.double(info, "granted_balance") ?? 0
                let topped = JSON.double(info, "topped_up_balance") ?? 0
                windows.append(QuotaWindow(
                    kind: .balance,
                    label: currency.isEmpty ? "余额" : "余额 · \(currency)",
                    remainingText: symbol + String(format: "%.2f", total),
                    detail: String(format: "充值 %@%.2f · 赠送 %@%.2f", symbol, topped, symbol, granted)
                        + (available ? "" : " · 服务暂不可用"),
                    source: .server
                ))
            }
            guard !windows.isEmpty else {
                status.state = .error
                status.errorMessage = "未能解析余额(原始响应见诊断)"
                status.lastUpdated = Date()
                return status
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
}
