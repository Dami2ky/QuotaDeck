import SwiftUI
import AppKit
import QuotaDeckCore

// MARK: - 管理窗口(左侧导航 + 四个页面)

enum Page: String, CaseIterable, Identifiable {
    case overview = "总览"
    case integrations = "集成"
    case stats = "统计"
    case diagnostics = "诊断"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .integrations: return "puzzlepiece"
        case .stats: return "chart.bar"
        case .diagnostics: return "stethoscope"
        }
    }
}

struct MainSplitView: View {
    @ObservedObject var store: Store
    @State private var page: Page = .overview

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.rawValue, systemImage: p.icon)
                    .tag(p)
            }
            .navigationSplitViewColumnWidth(160)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch page {
                case .overview: OverviewView(store: store)
                case .integrations: IntegrationsView(store: store)
                case .stats: StatsView(store: store)
                case .diagnostics: DiagnosticsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("QuotaDeck")
        .onAppear { store.startAutoRefresh() }
    }
}

// MARK: - 总览

struct OverviewView: View {
    @ObservedObject var store: Store

    private let columns = [GridItem(.adaptive(minimum: 380, maximum: 480), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(store.statuses) { status in
                    ProviderCard(status: status)
                }
            }
            .padding(20)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 16) {
                if store.refreshing { ProgressView().controlSize(.small) }
                Text(store.lastRefresh.map { "上次刷新 \($0.formatted())" } ?? "尚未刷新")
                Spacer()
                Button("立即刷新") { Task { await store.refreshAll() } }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task { await store.refreshAll() }
    }
}

