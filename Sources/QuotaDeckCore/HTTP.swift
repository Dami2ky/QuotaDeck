import Foundation

// MARK: - 极简 HTTP 客户端

public enum HTTPError: Error, LocalizedError {
    case badURL(String)
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .badURL(let u): return "无效地址: \(u)"
        case .httpStatus(let code, let body): return "HTTP \(code) \(String(body.prefix(200)))"
        }
    }
}

public struct SimpleHTTP {
    public let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 15
        // 直连:绕过系统/环境代理(本 shell 常见的 127.0.0.1 代理未必在线,目标均为国内可达接口)
        cfg.connectionProxyDictionary = [:]
        session = URLSession(configuration: cfg)
    }

    @discardableResult
    public func get(
        _ urlString: String,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw HTTPError.badURL(urlString) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw HTTPError.httpStatus(-1, "非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    public static func bearer(_ key: String) -> [String: String] {
        ["Authorization": key.hasPrefix("Bearer") ? key : "Bearer \(key)"]
    }

    /// 原始响应文本(诊断用,截断)
    public static func diagnoseText(_ data: Data?, statusCode: Int? = nil) -> String {
        guard let data, !data.isEmpty else { return "(空响应" + (statusCode.map { ", HTTP \($0)" } ?? "") + ")" }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let prefix = statusCode.map { "HTTP \($0) · " } ?? ""
        return prefix + String(text.prefix(3000))
    }
}

// MARK: - JSON 宽松取值

public enum JSON {
    public static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    public static func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }

    public static func array(_ any: Any?) -> [[String: Any]]? {
        (any as? [Any])?.compactMap { $0 as? [String: Any] }
    }

    public static func double(_ any: Any?, _ key: String) -> Double? {
        guard let v = (any as? [String: Any])?[key] else { return nil }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    public static func int(_ any: Any?, _ key: String) -> Int? {
        double(any, key).map(Int.init)
    }

    public static func string(_ any: Any?, _ key: String) -> String? {
        (any as? [String: Any])?[key] as? String
    }

    /// 秒/毫秒时间戳自适应转 Date
    public static func date(_ any: Any?, _ key: String) -> Date? {
        guard let t = double(any, key), t > 0 else { return nil }
        return t > 1e12 ? Date(timeIntervalSince1970: t / 1000) : Date(timeIntervalSince1970: t)
    }
}
