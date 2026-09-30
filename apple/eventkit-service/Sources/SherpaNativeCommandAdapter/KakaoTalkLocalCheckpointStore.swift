import Foundation
import SQLite3

public struct KakaoTalkLocalCheckpointCandidate: Codable, Sendable, Equatable {
    public let schema = "sherpa.kakaotalk-local-checkpoint.v1"
    public let state: String
    public let token: String?
    public let highWater: String

    public init(state: String, token: String?, highWater: String) {
        self.state = state
        self.token = token
        self.highWater = highWater
    }

    enum CodingKeys: String, CodingKey {
        case schema, state, token
        case highWater = "high_water"
    }
}

public final class KakaoTalkLocalCheckpointStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let lock = NSLock()

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var opened: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        ) == SQLITE_OK, let opened else { throw NativeCommandError.failed }
        database = opened
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("""
        CREATE TABLE IF NOT EXISTS kakaotalk_local_checkpoint (
          singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
          high_water TEXT NOT NULL,
          committed_at INTEGER NOT NULL
        ) STRICT
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS kakaotalk_local_checkpoint_pending (
          token TEXT PRIMARY KEY,
          high_water TEXT NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('pending', 'committed')),
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        ) STRICT
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    deinit { sqlite3_close(database) }

    public static func openDefault() throws -> KakaoTalkLocalCheckpointStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return try KakaoTalkLocalCheckpointStore(
            url: base.appendingPathComponent("Sherpa/context.sqlite3")
        )
    }

    public func stage(highWater: Date) throws -> KakaoTalkLocalCheckpointCandidate {
        let token = "KLCP\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let highWaterText = checkpointISO8601String(highWater)
        let now = Int64(Date().timeIntervalSince1970)
        lock.lock()
        defer { lock.unlock() }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO kakaotalk_local_checkpoint_pending(token, high_water, state, created_at, updated_at) VALUES(?, ?, 'pending', ?, ?)",
            -1, &prepared, nil
        ) == SQLITE_OK, let prepared else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(prepared) }
        bind(token, at: 1, to: prepared)
        bind(highWaterText, at: 2, to: prepared)
        sqlite3_bind_int64(prepared, 3, now)
        sqlite3_bind_int64(prepared, 4, now)
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw NativeCommandError.failed }
        return .init(state: "pending", token: token, highWater: highWaterText)
    }

    public func commit(token: String) throws -> KakaoTalkLocalCheckpointCandidate {
        guard token.hasPrefix("KLCP"), token.utf8.count <= 128 else {
            throw NativeCommandError.invalidRequest
        }
        lock.lock()
        defer { lock.unlock() }
        try executeUnlocked("BEGIN IMMEDIATE")
        do {
            let highWater = try pendingHighWater(token: token)
            let now = Int64(Date().timeIntervalSince1970)
            var checkpointStatement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                """
                INSERT INTO kakaotalk_local_checkpoint(singleton, high_water, committed_at)
                VALUES(1, ?, ?)
                ON CONFLICT(singleton) DO UPDATE SET
                  high_water = CASE WHEN excluded.high_water > high_water THEN excluded.high_water ELSE high_water END,
                  committed_at = excluded.committed_at
                """,
                -1, &checkpointStatement, nil
            ) == SQLITE_OK, let checkpointStatement else { throw NativeCommandError.failed }
            bind(highWater, at: 1, to: checkpointStatement)
            sqlite3_bind_int64(checkpointStatement, 2, now)
            guard sqlite3_step(checkpointStatement) == SQLITE_DONE else {
                sqlite3_finalize(checkpointStatement)
                throw NativeCommandError.failed
            }
            sqlite3_finalize(checkpointStatement)

            var pendingStatement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "UPDATE kakaotalk_local_checkpoint_pending SET state='committed', updated_at=? WHERE token=? AND state='pending'",
                -1, &pendingStatement, nil
            ) == SQLITE_OK, let pendingStatement else { throw NativeCommandError.failed }
            sqlite3_bind_int64(pendingStatement, 1, now)
            bind(token, at: 2, to: pendingStatement)
            guard sqlite3_step(pendingStatement) == SQLITE_DONE,
                sqlite3_changes(database) == 1
            else {
                sqlite3_finalize(pendingStatement)
                throw NativeCommandError.failed
            }
            sqlite3_finalize(pendingStatement)
            try executeUnlocked("COMMIT")
            return .init(state: "committed", token: nil, highWater: highWater)
        } catch {
            try? executeUnlocked("ROLLBACK")
            throw error
        }
    }

    public func current() throws -> KakaoTalkLocalCheckpointCandidate? {
        lock.lock()
        defer { lock.unlock() }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT high_water FROM kakaotalk_local_checkpoint WHERE singleton=1",
            -1, &prepared, nil
        ) == SQLITE_OK, let prepared else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(prepared) }
        guard sqlite3_step(prepared) == SQLITE_ROW else { return nil }
        guard let text = sqlite3_column_text(prepared, 0) else { throw NativeCommandError.failed }
        return .init(state: "committed", token: nil, highWater: String(cString: text))
    }

    private func pendingHighWater(token: String) throws -> String {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT high_water FROM kakaotalk_local_checkpoint_pending WHERE token=? AND state='pending'",
            -1, &prepared, nil
        ) == SQLITE_OK, let prepared else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(prepared) }
        bind(token, at: 1, to: prepared)
        guard sqlite3_step(prepared) == SQLITE_ROW,
            let text = sqlite3_column_text(prepared, 0)
        else { throw NativeCommandError.failed }
        return String(cString: text)
    }

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try executeUnlocked(sql)
    }

    private func executeUnlocked(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NativeCommandError.failed
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(
            statement, index, value, -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
    }
}

private func checkpointISO8601String(_ value: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: value)
}
