import Foundation
import SQLite3

// MARK: - ZCode 本地数据(只读)

/// 从 ~/.zcode 本地数据库推算的 5 小时窗口用量
public struct ZCodeLocalSnapshot {
    public var promptsInWindow: Int
    public var windowOpenedAt: Date?
    public var windowClosesAt: Date?
    public var promptsIn7d: Int
    public var promptsIn24h: Int
    public var tokensInWindow: Int
    public var planEntryAvailable: Bool?
    public var dbModifiedAt: Date?
}

public enum ZCodeLocal {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var dbURL: URL { home.appendingPathComponent(".zcode/cli/db/db.sqlite") }
    static var cacheURL: URL { home.appendingPathComponent(".zcode/v2/coding-plan-cache.json") }

    /// 读取本地用量(无则返回 nil)
    public static func snapshot() -> ZCodeLocalSnapshot? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dbURL.path) else { return nil }
        var snap = ZCodeLocalSnapshot(
            promptsInWindow: 0, windowOpenedAt: nil, windowClosesAt: nil,
            promptsIn7d: 0, promptsIn24h: 0, tokensInWindow: 0,
            planEntryAvailable: nil, dbModifiedAt: nil
        )
        snap.dbModifiedAt = try? fm.attributesOfItem(atPath: dbURL.path)[.modificationDate] as? Date
        snap.planEntryAvailable = codingPlanAvailable()

        var db: OpaquePointer?
        // 只读打开,避免干扰 ZCode 写入;WAL 库以同用户只读打开是安全的
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, db != nil else {
            sqlite3_close(db)
            return snap
        }
        defer { sqlite3_close(db) }

        let weekMs = 7 * 24 * 3600 * 1000
        let since = Int(Date().timeIntervalSince1970 * 1000) - weekMs
        // started_at 毫秒时间戳;只统计已开始且非异常的 turn
        let sql = """
        SELECT started_at, computed_total_tokens, status FROM turn_usage
        WHERE started_at >= ? ORDER BY started_at ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return snap }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(since))

        var times: [Double] = []
        var tokens: [Int] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let t = sqlite3_column_double(stmt, 0)
            times.append(t)
            tokens.append(Int(sqlite3_column_int64(stmt, 1)))
        }

        snap.promptsIn7d = times.count
        let dayAgo = Date().timeIntervalSince1970 * 1000 - 24 * 3600 * 1000
        snap.promptsIn24h = times.filter { $0 >= dayAgo }.count

        // 锚定窗口算法:窗口从窗口内第一条记录起算,跨度 5 小时;
        // 若有记录晚于窗口关闭时刻,则从那条记录重新开窗
        let fiveHourMs = 5.0 * 3600 * 1000
        if !times.isEmpty {
            var anchor = 0
            var window: (startIdx: Int, endIdx: Int, closesAt: Double)? = nil
            while anchor < times.count {
                let close = times[anchor] + fiveHourMs
                var last = anchor
                var i = anchor
                while i < times.count, times[i] < close { last = i; i += 1 }
                if i >= times.count {
                    window = (anchor, last, close)
                    break
                }
                anchor = i
            }
            if let w = window {
                snap.promptsInWindow = w.endIdx - w.startIdx + 1
                snap.windowOpenedAt = Date(timeIntervalSince1970: times[w.startIdx] / 1000)
                snap.windowClosesAt = Date(timeIntervalSince1970: w.closesAt / 1000)
                snap.tokensInWindow = tokens[w.startIdx...w.endIdx].reduce(0, +)
            }
        }
        return snap
    }

    /// coding-plan-cache.json 里是否有 available 的套餐入口
    static func codingPlanAvailable() -> Bool? {
        guard let data = try? Data(contentsOf: cacheURL),
              let obj = JSON.parse(data),
              let items = JSON.dict(JSON.dict(obj)?["entryStatus"])?["items"],
              let arr = JSON.array(items)
        else { return nil }
        return arr.contains { JSON.string($0, "status") == "available" }
    }

    /// 给 GLMProvider 用的预览信息(账号槽位,不含 key 内容)
    public static func hasCodingPlanApiKeySlot() -> Bool {
        let url = home.appendingPathComponent(".zcode/v2/credentials.json")
        guard let data = try? Data(contentsOf: url),
              let obj = JSON.parse(data) as? [String: Any] else { return false }
        return obj.keys.contains { $0.hasSuffix(":api-key") }
    }
}
