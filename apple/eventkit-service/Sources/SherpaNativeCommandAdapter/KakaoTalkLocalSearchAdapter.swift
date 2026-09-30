import Foundation

public struct KakaoTalkLocalSearchAdapter: Sendable {
    private static let localHistoryWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
    private let executable: URL
    private let runner: NativeCommandRunner
    private let checkpointStore: KakaoTalkLocalCheckpointStore?

    public init(
        executable: URL,
        runner: NativeCommandRunner = .init(),
        checkpointStore: KakaoTalkLocalCheckpointStore? = nil
    ) {
        self.executable = executable
        self.runner = runner
        self.checkpointStore = checkpointStore
    }

    public func search(query: Data, limit: Int) throws -> Data {
        guard (1...100).contains(limit),
            query.count <= 4_096,
            let decodedQuery = String(data: query, encoding: .utf8)
        else { throw NativeCommandError.invalidRequest }
        let normalizedQuery = decodedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
            normalizedQuery.count <= 256,
            !normalizedQuery.contains("\0"),
            !normalizedQuery.contains(where: \.isNewline)
        else { throw NativeCommandError.invalidRequest }

        localSearchLog("info", action: "start", fields: "limit=\(limit)")
        do {
            let argumentLauncher = URL(fileURLWithPath: "/usr/bin/xargs")
            guard FileManager.default.isExecutableFile(atPath: argumentLauncher.path) else {
                throw NativeCommandError.executableUnavailable
            }
            var queryInput = Data(normalizedQuery.precomposedStringWithCanonicalMapping.utf8)
            queryInput.append(0)
            let searchOutput = try runner.run(
                executable: argumentLauncher,
                arguments: [
                    "-0", executable.path, "search", "--limit", String(limit), "--json", "--",
                ],
                stdin: queryInput,
                timeoutSeconds: 30,
                outputLimit: 4 * 1_024 * 1_024,
                effect: .read
            ).stdout
            let nativeRows: [KakaoCLISearchRow]
            do {
                nativeRows = try JSONDecoder().decode([KakaoCLISearchRow].self, from: searchOutput)
            } catch {
                throw NativeCommandError.failed
            }
            guard nativeRows.count <= limit else { throw NativeCommandError.failed }

            var chatNames: [String: String] = [:]
            if !nativeRows.isEmpty {
                let chatsOutput = try runner.run(
                    executable: executable,
                    arguments: ["chats", "--limit", "1000", "--json"],
                    timeoutSeconds: 30,
                    outputLimit: 4 * 1_024 * 1_024
                ).stdout
                let chats: [KakaoCLIChatRow]
                do {
                    chats = try JSONDecoder().decode([KakaoCLIChatRow].self, from: chatsOutput)
                } catch {
                    throw NativeCommandError.failed
                }
                for chat in chats {
                    guard let id = chat.id?.value,
                        let displayName = boundedOptional(chat.displayName),
                        chatNames[id] == nil
                    else { continue }
                    chatNames[id] = displayName
                }
            }

            var seen: Set<String> = []
            var rows: [KakaoTalkLocalSearchResult] = []
            var omittedUnsupportedCount = 0
            for nativeRow in nativeRows {
                guard let id = nativeRow.id?.value,
                    let chatID = nativeRow.chatID?.value,
                    let timestamp = boundedRequired(nativeRow.timestamp, maximumBytes: 128),
                    validISO8601(timestamp),
                    let messageType = boundedRequired(nativeRow.type, maximumBytes: 128)
                else { throw NativeCommandError.failed }
                guard supportedLocalMessageType(messageType) else {
                    omittedUnsupportedCount += 1
                    continue
                }
                guard let text = boundedRequired(nativeRow.text, maximumBytes: 256 * 1_024)
                else { throw NativeCommandError.failed }
                let deduplicationKey = "\(chatID):\(id)"
                guard seen.insert(deduplicationKey).inserted else { continue }
                rows.append(
                    KakaoTalkLocalSearchResult(
                        reference: String(format: "KLS%03d", rows.count + 1),
                        timestamp: timestamp,
                        chat: chatNames[chatID],
                        sender: boundedOptional(nativeRow.sender),
                        text: text,
                        messageType: messageType,
                        isFromMe: nativeRow.isFromMe
                    ))
            }

            let envelope = KakaoTalkLocalSearchEnvelope(
                coverage: .init(limitReached: nativeRows.count >= limit),
                returnedCount: rows.count,
                omittedUnsupportedCount: omittedUnsupportedCount,
                limit: limit,
                results: rows
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(envelope)
            guard encoded.count <= 4 * 1_024 * 1_024 else {
                throw NativeCommandError.outputTooLarge
            }
            localSearchLog("info", action: "success", fields: "returned_count=\(rows.count)")
            return encoded
        } catch {
            localSearchLog("error", action: "failure", fields: "error=\(safeErrorName(error))")
            throw error
        }
    }

    public func history(chatName: Data, limit: Int, now: Date = Date()) throws -> Data {
        guard (1...1_000).contains(limit),
            chatName.count <= 4_096,
            let decodedChatName = String(data: chatName, encoding: .utf8)
        else { throw NativeCommandError.invalidRequest }
        let normalizedChatName = decodedChatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChatName.isEmpty,
            normalizedChatName.count <= 256,
            !normalizedChatName.contains("\0"),
            !normalizedChatName.contains(where: \.isNewline)
        else { throw NativeCommandError.invalidRequest }

        localSearchLog("info", action: "history-start", fields: "limit=\(limit) window_days=7")
        do {
            let chatsOutput = try runner.run(
                executable: executable,
                arguments: ["chats", "--limit", "1000", "--json"],
                timeoutSeconds: 30,
                outputLimit: 4 * 1_024 * 1_024
            ).stdout
            let chats: [KakaoCLIChatRow]
            do {
                chats = try JSONDecoder().decode([KakaoCLIChatRow].self, from: chatsOutput)
            } catch {
                throw NativeCommandError.failed
            }
            let exactMatches = chats.compactMap { chat -> (id: String, name: String)? in
                guard let id = chat.id?.value,
                    let name = boundedOptional(chat.displayName),
                    name.precomposedStringWithCanonicalMapping
                        == normalizedChatName.precomposedStringWithCanonicalMapping
                else { return nil }
                return (id, name)
            }
            guard exactMatches.count == 1, let selectedChat = exactMatches.first else {
                throw NativeCommandError.failed
            }

            let argumentLauncher = URL(fileURLWithPath: "/usr/bin/xargs")
            guard FileManager.default.isExecutableFile(atPath: argumentLauncher.path) else {
                throw NativeCommandError.executableUnavailable
            }
            var chatInput = Data(selectedChat.name.utf8)
            chatInput.append(0)
            let messagesOutput = try runner.run(
                executable: argumentLauncher,
                arguments: [
                    "-0", executable.path, "messages", "--since", "7d", "--limit", String(limit),
                    "--json", "--chat",
                ],
                stdin: chatInput,
                timeoutSeconds: 30,
                outputLimit: 8 * 1_024 * 1_024,
                effect: .read
            ).stdout
            let nativeRows: [KakaoCLIMessageRow]
            do {
                nativeRows = try JSONDecoder().decode([KakaoCLIMessageRow].self, from: messagesOutput)
            } catch {
                throw NativeCommandError.failed
            }
            guard nativeRows.count <= limit else { throw NativeCommandError.failed }

            let windowStart = now.addingTimeInterval(-Self.localHistoryWindowSeconds)
            var seen: Set<String> = []
            var rows: [KakaoTalkLocalSearchResult] = []
            var omittedUnsupportedCount = 0
            for nativeRow in nativeRows {
                guard let id = nativeRow.id?.value,
                    let chatID = nativeRow.chatID?.value,
                    chatID == selectedChat.id,
                    let timestamp = boundedRequired(nativeRow.timestamp, maximumBytes: 128),
                    let messageDate = iso8601Date(timestamp),
                    messageDate >= windowStart,
                    let messageType = boundedRequired(nativeRow.type, maximumBytes: 128)
                else { throw NativeCommandError.failed }
                guard supportedLocalMessageType(messageType) else {
                    omittedUnsupportedCount += 1
                    continue
                }
                guard let text = boundedRequired(nativeRow.text, maximumBytes: 256 * 1_024)
                else { throw NativeCommandError.failed }
                let deduplicationKey = "\(chatID):\(id)"
                guard seen.insert(deduplicationKey).inserted else { continue }
                rows.append(
                    KakaoTalkLocalSearchResult(
                        reference: "",
                        timestamp: timestamp,
                        chat: selectedChat.name,
                        sender: boundedOptional(nativeRow.sender),
                        text: text,
                        messageType: messageType,
                        isFromMe: nativeRow.isFromMe
                    ))
            }
            rows.sort { $0.timestamp < $1.timestamp }
            rows = rows.enumerated().map { index, row in
                KakaoTalkLocalSearchResult(
                    reference: String(format: "KLH%03d", index + 1),
                    timestamp: row.timestamp,
                    chat: row.chat,
                    sender: row.sender,
                    text: row.text,
                    messageType: row.messageType,
                    isFromMe: row.isFromMe
                )
            }

            let envelope = KakaoTalkLocalHistoryEnvelope(
                baseline: .init(windowStart: iso8601String(windowStart), windowEnd: iso8601String(now)),
                coverage: .init(limitReached: nativeRows.count >= limit),
                returnedCount: rows.count,
                omittedUnsupportedCount: omittedUnsupportedCount,
                limit: limit,
                results: rows
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(envelope)
            guard encoded.count <= 8 * 1_024 * 1_024 else {
                throw NativeCommandError.outputTooLarge
            }
            localSearchLog("info", action: "history-success", fields: "returned_count=\(rows.count)")
            return encoded
        } catch {
            localSearchLog("error", action: "history-failure", fields: "error=\(safeErrorName(error))")
            throw error
        }
    }

    public func archive(
        since: String,
        timeZoneIdentifier: String,
        limit: Int,
        now: Date = Date()
    ) throws -> Data {
        guard (1...50_000).contains(limit),
            let timeZone = TimeZone(identifier: timeZoneIdentifier)
        else { throw NativeCommandError.invalidRequest }
        let store = try checkpointStore ?? KakaoTalkLocalCheckpointStore.openDefault()
        let windowStart: Date
        let rangeKind: String
        let checkpointAvailable: Bool
        if since == "checkpoint" {
            guard let current = try store.current(),
                let highWater = iso8601Date(current.highWater)
            else { throw NativeCommandError.invalidRequest }
            windowStart = highWater.addingTimeInterval(-24 * 60 * 60)
            rangeKind = "local_checkpoint_with_overlap"
            checkpointAvailable = true
        } else {
            guard let explicitStart = localDateStart(since, timeZone: timeZone) else {
                throw NativeCommandError.invalidRequest
            }
            windowStart = explicitStart
            rangeKind = "explicit_local_date_range"
            checkpointAvailable = false
        }
        guard windowStart <= now else { throw NativeCommandError.invalidRequest }

        let elapsedDays = Int(ceil(now.timeIntervalSince(windowStart) / (24 * 60 * 60))) + 1
        guard (1...3_650).contains(elapsedDays) else { throw NativeCommandError.invalidRequest }

        localSearchLog(
            "info", action: "archive-start",
            fields: "limit=\(limit) window_days=\(elapsedDays)"
        )
        do {
            let messagesOutput = try runner.run(
                executable: executable,
                arguments: [
                    "messages", "--since", "\(elapsedDays)d", "--limit", String(limit), "--json",
                ],
                timeoutSeconds: 60,
                outputLimit: 64 * 1_024 * 1_024
            ).stdout
            let nativeRows: [KakaoCLIMessageRow]
            do {
                nativeRows = try JSONDecoder().decode([KakaoCLIMessageRow].self, from: messagesOutput)
            } catch {
                throw NativeCommandError.failed
            }
            guard nativeRows.count <= limit else { throw NativeCommandError.failed }

            let chatsOutput = try runner.run(
                executable: executable,
                arguments: ["chats", "--limit", "1000", "--json"],
                timeoutSeconds: 30,
                outputLimit: 4 * 1_024 * 1_024
            ).stdout
            let chats: [KakaoCLIChatRow]
            do {
                chats = try JSONDecoder().decode([KakaoCLIChatRow].self, from: chatsOutput)
            } catch {
                throw NativeCommandError.failed
            }
            var chatNames: [String: String] = [:]
            for chat in chats {
                guard let id = chat.id?.value,
                    let displayName = boundedOptional(chat.displayName),
                    chatNames[id] == nil
                else { continue }
                chatNames[id] = displayName
            }

            var seen: Set<String> = []
            var returnedChats: Set<String> = []
            var rows: [KakaoTalkLocalSearchResult] = []
            var omittedUnsupportedCount = 0
            for nativeRow in nativeRows {
                guard let id = nativeRow.id?.value,
                    let chatID = nativeRow.chatID?.value,
                    let timestamp = boundedRequired(nativeRow.timestamp, maximumBytes: 128),
                    let messageDate = iso8601Date(timestamp),
                    let messageType = boundedRequired(nativeRow.type, maximumBytes: 128)
                else { throw NativeCommandError.failed }
                guard messageDate >= windowStart, messageDate <= now else { continue }
                guard supportedLocalMessageType(messageType) else {
                    omittedUnsupportedCount += 1
                    continue
                }
                guard let text = boundedRequired(nativeRow.text, maximumBytes: 256 * 1_024)
                else { throw NativeCommandError.failed }
                let deduplicationKey = "\(chatID):\(id)"
                guard seen.insert(deduplicationKey).inserted else { continue }
                returnedChats.insert(chatID)
                rows.append(
                    KakaoTalkLocalSearchResult(
                        reference: "",
                        timestamp: timestamp,
                        chat: chatNames[chatID],
                        sender: boundedOptional(nativeRow.sender),
                        text: text,
                        messageType: messageType,
                        isFromMe: nativeRow.isFromMe
                    )
                )
            }
            rows.sort { $0.timestamp < $1.timestamp }
            rows = rows.enumerated().map { index, row in
                KakaoTalkLocalSearchResult(
                    reference: String(format: "KLA%05d", index + 1),
                    timestamp: row.timestamp,
                    chat: row.chat,
                    sender: row.sender,
                    text: row.text,
                    messageType: row.messageType,
                    isFromMe: row.isFromMe
                )
            }

            let limitReached = nativeRows.count >= limit
            let checkpoint: KakaoTalkLocalCheckpointCandidate?
            if limitReached {
                checkpoint = nil
            } else {
                checkpoint = try store.stage(highWater: now)
            }
            let envelope = KakaoTalkLocalArchiveEnvelope(
                range: .init(
                    kind: rangeKind,
                    checkpointAvailable: checkpointAvailable,
                    requestedStart: since,
                    windowStart: iso8601String(windowStart),
                    windowEnd: iso8601String(now),
                    timeZone: timeZoneIdentifier
                ),
                coverage: .init(limitReached: limitReached),
                returnedCount: rows.count,
                returnedChatCount: returnedChats.count,
                omittedUnsupportedCount: omittedUnsupportedCount,
                limit: limit,
                checkpoint: checkpoint,
                results: rows
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(envelope)
            guard encoded.count <= 64 * 1_024 * 1_024 else {
                throw NativeCommandError.outputTooLarge
            }
            localSearchLog(
                "info", action: "archive-success",
                fields: "returned_count=\(rows.count) chat_count=\(returnedChats.count)"
            )
            return encoded
        } catch {
            localSearchLog("error", action: "archive-failure", fields: "error=\(safeErrorName(error))")
            throw error
        }
    }

    public func commitCheckpoint(token: Data) throws -> Data {
        guard token.count <= 256,
            let decoded = String(data: token, encoding: .utf8)
        else { throw NativeCommandError.invalidRequest }
        let normalized = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("KLCP"), normalized.utf8.count <= 128,
            !normalized.contains("\0"), !normalized.contains(where: \.isNewline)
        else { throw NativeCommandError.invalidRequest }

        localSearchLog("info", action: "checkpoint-start", fields: "source=local_database")
        do {
            let store = try checkpointStore ?? KakaoTalkLocalCheckpointStore.openDefault()
            let checkpoint = try store.commit(token: normalized)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(checkpoint)
            localSearchLog("info", action: "checkpoint-success", fields: "state=committed")
            return encoded
        } catch {
            localSearchLog("error", action: "checkpoint-failure", fields: "error=\(safeErrorName(error))")
            throw error
        }
    }
}

public struct KakaoTalkLocalArchiveEnvelope: Encodable, Sendable, Equatable {
    public let schema = "sherpa.kakaotalk-local-archive.v1"
    public let source = "mac_local_synchronized_database"
    public let range: KakaoTalkLocalArchiveRange
    public let coverage: KakaoTalkLocalSearchCoverage
    public let returnedCount: Int
    public let returnedChatCount: Int
    public let omittedUnsupportedCount: Int
    public let limit: Int
    public let checkpoint: KakaoTalkLocalCheckpointCandidate?
    public let results: [KakaoTalkLocalSearchResult]

    enum CodingKeys: String, CodingKey {
        case schema, source, range, coverage, limit, checkpoint, results
        case returnedCount = "returned_count"
        case returnedChatCount = "returned_chat_count"
        case omittedUnsupportedCount = "omitted_unsupported_count"
    }
}

public struct KakaoTalkLocalArchiveRange: Encodable, Sendable, Equatable {
    public let kind: String
    public let checkpointAvailable: Bool
    public let earlierHistoryRead = false
    public let requestedStart: String
    public let windowStart: String
    public let windowEnd: String
    public let timeZone: String

    public init(
        kind: String,
        checkpointAvailable: Bool,
        requestedStart: String,
        windowStart: String,
        windowEnd: String,
        timeZone: String
    ) {
        self.kind = kind
        self.checkpointAvailable = checkpointAvailable
        self.requestedStart = requestedStart
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.timeZone = timeZone
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case checkpointAvailable = "checkpoint_available"
        case earlierHistoryRead = "earlier_history_read"
        case requestedStart = "requested_start"
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case timeZone = "time_zone"
    }
}

public struct KakaoTalkLocalHistoryEnvelope: Encodable, Sendable, Equatable {
    public let schema = "sherpa.kakaotalk-local-history.v1"
    public let source = "mac_local_synchronized_database"
    public let baseline: KakaoTalkLocalHistoryBaseline
    public let coverage: KakaoTalkLocalSearchCoverage
    public let returnedCount: Int
    public let omittedUnsupportedCount: Int
    public let limit: Int
    public let results: [KakaoTalkLocalSearchResult]

    enum CodingKeys: String, CodingKey {
        case schema, source, baseline, coverage, limit, results
        case returnedCount = "returned_count"
        case omittedUnsupportedCount = "omitted_unsupported_count"
    }
}

public struct KakaoTalkLocalHistoryBaseline: Encodable, Sendable, Equatable {
    public let kind = "checkpoint_missing_local_seven_day_window"
    public let checkpointAvailable = false
    public let earlierHistoryRead = false
    public let windowStart: String
    public let windowEnd: String

    public init(windowStart: String, windowEnd: String) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case checkpointAvailable = "checkpoint_available"
        case earlierHistoryRead = "earlier_history_read"
        case windowStart = "window_start"
        case windowEnd = "window_end"
    }
}

public struct KakaoTalkLocalSearchEnvelope: Encodable, Sendable, Equatable {
    public let schema = "sherpa.kakaotalk-local-search.v1"
    public let source = "mac_local_synchronized_database"
    public let coverage: KakaoTalkLocalSearchCoverage
    public let returnedCount: Int
    public let omittedUnsupportedCount: Int
    public let limit: Int
    public let results: [KakaoTalkLocalSearchResult]

    enum CodingKeys: String, CodingKey {
        case schema, source, coverage, limit, results
        case returnedCount = "returned_count"
        case omittedUnsupportedCount = "omitted_unsupported_count"
    }
}

public struct KakaoTalkLocalSearchCoverage: Encodable, Sendable, Equatable {
    public let completeness = "partial"
    public let reason = "local_database_may_be_incomplete"
    public let limitReached: Bool

    public init(limitReached: Bool) {
        self.limitReached = limitReached
    }

    enum CodingKeys: String, CodingKey {
        case completeness, reason
        case limitReached = "limit_reached"
    }
}

public struct KakaoTalkLocalSearchResult: Encodable, Sendable, Equatable {
    public let reference: String
    public let timestamp: String
    public let chat: String?
    public let sender: String?
    public let text: String
    public let messageType: String
    public let isFromMe: Bool

    enum CodingKeys: String, CodingKey {
        case reference, timestamp, chat, sender, text
        case messageType = "message_type"
        case isFromMe = "is_from_me"
    }
}

private struct KakaoCLIMessageRow: Decodable {
    let id: FlexibleIdentifier?
    let chatID: FlexibleIdentifier?
    let timestamp: String?
    let sender: String?
    let text: String?
    let type: String?
    let isFromMe: Bool

    enum CodingKeys: String, CodingKey {
        case id, timestamp, sender, text, type
        case chatID = "chat_id"
        case isFromMe = "is_from_me"
    }
}

private typealias KakaoCLISearchRow = KakaoCLIMessageRow

private struct KakaoCLIChatRow: Decodable {
    let id: FlexibleIdentifier?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct FlexibleIdentifier: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int64.self) {
            self.value = String(value)
        } else if let value = try? container.decode(UInt64.self) {
            self.value = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected identifier")
            )
        }
    }
}

private func boundedRequired(_ value: String?, maximumBytes: Int) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= maximumBytes, !value.contains("\0")
    else { return nil }
    return value
}

private func boundedOptional(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= 4_096, !value.contains("\0")
    else { return nil }
    return value
}

private func iso8601Date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func validISO8601(_ value: String) -> Bool {
    iso8601Date(value) != nil
}

private func supportedLocalMessageType(_ value: String) -> Bool {
    ["text", "photo", "video", "voice"].contains(value)
}

private func iso8601String(_ value: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: value)
}

private func localDateStart(_ value: String, timeZone: TimeZone) -> Date? {
    guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
        return nil
    }
    return date
}

private func localSearchLog(_ level: String, action: String, fields: String) {
    let line = "\(level) [adapter:kakaotalk-local-search:\(action)] \(fields)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

private func safeErrorName(_ error: Error) -> String {
    guard let error = error as? NativeCommandError else { return "unexpected" }
    return switch error {
    case .executableUnavailable: "executable_unavailable"
    case .invalidRequest: "invalid_request"
    case .outputTooLarge: "output_too_large"
    case .failed: "failed"
    case .timedOut: "timed_out"
    case .uncertain: "uncertain"
    case .rejected: "rejected"
    }
}