struct ProviderCard: View {
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.name).font(.title3.weight(.semibold))
                    if let sub = status.subtitle {
                        Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                stateView
            }

            if status.windows.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(status.errorMessage ?? "暂无数据")
                        .lineLimit(2)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(status.windows) { w in
                        WindowRow(window: w)
                    }
                }
            }

            HStack {
                Spacer()
                Text(status.lastUpdated.map { "更新 \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .opacity(status.state == .disabled || status.state == .notConfigured ? 0.6 : 1)
    }

    @ViewBuilder
    private var stateView: some View {
        switch status.state {
        case .ok:
            Label(status.state.label, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .error:
            Label(status.state.label, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .notConfigured:
            Text(status.state.label).font(.caption)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        case .disabled:
            Text(status.state.label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WindowRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label).font(.caption.weight(.medium))
                if window.source == .localEstimate {
                    Text("估算").font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(.orange)
                }
                if let t = window.remainingText {
                    Text(t).font(.caption.monospacedDigit().weight(.semibold))
                }
                Spacer()
                if let f = window.remainingFraction {
                    Text("\(Int((f * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(BarShape.color(f))
                }
            }
            BarShape(fraction: window.remainingFraction)
            HStack {
                if let d = window.detail {
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let r = window.resetsAt {
                    Text("重置 \(r.formatted(date: .omitted, time: .shortened))(剩 \(TimeFormat.countdown(to: r) ?? "-"))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - 集成(配置)

struct IntegrationsView: View {
    @ObservedObject var store: Store

    static let familyTitles: [String: String] = [
        "glm": "GLM / Z.ai",
        "minimax": "MiniMax",
        "deepseek": "DeepSeek",
        "relays": "中转站",
        "kimi": "Kimi",
        "grok": "Grok",
        "codex": "Codex",
    ]

    var body: some View {
        Form {
            Section("显示顺序(拖动或用箭头调整,总览 / 菜单栏 / 诊断同步生效)") {
                ForEach(store.config.providerOrder, id: \.self) { fid in
                    HStack {
                        Label(Self.familyTitles[fid] ?? fid, systemImage: "line.3.horizontal")
                        Spacer()
                        Button {
                            moveFamily(fid, -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            moveFamily(fid, +1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    store.config.providerOrder.move(fromOffsets: from, toOffset: to)
                }
            }

            ForEach(store.config.providerOrder, id: \.self) { fid in
                familySection(fid)
            }

            Section("通用") {
                Stepper("刷新间隔:\(store.config.refreshIntervalSec) 秒",
                        value: $store.config.refreshIntervalSec, in: 30...900, step: 30)
                Text("配置文件:\(ConfigStore.configURL.path)")
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.config) { _, _ in
            store.applyConfigChange()
        }
    }

    /// 箭头按钮移动某家到上/下一个位置
    private func moveFamily(_ fid: String, _ delta: Int) {
        var order = store.config.providerOrder
        guard let idx = order.firstIndex(of: fid) else { return }
        let target = idx + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(idx, target)
        store.config.providerOrder = order
    }

    @ViewBuilder
    private func familySection(_ fid: String) -> some View {
        switch fid {
        case "glm":
            Section("GLM / Z.ai · Coding Plan") {
                Toggle("启用", isOn: $store.config.glm.enabled)
                SecureField("API Key(bigmodel.cn 控制台)", text: $store.config.glm.apiKey)
                HStack {
                    TextField("接口基址", text: $store.config.glm.quotaBase)
                }
                Toggle("团队版套餐(?type=2)", isOn: $store.config.glm.teamContext)
                Toggle("查询 MCP 额度", isOn: $store.config.glm.mcpEnabled)
                Divider()
                Toggle("无 Key 时本地估算(ZCode 用量库)", isOn: $store.config.glm.useLocalFallback)
                Stepper("本地估算 5 小时上限:\(store.config.glm.assumed5hPromptLimit) prompts",
                        value: $store.config.glm.assumed5hPromptLimit, in: 20...500, step: 10)
                Stepper("本地估算周上限:\(store.config.glm.assumedWeeklyPromptLimit) prompts",
                        value: $store.config.glm.assumedWeeklyPromptLimit, in: 50...5000, step: 50)
            }
        case "minimax":
            Section("MiniMax · Token Plan 直连") {
                Toggle("启用", isOn: $store.config.minimax.enabled)
                SecureField("API Key(platform.minimaxi.com)", text: $store.config.minimax.apiKey)
                Text("查询 api.minimaxi.com/v1/token_plan/remains。Claude Code 走 MiniMax 时已自动复用其 token;若查询报错,请改填平台控制台的 Key。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case "deepseek":
            Section("DeepSeek · 开放平台余额") {
                Toggle("启用", isOn: $store.config.deepseek.enabled)
                SecureField("API Key(sk-...,platform.deepseek.com)", text: $store.config.deepseek.apiKey)
            }
        case "relays":
            Section("中转站(new-api / one-api 兼容)") {
                ForEach($store.config.relays, id: \.rid) { $relay in
                    GroupBox {
                        VStack(spacing: 8) {
                            HStack {
                                TextField("名称", text: $relay.name)
                                Toggle("启用", isOn: $relay.enabled)
                                Button {
                                    store.config.relays.removeAll { $0.rid == relay.rid }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            TextField("站点地址(如 https://api.example.com)", text: $relay.baseUrl)
                            SecureField("API Key(sk-...)", text: $relay.apiKey)
                        }
                    }
                }
                Button("添加中转站") {
                    store.config.relays.append(RelayConfig(name: "新中转站"))
                }
            }
        case "kimi":
            Section("Kimi · Coding Plan") {
                Toggle("启用", isOn: $store.config.kimi.enabled)
                SecureField("API Key(sk-kimi-...,Kimi Code 控制台)", text: $store.config.kimi.apiKey)
            }
        case "grok":
            Section("Grok · xAI") {
                Toggle("启用", isOn: $store.config.grok.enabled)
                SecureField("API Key(console.x.ai)", text: $store.config.grok.apiKey)
            }
        case "codex":
            Section("Codex · ChatGPT 订阅") {
                Toggle("启用", isOn: $store.config.codex.enabled)
                SecureField("访问令牌(留空则读本机 ~/.codex)", text: $store.config.codex.apiKey)
                Text("本机 ~/.codex 为 API Key/中转模式时无订阅额度可查。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - 统计

struct StatsView: View {
    @ObservedObject var store: Store

    var body: some View {
        Table(store.history.reversed()) {
            TableColumn("时间") { r in
                Text(r.time.formatted(date: .abbreviated, time: .standard))
            }
            TableColumn("成功") { r in Text("\(r.okCount)").foregroundStyle(.green) }
            TableColumn("失败") { r in Text("\(r.failCount)").foregroundStyle(r.failCount > 0 ? .orange : .secondary) }
            TableColumn("耗时") { r in
                Text(r.outcomes.map(\.durationMs).max().map { "\($0) ms" } ?? "-")
            }
            TableColumn("失败详情") { r in
                Text(r.outcomes.filter { !$0.ok }
                    .map { "\($0.providerId): \($0.error ?? "?")" }
                    .joined(separator: "; "))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 诊断

/// 原始响应美化:把每行内嵌的 JSON 解析后缩进展开,长文本随窗口宽度自动换行
enum DiagFormat {
    static func beautify(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let brace = line.firstIndex(of: "{") else { return String(line) }
            let prefix = String(line[..<brace])
            let jsonText = String(line[brace...])
            guard let data = jsonText.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            else { return String(line) }
            return prefix + "\n" + String(decoding: pretty, as: UTF8.self)
        }.joined(separator: "\n")
    }
}

struct DiagnosticsView: View {
    @ObservedObject var store: Store
    @State private var selectedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("接入", selection: $selectedId) {
                ForEach(store.statuses) { s in
                    Text(s.name).tag(Optional(s.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 360, alignment: .leading)
            .padding(12)

            if let status = store.statuses.first(where: { $0.id == selectedId }) {
                HStack(spacing: 12) {
                    if let err = status.errorMessage {
                        Text("⚠ " + err)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(status.lastUpdated.map { "更新于 \($0.formatted(date: .omitted, time: .standard))" } ?? "")
                        .foregroundStyle(.secondary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(status.rawResponse ?? "", forType: .string)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // 仅纵向滚动:文本随窗口宽度自动换行,不再横向拖动
                ScrollView(.vertical) {
                    Text(DiagFormat.beautify(status.rawResponse ?? "(无原始响应)"))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                }
            } else {
                Text("选择一个接入查看原始响应")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if selectedId == nil { selectedId = store.statuses.first?.id }
        }
    }
}
