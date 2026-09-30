import Foundation

public let sherpaProtocolVersion = "2.0.0"

public enum WorkerProtocolError: Error, Equatable {
    case invalidJSON, invalidEnvelope, readFailure, requestTooLarge
    case unsupportedVersion, unsupportedCapability, invalidPayload, resultTooLarge

    public var stableCode: String {
        switch self {
        case .invalidJSON: "protocol.invalid_json"
        case .invalidEnvelope: "protocol.invalid_envelope"
        case .readFailure: "protocol.read_failure"
        case .requestTooLarge: "protocol.request_too_large"
        case .unsupportedVersion: "protocol.unsupported_version"
        case .unsupportedCapability: "protocol.unsupported_capability"
        case .invalidPayload: "protocol.invalid_payload"
        case .resultTooLarge: "protocol.result_too_large"
        }
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), integer(Int64), number(Double), string(String)
    case array([JSONValue]), object(JSONObject)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Int64.self) { self = .integer(decoded) }
        else if let decoded = try? value.decode(Double.self), decoded.isFinite { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([JSONValue].self) { self = .array(decoded) }
        else if let decoded = try? value.decode(JSONObject.self) { self = .object(decoded) }
        else { throw WorkerProtocolError.invalidJSON }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .bool(decoded): try value.encode(decoded)
        case let .integer(decoded): try value.encode(decoded)
        case let .number(decoded): guard decoded.isFinite else { throw WorkerProtocolError.invalidPayload }; try value.encode(decoded)
        case let .string(decoded): try value.encode(decoded)
        case let .array(decoded): try value.encode(decoded)
        case let .object(decoded): try value.encode(decoded)
        }
    }
}

public extension JSONValue {
    var string: String? { if case let .string(value) = self { value } else { nil } }
    var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
    var integer: Int? {
        if case let .integer(value) = self, let exact = Int(exactly: value) { exact } else { nil }
    }
    var double: Double? {
        switch self { case let .number(value): value; case let .integer(value): Double(value); default: nil }
    }
    var array: [JSONValue]? { if case let .array(value) = self { value } else { nil } }
    var object: JSONObject? { if case let .object(value) = self { value } else { nil } }
    var isNull: Bool { self == .null }
}

public typealias JSONObject = [String: JSONValue]

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

public extension JSONObject {
    func decode<T: Decodable>(as type: T.Type, allowedKeys: Set<String>, requiredKeys: Set<String>? = nil) throws -> T {
        let actual = Set(keys)
        guard actual.isSubset(of: allowedKeys), (requiredKeys ?? allowedKeys).isSubset(of: actual)
        else { throw WorkerProtocolError.invalidPayload }
        do { return try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
        catch { throw WorkerProtocolError.invalidPayload }
    }

    func decodeExact<T: Codable>(as type: T.Type, allowedKeys: Set<String>, requiredKeys: Set<String>? = nil) throws -> T {
        let value = try decode(as: type, allowedKeys: allowedKeys, requiredKeys: requiredKeys)
        guard try encodeJSONObject(value) == self else { throw WorkerProtocolError.invalidPayload }
        return value
    }
}

public func encodeJSONObject<T: Encodable>(_ value: T) throws -> JSONObject {
    do {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        guard case let .object(object) = decoded else { throw WorkerProtocolError.invalidPayload }
        return object
    } catch let error as WorkerProtocolError { throw error }
    catch { throw WorkerProtocolError.invalidPayload }
}

public enum WorkerEffect: String, Codable, Sendable, Equatable { case read, authorizationPrompt = "authorization_prompt", mutation, dispatch; public static var write: Self { .mutation } }
public enum RequiredEvidence: String, Codable, Sendable { case none, authorizationReadback = "authorization_readback", nativeReadback = "native_readback", nativeAbsenceReadback = "native_absence_readback", applicationAcceptance = "application_acceptance" }

public struct WorkerPolicy: Codable, Sendable, Equatable {
    public let effect: WorkerEffect
    public let requiredEvidence: RequiredEvidence
    public let artifactDirectory: String?
    enum CodingKeys: String, CodingKey { case effect, requiredEvidence = "required_evidence", artifactDirectory = "artifact_directory" }
}

public struct WorkerRequest: Sendable {
    public let requestID, operationID, capability, applicationContract, idempotencyKey: String
    public let payload: JSONObject
    public let deadlineMilliseconds: Int
    public let policy: WorkerPolicy
    public var effect: WorkerEffect { policy.effect }
    public var artifactDirectory: String? { policy.artifactDirectory }

