public struct WorkerCapabilitiesResult: Codable, Sendable, Equatable {
    public let schema: String
    public let worker: String
    public let capabilities: [WorkerCapabilityDescriptor]

    public init(capabilities: [WorkerCapabilityDescriptor]) {
        schema = "sherpa.worker-capabilities.v2"
        worker = "eventkit"
        self.capabilities = capabilities
    }
}

public struct WorkerCapabilityDescriptor: Codable, Sendable, Equatable {
    public let capability: String
    public let applicationContract: String
    public let requestSchema: String
    public let successSchema: String
    public let partialSchema: String?
    public let uncertainSchema: String?
    public let effect: String
    public let requiredEvidence: String
    public let artifactPolicy: String
    public let destination: String
    public let state: String
    public let stableReasonCode: String?

    public init(
        capability: String,
        effect: String,
        requiredEvidence: String,
        destination: String,
        supportsIncompleteOutcomes: Bool
    ) {
        let stem = "sherpa.planner.\(capability)"
        self.capability = capability
        applicationContract = "sherpa.planner.v2"
        requestSchema = "\(stem).request.v2"
        successSchema = "\(stem).success.v2"
        partialSchema = supportsIncompleteOutcomes ? "\(stem).partial.v2" : nil
        uncertainSchema = supportsIncompleteOutcomes ? "\(stem).uncertain.v2" : nil
        self.effect = effect
        self.requiredEvidence = requiredEvidence
        artifactPolicy = "none"
        self.destination = destination
        state = "supported"
        stableReasonCode = nil
    }

    enum CodingKeys: String, CodingKey {
        case capability
        case applicationContract = "application_contract"
        case requestSchema = "request_schema"
        case successSchema = "success_schema"
        case partialSchema = "partial_schema"
        case uncertainSchema = "uncertain_schema"
        case effect
        case requiredEvidence = "required_evidence"
        case artifactPolicy = "artifact_policy"
        case destination, state
        case stableReasonCode = "stable_reason_code"
    }
}
