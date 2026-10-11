import Foundation
import QuotaDeckCore

// planbar CLI —— 数据层验证与终端输出
// 用法:
//   planbar            拉取全部并打印表格
//   planbar --json     输出 JSON
//   planbar --raw      附带原始响应(诊断)

let args = Set(CommandLine.arguments.dropFirst())
let wantJson = args.contains("--json")
let wantRaw = args.contains("--raw")

let cfg = ConfigStore.load()
let providers = ProviderRegistry.providers(for: cfg)

if providers.isEmpty {
    print("没有已启用的接入。配置文件: \(ConfigStore.configURL.path)")
    print("GLM 本地估算默认启用;中转站/Kimi/Grok/Codex 需在配置中填 key 后启用。")
    exit(0)
}

let sem = DispatchSemaphore(value: 0)
var statuses: [ProviderStatus] = []

Task {
    let collected = await withTaskGroup(of: ProviderStatus.self) { group in
        for p in providers {
            group.addTask { await p.fetch(cfg) }
        }
        var out: [ProviderStatus] = []
        for await s in group { out.append(s) }
        return out
    }
    // 输出顺序 = provider 列表顺序(即集成页的用户排序)
    let byId = Dictionary(collected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    statuses = providers.compactMap { byId[$0.id] }
    sem.signal()
}
sem.wait()

if wantJson {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    if let data = try? enc.encode(statuses) {
        print(String(data: data, encoding: .utf8) ?? "[]")
    }
} else {
    print("QuotaDeck · Coding Plan 余量  (\(Date().formatted()))")
    print(String(repeating: "─", count: 64))
    for s in statuses {
        let mark: String
        switch s.state {
        case .ok: mark = "✓"
        case .notConfigured: mark = "○"
        case .error: mark = "✗"
        case .disabled: mark = "–"
        }
        print("\(mark) \(s.name)\(s.subtitle.map { "  · \($0)" } ?? "")")
        if s.windows.isEmpty {
            print("    \(s.errorMessage ?? "(无额度数据)")")
        }
        for w in s.windows {
            var line = "    ▸ \(w.label)"
            if let f = w.remainingFraction {
                let filled = Int((f * 20).rounded())
                line += "  [\(String(repeating: "█", count: filled))\(String(repeating: "░", count: 20 - filled))] \(Int((f * 100).rounded()))%"
            }
            if let t = w.remainingText { line += "  \(t)" }
            if let c = TimeFormat.countdown(to: w.resetsAt) { line += "  (重置剩 \(c))" }
            print(line)
            if let d = w.detail { print("        \(d)") }
        }
        if s.state == .error, let e = s.errorMessage { print("    ⚠ \(e)") }
        if wantRaw, let raw = s.rawResponse {
            print("    ── 原始响应 ──")
            raw.split(separator: "\n").forEach { print("    | \($0)") }
        }
        print()
    }
}
