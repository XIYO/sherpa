import Foundation
import SherpaWorkerProtocol

let contextAnalysisSchema = "sherpa.context-analysis-request.v1"
let planningSuggestionSchema = "sherpa.planning-suggestions.v1"
let maximumTranscriptBytes = 1_048_576
let maximumEvidenceItems = 4_096

struct EvidenceReference: Hashable {
    let record: String
    let revision: String

    var object: JSONObject {
        [
            "record_reference": .string(record),
            "revision_reference": .string(revision),
        ]
    }
}

struct AnalysisPayload {
    let analysisID: String
    let source: String
    let transcript: String
    let timezone: String
    let referenceTime: String
    let maximumProposals: Int
    let evidenceList: [EvidenceReference]
    let evidence: Set<EvidenceReference>

    init(object: JSONObject) throws {
        let keys: Set<String> = [
            "schema", "analysis_id", "source", "transcript", "timezone",
            "reference_time", "max_proposals", "evidence",
        ]
        struct EvidenceWire: Decodable { let recordReference, revisionReference: String; enum CodingKeys: String, CodingKey { case recordReference = "record_reference", revisionReference = "revision_reference" } }
        struct Wire: Decodable {
            let schema, analysisID, source, transcript, timezone, referenceTime: String
            let maxProposals: Int
            let evidence: [EvidenceWire]
            enum CodingKeys: String, CodingKey { case schema, analysisID = "analysis_id", source, transcript, timezone, referenceTime = "reference_time", maxProposals = "max_proposals", evidence }
        }
        let wire = try object.decode(as: Wire.self, allowedKeys: keys)
        let analysisID = wire.analysisID, source = wire.source, transcript = wire.transcript
        let timezone = wire.timezone, referenceTime = wire.referenceTime
        let maximumProposals = wire.maxProposals, rawEvidence = wire.evidence
        guard wire.schema == contextAnalysisSchema else { throw WorkerProtocolError.invalidPayload }
        guard isSafeIdentifier(analysisID),
              ["imessage", "kakaotalk", "mail"].contains(source),
              !transcript.isEmpty,
              transcript.utf8.count <= maximumTranscriptBytes,
              TimeZone(identifier: timezone) != nil,
              parseRFC3339(referenceTime) != nil,
              (1 ... 64).contains(maximumProposals),
              !rawEvidence.isEmpty,
              rawEvidence.count <= maximumEvidenceItems
        else { throw WorkerProtocolError.invalidPayload }

        let evidenceList = try rawEvidence.map { value in
            let record = value.recordReference, revision = value.revisionReference
            guard validEvidencePair(record: record, revision: revision, source: source)
            else { throw WorkerProtocolError.invalidPayload }
            return EvidenceReference(record: record, revision: revision)
        }
        let evidence = Set(evidenceList)
        guard evidence.count == rawEvidence.count else {
            throw WorkerProtocolError.invalidPayload
        }

        self.analysisID = analysisID
        self.source = source
        self.transcript = transcript
        self.timezone = timezone
        self.referenceTime = referenceTime
        self.maximumProposals = maximumProposals
        self.evidenceList = evidenceList
        self.evidence = evidence
    }
}

private func isSafeIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 64 && value.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122:
            true
        default:
            false
        }
    }
}

private func validEvidencePair(record: String, revision: String, source: String) -> Bool {
    guard isSafeReference(record), isSafeReference(revision) else { return false }
    if record.hasPrefix("evi1_") && revision.hasPrefix("evr1_") {
        return record.dropFirst("evi1_".count) == revision.dropFirst("evr1_".count)
    }
    if source == "mail" {
        return record.hasPrefix("mail1_") && revision.hasPrefix("mailr1_")
    }
    return record.hasPrefix("ctxm1_") && revision.hasPrefix("ctxr1_")
}

private func isSafeReference(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122:
            true
        default:
            false
        }
    }
}