    public init(data: Data) throws {
        let decoder = JSONDecoder()
        let root: JSONObject
        do { root = try decoder.decode(JSONObject.self, from: data) } catch { throw WorkerProtocolError.invalidJSON }
        let keys: Set<String> = ["kind", "protocol_version", "application_contract", "request_id", "operation_id", "capability", "payload", "deadline_ms", "idempotency_key", "policy"]
        guard Set(root.keys) == keys, root["kind"] == .string("request") else { throw WorkerProtocolError.invalidEnvelope }
        guard case let .string(version)? = root["protocol_version"] else { throw WorkerProtocolError.invalidEnvelope }
        guard version == sherpaProtocolVersion else { throw WorkerProtocolError.unsupportedVersion }
        guard case let .string(contract)? = root["application_contract"], case let .string(requestID)? = root["request_id"], case let .string(operationID)? = root["operation_id"], case let .string(capability)? = root["capability"], case let .object(payload)? = root["payload"], case let .integer(deadline)? = root["deadline_ms"], case let .string(idempotency)? = root["idempotency_key"], case let .object(policyObject)? = root["policy"] else { throw WorkerProtocolError.invalidEnvelope }
        guard Set(policyObject.keys) == ["effect", "required_evidence", "artifact_directory"] else { throw WorkerProtocolError.invalidEnvelope }
        let policyData = try JSONEncoder().encode(policyObject)
        guard let policy = try? decoder.decode(WorkerPolicy.self, from: policyData), validArtifactDirectory(policy.artifactDirectory), (1...300_000).contains(deadline), deadline <= Int64(Int.max), [requestID, operationID, capability, idempotency].allSatisfy({ isSafeIdentifier($0, maximumLength: 128) }), isSafeIdentifier(contract, maximumLength: 128) else { throw WorkerProtocolError.invalidEnvelope }
        self.requestID = requestID; self.operationID = operationID; self.capability = capability
        self.applicationContract = contract; self.payload = payload
        self.deadlineMilliseconds = Int(deadline); self.idempotencyKey = idempotency; self.policy = policy
    }
}

public enum WorkerStatus: String, Codable, Sendable { case succeeded, failed, partial, uncertain }
public enum EffectKind: String, Codable, Sendable { case none, authorizationPrompt = "authorization_prompt", nativeMutation = "native_mutation", outboundDispatch = "outbound_dispatch" }
public enum EffectState: String, Codable, Sendable { case notApplicable = "not_applicable", notStarted = "not_started", applied, mayHaveApplied = "may_have_applied" }
public enum EvidenceKind: String, Codable, Sendable { case authorizationReadback = "authorization_readback", nativeReadback = "native_readback", nativeAbsenceReadback = "native_absence_readback", applicationAcceptance = "application_acceptance" }
public enum EvidenceState: String, Codable, Sendable { case matched, mismatched, unavailable }
public enum RetryDisposition: String, Codable, Sendable { case never, safe, afterBackoff = "after_backoff", afterUserAction = "after_user_action" }
public struct WorkerEffectOutcome: Codable, Sendable { public let kind: EffectKind; public let state: EffectState; public init(kind: EffectKind, state: EffectState) { self.kind = kind; self.state = state } }
public struct WorkerEvidence: Codable, Sendable { public let kind: EvidenceKind; public let state: EvidenceState; public init(kind: EvidenceKind, state: EvidenceState) { self.kind = kind; self.state = state } }
public struct WorkerError: Codable, Sendable { public let code: String; public let retry: RetryDisposition; public init(code: String, retry: RetryDisposition) { self.code = code; self.retry = retry } }

public struct WorkerResponse: Codable, Sendable {
    public let kind = "response", protocolVersion = sherpaProtocolVersion
    public let applicationContract, requestID, operationID, capability: String
    public let status: WorkerStatus
    public let result: JSONValue?
    public let effect: WorkerEffectOutcome
    public let evidence: WorkerEvidence?
    public let error: WorkerError?
    public let warnings: [JSONValue]
    public var stableErrorCode: String? { error?.code }
    enum CodingKeys: String, CodingKey { case kind, protocolVersion = "protocol_version", applicationContract = "application_contract", requestID = "request_id", operationID = "operation_id", capability, status, result, effect, evidence, error, warnings }

    public static func success(request: WorkerRequest, result: JSONObject, effect: WorkerEffectOutcome = .init(kind: .none, state: .notApplicable), evidence: WorkerEvidence? = nil) -> Self { .init(applicationContract: request.applicationContract, requestID: request.requestID, operationID: request.operationID, capability: request.capability, status: .succeeded, result: .object(result), effect: effect, evidence: evidence, error: nil, warnings: []) }
    public static func failure(request: WorkerRequest, code: String, retry: RetryDisposition = .never) -> Self { .init(applicationContract: request.applicationContract, requestID: request.requestID, operationID: request.operationID, capability: request.capability, status: .failed, result: nil, effect: .init(kind: .none, state: .notStarted), evidence: nil, error: .init(code: code, retry: retry), warnings: []) }
    public static func uncorrelatedFailure(code: String) -> Self { .init(applicationContract: "sherpa.planner.v2", requestID: "unknown", operationID: "unknown", capability: "unknown", status: .failed, result: nil, effect: .init(kind: .none, state: .notStarted), evidence: nil, error: .init(code: code, retry: .never), warnings: []) }
    public func encoded(maximumBytes: Int = 8 * 1024 * 1024) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(self); guard data.count <= maximumBytes else { throw WorkerProtocolError.resultTooLarge }; return data }
}

public func readWorkerRequest(from handle: FileHandle = .standardInput, maximumBytes: Int = 64 * 1024) throws -> Data {
    guard maximumBytes > 0 else { throw WorkerProtocolError.invalidEnvelope }; var input = Data()
    while true { let allowance = maximumBytes + 1 - input.count; guard allowance > 0 else { throw WorkerProtocolError.requestTooLarge }; let chunk: Data; do { chunk = try handle.read(upToCount: min(8192, allowance)) ?? Data() } catch { throw WorkerProtocolError.readFailure }; if chunk.isEmpty { break }; input.append(chunk); if input.count > maximumBytes { throw WorkerProtocolError.requestTooLarge } }
    return input
}

private func isSafeIdentifier(_ value: String, maximumLength: Int) -> Bool { !value.isEmpty && value.utf8.count <= maximumLength && value.unicodeScalars.allSatisfy { (45...46).contains($0.value) || (48...57).contains($0.value) || (65...90).contains($0.value) || $0.value == 95 || (97...122).contains($0.value) } }
private func validArtifactDirectory(_ value: String?) -> Bool { value.map { !$0.isEmpty && $0.utf8.count <= 4096 && !$0.contains("\0") } ?? true }
