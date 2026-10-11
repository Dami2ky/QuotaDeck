import Foundation

// MARK: - 中转站(new-api / one-api 兼容)

/// 查询协议(OpenAI 计费面板兼容,绝大多数中转站支持):
///   GET {base}/v1/dashboard/billing/subscription → { hard_limit_usd, ... }
///   GET {base}/v1/dashboard/billing/usage?start_date=&end_date= → { total_usage }(单位:美分)
public struct RelayProvider: QuotaProvider {
    public let relay: RelayConfig
    let http = SimpleHTTP()

    public var id: String { "relay:" + relay.name }
    public var displayName: String { "中转站 · " + relay.name }

    public init(relay: RelayConfig) { self.relay = relay }

    public func isConfigured(_ cfg: AppConfig) -> Bool {
        !relay.baseUrl.isEmpty && !relay.apiKey.isEmpty
    }

    public func fetch(_ cfg: AppConfig) async -> ProviderStatus {
        var status = ProviderStatus(id: id, name: displayName, subtitle: relay.baseUrl, state: .ok)
        guard isConfigured(cfg) else {
            status.state = .notConfigured
            status.errorMessage = "缺少站点地址或 API Key"
            return status
        }
        var baseVar = relay.baseUrl
        if baseVar.hasSuffix("/") { baseVar.removeLast() }
        // 有些配置填的是 .../v1 结尾,归一化到根
        if baseVar.hasSuffix("/v1") { baseVar.removeLast(3) }
        let base = baseVar

        do {
            async let sub = http.get(base + "/v1/dashboard/billing/subscription", headers: SimpleHTTP.bearer(relay.apiKey))
            async let usage = fetchUsage(base)

            let (subData, subResp) = try await sub
            let (usageData, usageResp) = try await usage

            status.rawResponse = """
            [subscription] \(SimpleHTTP.diagnoseText(subData, statusCode: subResp.statusCode))
            [usage] \(SimpleHTTP.diagnoseText(usageData, statusCode: usageResp.statusCode))
            """

            guard let subObj = JSON.parse(subData) else {
                throw HTTPError.httpStatus(subResp.statusCode, "subscription 响应非 JSON")
            }
            // 兼容一层包裹:{data:{...}} 或直接 {...}
            let subBody = JSON.dict(subObj)?["data"] ?? subObj
            let hardLimit = JSON.double(subBody, "hard_limit_usd")
                ?? JSON.double(subBody, "system_hard_limit_usd") ?? 0

            var usedUsd: Double? = nil
            if let usageObj = JSON.parse(usageData) {
                let usageBody = JSON.dict(usageObj)?["data"] ?? usageObj
                if let total = JSON.double(usageBody, "total_usage") {
                    usedUsd = total / 100  // total_usage 单位是 0.01 USD
                }
            }

            guard hardLimit > 0 else {
                status.state = .error
                status.errorMessage = "站点未返回 hard_limit_usd(可能不支持计费接口)"
                return status
            }
            let used = usedUsd ?? 0
            let remain = max(0, hardLimit - used)
            status.windows = [
                QuotaWindow(
                    kind: .balance,
                    label: "Key 余额",
                    remainingFraction: min(1, remain / hardLimit),
                    remainingText: String(format: "$%.2f", remain),
                    detail: String(format: "额度 $%.2f · 已用 $%.2f", hardLimit, used)
                )
            ]
            status.lastUpdated = Date()
            return status
        } catch {
            status.state = .error
            if case HTTPError.httpStatus(let code, _) = error, code == 404 {
                status.errorMessage = "该站点不支持 new-api 计费接口(404)。中转站模块适用于 new-api / one-api 类站点;厂商直连端点(如 MiniMax/DeepSeek 官方 API)不适用,可在集成页删除此条目。"
            } else {
                status.errorMessage = error.localizedDescription
            }
            status.lastUpdated = Date()
            return status
        }
    }

    func fetchUsage(_ base: String) async throws -> (Data, HTTPURLResponse) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let start = df.string(from: monthStart)
        let end = df.string(from: now)
        return try await http.get(
            base + "/v1/dashboard/billing/usage?start_date=\(start)&end_date=\(end)",
            headers: SimpleHTTP.bearer(relay.apiKey)
        )
    }
}
