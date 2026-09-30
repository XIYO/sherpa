import Foundation
import SQLite3

/// Read-only access to Mail.app's local envelope index.  AppleScript mailbox
/// enumeration can block indefinitely on a syncing account; the index is the
/// same local data Mail uses for its message list and covers every account.
struct MailIndexReader: Sendable {
    func list(from: String, to: String, limit: Int) throws -> MailListOutput {
        guard let start = parseMailIndexDate(from), let end = parseMailIndexDate(to), start < end,
              (1 ... 50_000).contains(limit) else { throw NativeCommandError.invalidRequest }
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail/V10/MailData/Envelope Index").path
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else { throw NativeCommandError.failed }
        defer { sqlite3_close(database) }
        let sql = """
        SELECT m.ROWID, COALESCE(s.subject, ''), COALESCE(a.address, ''),
               m.date_received, m.date_sent, COALESCE(x.summary, ''), COALESCE(b.url, '')
        FROM messages m
        LEFT JOIN subjects s ON s.ROWID = m.subject
        LEFT JOIN addresses a ON a.ROWID = m.sender
        LEFT JOIN summaries x ON x.ROWID = m.summary
        LEFT JOIN mailboxes b ON b.ROWID = m.mailbox
        WHERE m.deleted = 0 AND m.date_received >= ? AND m.date_received < ?
        ORDER BY m.date_received DESC, m.ROWID DESC LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement
        else { throw NativeCommandError.failed }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(start.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(end.timeIntervalSince1970))
        sqlite3_bind_int(statement, 3, Int32(limit))
        var messages: [MailItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let received = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3)))
            let sentValue = sqlite3_column_int64(statement, 4)
            messages.append(MailItem(
                sourceMessageID: "mail-index:\(rowID)", subject: sqliteText(statement, 1),
                sender: sqliteText(statement, 2), receivedAt: mailIndexDate(received),
                sentAt: sentValue == 0 ? nil : mailIndexDate(Date(timeIntervalSince1970: TimeInterval(sentValue))),
                body: sqliteText(statement, 5), bodyTruncated: true,
                mailbox: sqliteText(statement, 6), recipients: [], attachments: []
            ))
        }
        return MailListOutput(messages: messages)
    }

    func read(sourceMessageID: String, maximumBodyBytes: Int) throws -> MailReadOutput {
        guard sourceMessageID.hasPrefix("mail-index:"),
              let rowID = Int64(sourceMessageID.dropFirst("mail-index:".count)),
              rowID > 0, (1 ... 1_024 * 1_024).contains(maximumBodyBytes)
        else { throw NativeCommandError.invalidRequest }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail/V10")
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { throw NativeCommandError.failed }
        let expected = "\(rowID).emlx"
        for case let file as URL in enumerator where file.lastPathComponent == expected {
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            guard let newline = data.firstIndex(of: 0x0a),
                  let length = Int(String(decoding: data[..<newline], as: UTF8.self))
            else { throw NativeCommandError.failed }
            let start = data.index(after: newline)
            guard length >= 0, data.distance(from: start, to: data.endIndex) >= length else {
                throw NativeCommandError.failed
            }
            let message = String(decoding: data[start..<data.index(start, offsetBy: length)], as: UTF8.self)
            let separator = message.range(of: "\r\n\r\n") ?? message.range(of: "\n\n")
            let body = separator.map { String(message[$0.upperBound...]) } ?? ""
            let bounded = String(decoding: body.utf8.prefix(maximumBodyBytes), as: UTF8.self)
            return MailReadOutput(message: MailItem(
                sourceMessageID: sourceMessageID, subject: "", sender: "", receivedAt: "", sentAt: nil,
                body: bounded, bodyTruncated: body.utf8.count > bounded.utf8.count,
                mailbox: "", recipients: [], attachments: []
            ))
        }
        return MailReadOutput(message: nil)
    }
}

private func sqliteText(_ statement: OpaquePointer, _ column: Int32) -> String {
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
}

private func parseMailIndexDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func mailIndexDate(_ value: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: value)
}
