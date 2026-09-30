import Foundation
import SherpaMutationApplication
import SQLite3

public struct NativeMutationRecord: Codable, Sendable, Equatable {
    public let operationID: String
    public let capability: String
    public let status: NativeMutationStatus
    public let stableErrorCode: String?
    public let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id", capability, status
        case stableErrorCode = "stable_error_code"
        case createdAt = "created_at"
    }
}

public final class NativeMutationStore: MutationJournal, @unchecked Sendable {
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
        CREATE TABLE IF NOT EXISTS native_mutations (
          operation_id TEXT PRIMARY KEY,
          capability TEXT NOT NULL,
          status TEXT NOT NULL,
          stable_error_code TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        ) STRICT
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    deinit { sqlite3_close(database) }

    public static func openDefault() throws -> NativeMutationStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return try NativeMutationStore(url: base.appendingPathComponent("Sherpa/native.sqlite3"))
    }

    public func start(capability: String) throws -> String {
        let operationID = "op-\(UUID().uuidString.lowercased())"
        try start(operationID: operationID, capability: capability)
        return operationID
    }

    public func start(operationID: String, capability: String) throws {
        guard !operationID.isEmpty, operationID.utf8.count <= 128,
              capability.utf8.count <= 128 else { throw NativeCommandError.invalidRequest }
        let now = Int64(Date().timeIntervalSince1970)
        try statement(
            "INSERT INTO native_mutations(operation_id, capability, status, created_at, updated_at) VALUES(?, ?, 'started', ?, ?)",
            text: [operationID, capability], integers: [now, now]
        )
    }

    public func finish(
        operationID: String,
        status: NativeMutationStatus,
        stableErrorCode: String? = nil
    ) throws {
        guard status != .started else { throw NativeCommandError.invalidRequest }
        let now = Int64(Date().timeIntervalSince1970)
        lock.lock()
        defer { lock.unlock() }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database,
            "UPDATE native_mutations SET status=?, stable_error_code=?, updated_at=? WHERE operation_id=? AND status='started'",
            -1, &prepared, nil) == SQLITE_OK, let prepared else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(prepared) }
        bind(status.rawValue, at: 1, to: prepared)
        if let stableErrorCode { bind(stableErrorCode, at: 2, to: prepared) }
        else { sqlite3_bind_null(prepared, 2) }
        sqlite3_bind_int64(prepared, 3, now)
        bind(operationID, at: 4, to: prepared)
        guard sqlite3_step(prepared) == SQLITE_DONE, sqlite3_changes(database) == 1 else {
            throw NativeCommandError.failed
        }
    }

    public func recent(limit: Int = 100) throws -> [NativeMutationRecord] {
        guard (1 ... 1_000).contains(limit) else { throw NativeCommandError.invalidRequest }
        lock.lock()
        defer { lock.unlock() }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database,
            "SELECT operation_id, capability, status, stable_error_code, created_at FROM native_mutations ORDER BY created_at DESC, operation_id DESC LIMIT ?",
            -1, &prepared, nil) == SQLITE_OK, let prepared else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(prepared) }
        sqlite3_bind_int(prepared, 1, Int32(limit))
        var records: [NativeMutationRecord] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            guard let operation = sqlite3_column_text(prepared, 0),
                  let capability = sqlite3_column_text(prepared, 1),
                  let statusText = sqlite3_column_text(prepared, 2),
                  let status = NativeMutationStatus(rawValue: String(cString: statusText))
            else { throw NativeCommandError.failed }
            let error = sqlite3_column_text(prepared, 3).map { String(cString: $0) }
            records.append(.init(
                operationID: String(cString: operation), capability: String(cString: capability),
                status: status, stableErrorCode: error, createdAt: sqlite3_column_int64(prepared, 4)
            ))
        }
        return records
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NativeCommandError.failed
        }
    }

    private func statement(_ sql: String, text: [String], integers: [Int64]) throws {
        lock.lock()
        defer { lock.unlock() }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK,
              let prepared else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(prepared) }
        var index: Int32 = 1
        for value in text { bind(value, at: index, to: prepared); index += 1 }
        for value in integers { sqlite3_bind_int64(prepared, index, value); index += 1 }
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw NativeCommandError.failed }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
}
