import Foundation
import SherpaWorkerProtocol

struct ModelTranscript {
    let text: String
    let evidenceContent: [Int: String]
}

private enum TranscriptKind {
    case cct6
    case cct7
    case mct2
    case freshChat
    case freshMail
}

/// Removes opaque evidence pairs before source content reaches the model.
/// Exact immutable pairs remain in the validated request and are represented
/// to the model only by bounded one-based ephemeral handles.
func makeModelTranscript(_ payload: AnalysisPayload) throws -> ModelTranscript {
    var lines = payload.transcript
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
    guard let header = lines.first else { throw WorkerProtocolError.invalidPayload }

    let kind: TranscriptKind
    if header.hasPrefix("!CCT6|") {
        kind = .cct6
    } else if header.hasPrefix("!CCT7|") {
        kind = .cct7
    } else if header.hasPrefix("!MCT2|") {
        kind = .mct2
    } else if header.hasPrefix("!FCHAT1|") {
        kind = .freshChat
    } else if header.hasPrefix("!FMAIL1|") {
        kind = .freshMail
    } else {
        throw WorkerProtocolError.invalidPayload
    }
    let isMail = kind == .mct2 || kind == .freshMail
    guard (payload.source == "mail") == isMail else {
        throw WorkerProtocolError.invalidPayload
    }

    lines[0] = try modelHeader(header, kind: kind)
    let handles = Dictionary(
        uniqueKeysWithValues: payload.evidenceList.enumerated().map { index, evidence in
            (evidence, index + 1)
        }
    )
    var seen = Set<Int>()
    var evidenceContent = [Int: String]()
    for index in lines.indices.dropFirst() {
        if lines[index].isEmpty { continue }
        var fields = try splitEscapedFields(lines[index])
        let evidenceFields: (record: Int, revision: Int)? = switch kind {
        case .cct6:
            fields.count == 2 && ["T", "D"].contains(fields[0]) ? nil : (2, 3)
        case .cct7:
            fields.count == 2 && ["T", "D", "S"].contains(fields[0]) ? nil : (1, 2)
        case .mct2:
            fields.count == 2 && fields[0] == "D" ? nil : (1, 2)
        case .freshChat, .freshMail:
            (1, 2)
        }
        guard let evidenceFields else { continue }
        let expectedCount = switch kind {
        case .cct6: 5
        case .cct7: 4
        case .mct2: 14
        case .freshChat: 8
        case .freshMail: 6
        }
        guard fields.count == expectedCount else {
            throw WorkerProtocolError.invalidPayload
        }

        let recordPrefix: String = switch kind {
        case .mct2: "mail1_"
        case .cct6, .cct7: "ctxm1_"
        case .freshChat, .freshMail: ""
        }
        let revisionPrefix: String = switch kind {
        case .mct2: "mailr1_"
        case .cct6, .cct7: "ctxr1_"
        case .freshChat, .freshMail: ""
        }
        let evidence = EvidenceReference(
            record: recordPrefix + fields[evidenceFields.record],
            revision: revisionPrefix + fields[evidenceFields.revision]
        )
        guard let handle = handles[evidence], seen.insert(handle).inserted else {
            throw WorkerProtocolError.invalidPayload
        }
        let contentFields: [String] = switch kind {
        case .cct6: [fields[4]]
        case .cct7: [fields[3]]
        case .mct2: [fields[9], fields[11]]
        case .freshChat: [fields[7]]
        case .freshMail: [fields[4], fields[5]]
        }
        evidenceContent[handle] = try contentFields
            .map(unescapeField)
            .joined(separator: "\n")
        fields.remove(at: evidenceFields.revision)
        fields.remove(at: evidenceFields.record)
        let handleIndex = switch kind {
        case .cct6: 2
        case .cct7, .mct2, .freshChat, .freshMail: 1
        }
        fields.insert(String(handle), at: handleIndex)
        lines[index] = fields.joined(separator: "|")
    }
    guard seen.count == payload.evidenceList.count else {
        throw WorkerProtocolError.invalidPayload
    }
    return ModelTranscript(
        text: lines.joined(separator: "\n"),
        evidenceContent: evidenceContent
    )
}

private func modelHeader(_ header: String, kind: TranscriptKind) throws -> String {
    var fields = try splitEscapedFields(header)
    guard !fields.isEmpty else { throw WorkerProtocolError.invalidPayload }
    fields.removeAll { $0.hasPrefix("r=") || $0.hasPrefix("v=") }
    let isMail = kind == .mct2 || kind == .freshMail
    fields[0] = isMail ? "!MAIL1" : "!CHAT1"
    if !isMail {
        fields.append("e=ordinal")
    }
    if let rowIndex = fields.firstIndex(where: { $0.hasPrefix("row=") })
    {
        fields[rowIndex] = fields[rowIndex].replacingOccurrences(
            of: ",ref,revision,",
            with: ",evidence,"
        )
    }
    return fields.joined(separator: "|")
}

private func splitEscapedFields(_ line: String) throws -> [String] {
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

private func unescapeField(_ value: String) throws -> String {
    var output = String()
    var characters = value.makeIterator()
    while let character = characters.next() {
        guard character == "\\" else {
            output.append(character)
            continue
        }
        guard let escaped = characters.next() else {
            throw WorkerProtocolError.invalidPayload
        }
        switch escaped {
        case "\\": output.append("\\")
        case "|": output.append("|")
        case "n": output.append("\n")
        case "r": output.append("\r")
        default: throw WorkerProtocolError.invalidPayload
        }
    }
    return output
}
