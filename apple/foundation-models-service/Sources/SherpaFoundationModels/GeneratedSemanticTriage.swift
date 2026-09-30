import Foundation
import FoundationModels
import SherpaWorkerProtocol

@Generable
struct GeneratedSemanticTriageBatch {
    @Guide(description: "Exact number of transcript rows inspected. This must equal the requested row count.")
    var reviewedRows: Int

    @Guide(
        description: "Planning-relevant lifecycle relations after inspecting all rows. Use a one-row relation when no other row is needed.",
        .maximumCount(16)
    )
    var relations: [GeneratedSemanticRelation]
}

@Generable
struct GeneratedSemanticRelation {
    @Guide(description: "Exactly one of commitment, request, cancellation, reschedule, recommitment, completion, status_update, deadline, purchase_intent, other_planning_signal.")
    var kind: String

    @Guide(
        description: "Unique one-based row handles needed to establish the fact and its lifecycle context.",
        .count(1 ... 16)
    )
    var handles: [Int]

    @Guide(description: "True when later context or user clarification is required before planning.")
    var ambiguous: Bool
}

enum GeneratedSemanticTriageError: Error {
    case reviewedRows
    case relationCount
    case kind
    case evidenceHandle

    var ruleCode: String {
        switch self {
        case .reviewedRows: "triage_reviewed_rows"
        case .relationCount: "triage_relation_count"
        case .kind: "triage_kind"
        case .evidenceHandle: "triage_evidence_handle"
        }
    }
}

func mapGeneratedSemanticTriage(
    _ generated: GeneratedSemanticTriageBatch,
    payload: SemanticTriagePayload
) throws -> JSONObject {
    guard generated.reviewedRows == payload.rowCount else {
        throw GeneratedSemanticTriageError.reviewedRows
    }
    guard generated.relations.count <= payload.maximumRelations else {
        throw GeneratedSemanticTriageError.relationCount
    }
    let validKinds: Set<String> = [
        "commitment", "request", "cancellation", "reschedule", "recommitment",
        "completion", "status_update", "deadline", "purchase_intent",
        "other_planning_signal",
    ]
    let relations = try generated.relations.map { relation -> JSONValue in
        guard validKinds.contains(relation.kind) else {
            throw GeneratedSemanticTriageError.kind
        }
        guard (1 ... 16).contains(relation.handles.count),
              Set(relation.handles).count == relation.handles.count,
              relation.handles.allSatisfy({ (1 ... payload.rowCount).contains($0) })
        else { throw GeneratedSemanticTriageError.evidenceHandle }
        return .object([
            "kind": .string(relation.kind),
            "handles": .array(relation.handles.map { .integer(Int64($0)) }),
            "ambiguous": .bool(relation.ambiguous),
        ])
    }
    return [
        "schema": .string(contextSemanticTriageResultSchema),
        "analysis_id": .string(payload.analysisID),
        "chunk_id": .string(payload.chunkID),
        "reviewed_rows": .integer(Int64(generated.reviewedRows)),
        "relations": .array(relations),
    ]
}
