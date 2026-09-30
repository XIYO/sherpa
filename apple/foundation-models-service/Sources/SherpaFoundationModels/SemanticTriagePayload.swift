import Foundation
import SherpaWorkerProtocol

let contextSemanticTriageRequestSchema = "sherpa.context-semantic-triage-request.v1"
let contextSemanticTriageResultSchema = "sherpa.context-semantic-triage-result.v1"
let maximumTriageRows = 16

struct SemanticTriagePayload {
    let analysisID: String
    let chunkID: String
    let source: String
    let transcript: String
    let timezone: String
    let referenceTime: String
    let rowCount: Int
    let maximumRelations: Int

    init(object: JSONObject) throws {
        let keys: Set<String> = [
            "schema", "analysis_id", "chunk_id", "source", "transcript",
            "timezone", "reference_time", "row_count", "max_relations",
        ]
        struct Wire: Decodable {
            let schema, analysisID, chunkID, source, transcript, timezone, referenceTime: String
            let rowCount, maxRelations: Int
            enum CodingKeys: String, CodingKey { case schema, analysisID = "analysis_id", chunkID = "chunk_id", source, transcript, timezone, referenceTime = "reference_time", rowCount = "row_count", maxRelations = "max_relations" }
        }
        let wire = try object.decode(as: Wire.self, allowedKeys: keys)
        guard wire.schema == contextSemanticTriageRequestSchema else { throw WorkerProtocolError.invalidPayload }
        let analysisID = wire.analysisID, chunkID = wire.chunkID, source = wire.source
        let transcript = wire.transcript, timezone = wire.timezone, referenceTime = wire.referenceTime
        let rowCount = wire.rowCount, maximumRelations = wire.maxRelations
        guard isSafeTriageIdentifier(analysisID),
              isSafeTriageIdentifier(chunkID),
              ["imessage", "kakaotalk", "mail"].contains(source),
              !transcript.isEmpty,
              transcript.utf8.count <= maximumTranscriptBytes,
              TimeZone(identifier: timezone) != nil,
              parseRFC3339(referenceTime) != nil,
              (1 ... maximumTriageRows).contains(rowCount),
              maximumRelations == rowCount
        else { throw WorkerProtocolError.invalidPayload }
        try validateTriageTranscript(transcript, source: source, expectedRows: rowCount)

        self.analysisID = analysisID
        self.chunkID = chunkID
        self.source = source
        self.transcript = transcript
        self.timezone = timezone
        self.referenceTime = referenceTime
        self.rowCount = rowCount
        self.maximumRelations = maximumRelations
    }
}

private func validateTriageTranscript(
    _ transcript: String,
    source: String,
    expectedRows: Int
) throws {
    let lines = transcript
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
    guard let header = lines.first else { throw WorkerProtocolError.invalidPayload }
    let isMail = source == "mail"
    guard header.hasPrefix(isMail ? "!TM1|" : "!TC1|"),
          lines.count - 1 == expectedRows
    else { throw WorkerProtocolError.invalidPayload }

    for (offset, line) in lines.dropFirst().enumerated() {
        let fields = try splitTriageFields(line)
        guard fields.count == (isMail ? 7 : 8),
              fields[1] == String(offset + 1),
              validPartToken(fields[2])
        else { throw WorkerProtocolError.invalidPayload }
    }
}

private func splitTriageFields(_ line: String) throws -> [String] {
    var fields = [String]()
    var field = String()
    var escaped = false
    for character in line {
        if character == "|", !escaped {
            fields.append(field)
            field.removeAll(keepingCapacity: true)
            continue
        }
        field.append(character)
        if escaped {
            escaped = false
        } else if character == "\\" {
            escaped = true
        }
    }
    guard !escaped else { throw WorkerProtocolError.invalidPayload }
    fields.append(field)
    return fields
}

private func validPartToken(_ value: String) -> Bool {
    let components = value.split(separator: "/", omittingEmptySubsequences: false)
    guard components.count == 2,
          let index = Int(components[0]),
          let total = Int(components[1])
    else { return false }
    return index > 0 && total > 0 && index <= total && total <= 9_999
}

private func isSafeTriageIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 64 && value.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122:
            true
        default:
            false
        }
    }
}
