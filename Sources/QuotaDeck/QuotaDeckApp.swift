import SwiftUI
import QuotaDeckCore

@main
struct QuotaDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            Text(store.menuTitle)
        }
        .menuBarExtraStyle(.window)

        Window("QuotaDeck", id: "main") {
            MainSplitView(store: store)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("立即刷新") { Task { await store.refreshAll() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// MARK: - 菜单栏下拉面板

struct MenuBarPanel: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Coding Plan 余量")
                    .font(.headline)
                Spacer()
                if store.refreshing { ProgressView().controlSize(.small) }
                Text(store.lastRefresh.map { "更新于 \(TimeZone.current.abbreviation() != nil ? "" : "")\($0.formatted(date: .omitted, time: .shortened))" } ?? "未刷新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.statuses) { status in
                MenuBarRow(status: status)
            }

            Divider()
            HStack(spacing: 14) {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("管理窗口", systemImage: "macwindow")
                }
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .font(.callout)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            store.startAutoRefresh()
        }
    }
}

struct MenuBarRow: View {
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(status.name).font(.callout.weight(.medium))
                stateBadge
                Spacer()
                if status.windows.isEmpty {
                    Text(status.state.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(status.windows) { w in
                HStack(spacing: 6) {
                    Text(w.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)
                    BarShape(fraction: w.remainingFraction)
                    if let t = w.remainingText ?? TimeFormat.countdown(to: w.resetsAt) {
                        Text(t).font(.caption.monospacedDigit())
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(status.state == .disabled || status.state == .notConfigured ? 0.55 : 1)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch status.state {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}

// MARK: - 进度条

struct BarShape: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                if let f = fraction {
                    Capsule().fill(Self.color(f))
                        .frame(width: max(6, f * geo.size.width))
                } else {
                    Capsule().fill(Color.primary.opacity(0.18))
                        .frame(width: geo.size.width * 0.35)
                }
            }
        }
        .frame(height: 7)
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }

    static func color(_ f: Double) -> Color {
        if f < 0.2 { return .red }
        if f < 0.5 { return .orange }
        return .green
    }
}
