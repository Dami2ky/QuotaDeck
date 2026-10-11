import Foundation

// MARK: - 刷新记录(统计页)

public struct ProviderRefreshOutcome: Codable, Hashable {
    public var providerId: String
    public var ok: Bool
    public var durationMs: Int
    public var error: String?
}

public struct RefreshRecord: Codable, Identifiable, Hashable {
    public var id: UUID = UUID()
    public var time: Date
    public var outcomes: [ProviderRefreshOutcome]

    public var okCount: Int { outcomes.filter(\.ok).count }
    public var failCount: Int { outcomes.count - okCount }
}

// MARK: - 状态缓存

enum StatusCache {
    static var url: URL { ConfigStore.appSupportDir.appendingPathComponent("status-cache.json") }

    static func save(_ statuses: [ProviderStatus]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(statuses) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> [ProviderStatus]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode([ProviderStatus].self, from: data)
    }
}

// MARK: - Store

@MainActor
public final class Store: ObservableObject {
    @Published public private(set) var statuses: [ProviderStatus] = []
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var refreshing = false
    @Published public private(set) var history: [RefreshRecord] = []
    @Published public var config: AppConfig {
        didSet { ConfigStore.save(config) }
    }

    private var providers: [QuotaProvider] = []
    private var loopTask: Task<Void, Never>?

    public init(config: AppConfig? = nil) {
        let cfg = config ?? ConfigStore.load()
        self.config = cfg
        if let cached = StatusCache.load() {
            self.statuses = cached
            self.lastRefresh = cached.compactMap(\.lastUpdated).max()
        }
        rebuildProviders()
        startAutoRefresh()
    }

    public func rebuildProviders() {
        providers = ProviderRegistry.providers(for: config)
        // 追加未启用的占位,让总览可见
        let placeholders = ProviderRegistry.placeholderStatuses(for: config)
        let activeIds = providers.map(\.id)
        let known = Set(statuses.map(\.id))
        let extra = placeholders.filter { !activeIds.contains($0.id) && !known.contains($0.id) }
        statuses.append(contentsOf: extra)
    }

    /// 启动定时刷新循环
    public func startAutoRefresh() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(15, self.config.refreshIntervalSec)
                await self.refreshAll()
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    public func stopAutoRefresh() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// 并发刷新全部 Provider
    public func refreshAll() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        // 同步一次最新配置里的 provider 集合
        providers = ProviderRegistry.providers(for: config)
        let list = providers
        let cfg = config
        guard !list.isEmpty else {
            statuses = ProviderRegistry.placeholderStatuses(for: config)
            return
        }

        let started = Date()
        let results = await withTaskGroup(of: (QuotaProvider, ProviderStatus, Int).self) { group in
            for p in list {
                group.addTask {
                    let t0 = DispatchTime.now()
                    var status = await p.fetch(cfg)
                    let ms = Int((DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000)
                    status.state = (status.state == .ok && status.errorMessage == nil) ? .ok : status.state
                    return (p, status, ms)
                }
            }
            var collected: [(QuotaProvider, ProviderStatus, Int)] = []
            for await r in group { collected.append(r) }
            return collected
        }

        var record = RefreshRecord(time: started, outcomes: [])
        var merged: [ProviderStatus] = []
        for (p, status, ms) in results.sorted(by: { $0.1.name < $1.1.name }) {
            let ok = status.state == .ok
            record.outcomes.append(ProviderRefreshOutcome(
                providerId: p.id, ok: ok, durationMs: ms,
                error: ok ? nil : (status.errorMessage ?? "未知错误")
            ))
            merged.append(status)
        }
        // 保留未启用的占位
        let activeIds = Set(list.map(\.id))
        merged.append(contentsOf: statuses.filter { !activeIds.contains($0.id) && $0.windows.isEmpty })
        statuses = merged
        lastRefresh = started
        history.append(record)
        if history.count > 50 { history.removeFirst(history.count - 50) }
        StatusCache.save(statuses)
    }

    /// 菜单栏摘要:最紧张的一个窗口
    public var menuTitle: String {
        let candidates = statuses.flatMap { s -> [(String, QuotaWindow)] in
            s.windows.map { (s.name, $0) }
        }
        .filter { $0.1.remainingFraction != nil }
        guard let worst = candidates.min(by: {
            ($0.1.remainingFraction ?? 1) < ($1.1.remainingFraction ?? 1)
        }) else {
            return "QuotaDeck"
        }
        let pct = Int(((worst.1.remainingFraction ?? 1) * 100).rounded())
        let short = worst.1.kind == .weekly ? "周" : (worst.1.kind == .fiveHour ? "5h" : "")
        let name = worst.0.prefix(6)
        return short.isEmpty ? "\(name) \(pct)%" : "\(name) \(short) \(pct)%"
    }

    /// 手动编辑配置后调用
    public func applyConfigChange() {
        rebuildProviders()
    }
}
