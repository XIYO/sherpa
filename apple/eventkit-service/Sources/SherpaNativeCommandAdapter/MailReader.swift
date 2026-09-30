import Foundation
import SherpaMailShim

public struct MailRecipient: Codable, Sendable, Equatable {
    public let role: String
    public let name: String?
    public let address: String
}

public struct MailAttachment: Codable, Sendable, Equatable {
    public let mimeType: String?
    public let byteCount: Int
    public let downloaded: Bool

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case byteCount = "byte_count"
        case downloaded
    }
}

public struct MailItem: Codable, Sendable, Equatable {
    public let sourceMessageID: String
    public let subject: String
    public let sender: String
    public let receivedAt: String
    public let sentAt: String?
    public let body: String
    public let bodyTruncated: Bool
    public let mailbox: String
    public let recipients: [MailRecipient]
    public let attachments: [MailAttachment]

    enum CodingKeys: String, CodingKey {
        case sourceMessageID = "source_message_id"
        case subject, sender
        case receivedAt = "received_at"
        case sentAt = "sent_at"
        case body
        case bodyTruncated = "body_truncated"
        case mailbox, recipients, attachments
    }
}

public struct MailListOutput: Codable, Sendable, Equatable {
    public let messages: [MailItem]
}

public struct MailReadOutput: Codable, Sendable, Equatable {
    public let message: MailItem?
}

public struct MailReader: Sendable {
    public typealias Handler = @Sendable (Data) -> Data
    private let handler: Handler?

    public init() {
        handler = nil
    }

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func list(
        from: String,
        to: String,
        limit: Int,
        maximumBodyBytes: Int
    ) throws -> MailListOutput {
        guard let start = parsedDate(from), let end = parsedDate(to), start < end,
              (1 ... 50_000).contains(limit),
              (0 ... 1_024 * 1_024).contains(maximumBodyBytes)
        else { throw NativeCommandError.invalidRequest }
        if handler == nil {
            return try MailIndexReader().list(from: from, to: to, limit: limit)
        }
        return try call(
            capability: "mail.messages.list",
            payload: MailListPayload(
                from: from, to: to, limit: limit, maximumBodyBytes: maximumBodyBytes
            ),
            result: MailListOutput.self
        )
    }

    public func read(sourceMessageID: String, maximumBodyBytes: Int) throws -> MailReadOutput {
        guard !sourceMessageID.isEmpty, sourceMessageID.utf8.count <= 4_096,
              !sourceMessageID.contains("\0"),
              (1 ... 1_024 * 1_024).contains(maximumBodyBytes)
        else { throw NativeCommandError.invalidRequest }
        if handler == nil {
            return try MailIndexReader().read(
                sourceMessageID: sourceMessageID, maximumBodyBytes: maximumBodyBytes
            )
        }
        return try call(
            capability: "mail.message.get",
            payload: MailReadPayload(
                sourceMessageID: sourceMessageID, maximumBodyBytes: maximumBodyBytes
            ),
            result: MailReadOutput.self
        )
    }

    private func call<Payload: Encodable, Result: Decodable>(
        capability: String,
        payload: Payload,
        result: Result.Type
    ) throws -> Result {
        let id = UUID().uuidString.lowercased()
        let request = MailRequest(
            requestID: "req-\(id)", operationID: "op-\(id)", capability: capability,
            idempotencyKey: "idem-\(id)", payload: payload
        )
        let response = try JSONDecoder().decode(
            MailResponse<Result>.self,
            from: try requiredHandler()(try JSONEncoder().encode(request))
        )
        guard response.status == "succeeded", let value = response.result else {
            throw NativeCommandError.rejected(response.error?.code ?? "mail.read_failed")
        }
        return value
    }

    private func requiredHandler() throws -> Handler {
        guard let handler else { throw NativeCommandError.failed }
        return handler
    }
}

private struct MailListPayload: Encodable {
    let from: String
    let to: String
    let limit: Int
    let maximumBodyBytes: Int
    enum CodingKeys: String, CodingKey {
        case from, to, limit
        case maximumBodyBytes = "max_body_bytes"
    }
}

private struct MailReadPayload: Encodable {
    let sourceMessageID: String
    let maximumBodyBytes: Int
    enum CodingKeys: String, CodingKey {
        case sourceMessageID = "source_message_id"
        case maximumBodyBytes = "max_body_bytes"
    }
}

private struct MailPolicy: Encodable {
    let effect: String = "read"
    let requiredEvidence: String = "none"
    let artifactDirectory: String? = nil
    enum CodingKeys: String, CodingKey {
        case effect
        case requiredEvidence = "required_evidence"
        case artifactDirectory = "artifact_directory"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(effect, forKey: .effect)
        try values.encode(requiredEvidence, forKey: .requiredEvidence)
        try values.encodeNil(forKey: .artifactDirectory)
    }
}

private struct MailRequest<Payload: Encodable>: Encodable {
    let kind = "request"
    let protocolVersion = "2.0.0"
    let applicationContract = "sherpa.mail.v2"
    let requestID: String
    let operationID: String
    let capability: String
    let deadlineMilliseconds = 30_000
    let idempotencyKey: String
    let policy = MailPolicy()
    let payload: Payload
    enum CodingKeys: String, CodingKey {
        case kind
        case protocolVersion = "protocol_version"
        case applicationContract = "application_contract"
        case requestID = "request_id"
        case operationID = "operation_id"
        case capability, payload
        case deadlineMilliseconds = "deadline_ms"
        case idempotencyKey = "idempotency_key"
        case policy
    }
}

private struct MailResponse<Result: Decodable>: Decodable {
    let status: String
    let result: Result?
    let error: MailResponseError?
}

private struct MailResponseError: Decodable {
    let code: String
}

private func parsedDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
