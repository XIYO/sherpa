import Foundation

public struct IMessageAdapter: Sendable {
    private let executable: URL
    private let runner: NativeCommandRunner

    public init(executable: URL, runner: NativeCommandRunner = .init()) {
        self.executable = executable
        self.runner = runner
    }

    public func chats(limit: Int) throws -> Data {
        guard (1 ... 1_000).contains(limit) else { throw NativeCommandError.invalidRequest }
        return try runner.run(executable: executable, arguments: [
            "chats", "--limit", String(limit), "--json", "--log-level", "error",
        ]).stdout
    }

    public func history(chatID: UInt64, start: String, end: String, limit: Int) throws -> Data {
        guard (1 ... 10_000).contains(limit), validTimestamp(start), validTimestamp(end)
        else { throw NativeCommandError.invalidRequest }
        return try runner.run(executable: executable, arguments: [
            "history", "--chat-id", String(chatID), "--start", start, "--end", end,
            "--limit", String(limit), "--attachments", "--json", "--log-level", "error",
        ]).stdout
    }

    public func send(chatID: UInt64, text: Data) throws -> Data {
        guard let text = boundedText(text) else { throw NativeCommandError.invalidRequest }
        let group = try runner.run(executable: executable, arguments: [
            "group", "--chat-id", String(chatID), "--json", "--log-level", "error",
        ]).stdout
        try requireExactScalar(group, expected: String(chatID))
        return try runner.run(executable: executable, arguments: [
            "send", "--chat-id", String(chatID), "--text", text, "--service", "auto",
            "--json", "--log-level", "error",
        ], stdin: Data([0x01]), effect: .mutation).stdout
    }
}

private struct NativeChatRow: Decodable {
    let id: String?

    enum CodingKeys: String, CodingKey {
        case id, chatID = "chat_id"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeStringOrIntegerIfPresent(forKeys: [.id, .chatID])
    }
}

private extension KeyedDecodingContainer where Key == NativeChatRow.CodingKeys {
    func decodeStringOrIntegerIfPresent(forKeys keys: [Key]) throws -> String? {
        for key in keys {
            if let string = try? decodeIfPresent(String.self, forKey: key) { return string }
            if let integer = try? decodeIfPresent(Int64.self, forKey: key) {
                return String(integer)
            }
        }
        return nil
    }
}

private func decodedRows(_ data: Data) throws -> [NativeChatRow] {
    let decoder = JSONDecoder()
    if let rows = try? decoder.decode([NativeChatRow].self, from: data) { return rows }
    if let row = try? decoder.decode(NativeChatRow.self, from: data) { return [row] }
    let text = String(decoding: data, as: UTF8.self)
    return try text.split(whereSeparator: \.isNewline).map {
        try decoder.decode(NativeChatRow.self, from: Data($0.utf8))
    }
}

private func requireExactScalar(_ data: Data, expected: String) throws {
    guard try decodedRows(data).filter({ $0.id == expected }).count == 1 else {
        throw NativeCommandError.failed
    }
}

private func validTimestamp(_ value: String) -> Bool {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if formatter.date(from: value) != nil { return true }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value) != nil
}

private func boundedText(_ data: Data) -> String? {
    guard !data.isEmpty, data.count <= 64 * 1_024, let text = String(data: data, encoding: .utf8),
          !text.contains("\0") else { return nil }
    return text
}
