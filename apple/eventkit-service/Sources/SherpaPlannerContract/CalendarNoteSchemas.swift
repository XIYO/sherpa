import Foundation

/// Versioned, human-readable records stored in Calendar notes.
///
/// This is deliberately separate from the Planner worker protocol.  The
/// protocol describes a request to EventKit; a calendar note schema describes
/// the durable record the assistant writes into the user's Calendar.
public enum CalendarNoteSchema: String, CaseIterable, Codable, Sendable, Equatable {
    case cardPaymentV2_1 = "xiyo.calendar.card-payment@2.1"
    case cardPaymentV2_2 = "xiyo.calendar.card-payment@2.2"
    case paymentV3_0 = "xiyo.calendar.payment@3.0"

    public static let latestCardPayment: Self = .cardPaymentV2_2
    public static let latestPayment: Self = .paymentV3_0

    /// A successor is a writing choice for a newly created record, never an
    /// instruction to rewrite an existing Calendar note automatically.
    public var successor: Self? {
        switch self {
        case .cardPaymentV2_1: .cardPaymentV2_2
        case .cardPaymentV2_2: .paymentV3_0
        case .paymentV3_0: nil
        }
    }

    public var definition: CalendarNoteSchemaDefinition {
        switch self {
        case .cardPaymentV2_1:
            .init(
                schema: self,
                sections: [
                    .init("카드", ["발급사", "상품", "상품코드", "상품출처", "끝번호", "유효기간", "브랜드", "연회비", "연회비조건", "교통기능"]),
                    .init("결제", ["결제일", "청구이용기간", "명세서작성기준일", "출처", "확인일"]),
                    .init("보안", ["해외원화결제", "해외거래", "확인일"]),
                    .init("기본혜택", ["이름", "대상", "할인표", "실적산정기간", "국내반영기준", "해외반영기준", "적용기간", "조건", "실적제외", "출처", "확인일"]),
                    .init("프로모션", ["이름", "추가할인표", "모집기간", "제공가능기간", "개인한도", "개인시작월", "개인종료월", "상태", "조건", "출처", "확인일"]),
                    .init("자동납부", ["항목", "상태", "신청일", "적용일", "확인일"]),
                ]
            )
        case .cardPaymentV2_2:
            .init(
                schema: self,
                sections: [
                    .init("카드", ["발급사", "상품", "상품코드", "상품출처", "끝번호", "유효기간", "브랜드", "연회비", "연회비조건", "교통기능"]),
                    .init("결제", ["결제일", "결제계좌", "청구이용기간", "명세서작성기준일", "출처", "확인일"]),
                    .init("명세서", ["수신처"]),
                    .init("보안", ["해외원화결제", "해외거래", "확인일"]),
                    .init("기본혜택", ["이름", "대상", "할인표", "포인트표", "실적산정기간", "국내반영기준", "해외반영기준", "적용기간", "조건", "실적포함", "실적제외", "출처", "확인일"]),
                    .init("프로모션", ["이름", "추가할인표", "모집기간", "제공가능기간", "개인한도", "개인시작월", "개인종료월", "상태", "조건", "출처", "확인일"]),
                    .init("자동납부", ["항목", "상태", "신청일", "적용일", "확인일"]),
                ]
            )
        case .paymentV3_0:
            .init(
                schema: self,
                sections: [
                    .init("결제수단", ["유형", "발급사", "상품", "상품코드", "끝번호", "유효기간", "브랜드", "은행", "계좌", "출처"]),
                    .init("결제", ["결제일", "청구이용기간", "명세서작성기준일", "출처", "확인일"]),
                    .init("명세서", ["수신처"]),
                    .init("보안", ["해외원화결제", "해외거래", "확인일"]),
                    .init("기본혜택", ["이름", "대상", "할인표", "포인트표", "실적산정기간", "국내반영기준", "해외반영기준", "적용기간", "조건", "실적포함", "실적제외", "출처", "확인일"]),
                    .init("프로모션", ["이름", "추가할인표", "모집기간", "제공가능기간", "개인한도", "개인시작월", "개인종료월", "상태", "조건", "출처", "확인일"]),
                    .init("자동납부", ["항목", "상태", "청구금액", "할인전금액", "신청일", "적용일", "확인일"]),
                    .init("구독", ["제공사", "계약번호", "약정기간", "제품", "모델명"]),
                ]
            )
        }
    }
}

public struct CalendarNoteSchemaDefinition: Sendable, Equatable {
    public let schema: CalendarNoteSchema
    /// Canonical section order. A record may omit a section when the source
    /// has no fact for it; unknown existing sections must be preserved.
    public let sections: [CalendarNoteSchemaSectionDefinition]

    public init(schema: CalendarNoteSchema, sections: [CalendarNoteSchemaSectionDefinition]) {
        self.schema = schema
        self.sections = sections
    }
}

public struct CalendarNoteSchemaSectionDefinition: Sendable, Equatable {
    public let heading: String
    /// Ordered writing checklist. A field is omitted only when the source has
    /// no fact and the writer cannot state `확인 필요` truthfully.
    public let fields: [String]

    public init(_ heading: String, _ fields: [String]) {
        self.heading = heading
        self.fields = fields
    }
}

public struct CalendarNoteSection: Sendable, Equatable {
    public let heading: String
    /// Each entry is a rendered fact without its bullet prefix, for example
    /// `발급사: 예시카드`.
    public let facts: [String]

    public init(heading: String, facts: [String]) {
        self.heading = heading
        self.facts = facts
    }
}

public enum CalendarNoteSchemaResolution: Sendable, Equatable {
    case none
    case supported(CalendarNoteSchema)
    /// Never rewrite an unknown version: it is still a durable user record.
    case unsupported(String)
    case malformed
}

public enum CalendarNoteSchemaError: Error, Equatable {
    case blankSummary
    case invalidSection
    case invalidFact
}

/// The sole registry for Calendar note record formats.
public enum CalendarNoteSchemaRegistry {
    private static let markerPrefix = "@schema:"

    public static func resolve(in note: String) -> CalendarNoteSchemaResolution {
        let nonblankLines = note.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let markers = nonblankLines.filter { $0.hasPrefix(markerPrefix) }
        guard !markers.isEmpty else { return .none }
        guard markers.count == 1, markers[0] == nonblankLines.last else { return .malformed }

        let identifier = String(markers[0].dropFirst(markerPrefix.count)).trimmingCharacters(in: .whitespaces)
        guard !identifier.isEmpty, !identifier.contains(where: \.isWhitespace) else { return .malformed }
        guard let schema = CalendarNoteSchema(rawValue: identifier) else { return .unsupported(identifier) }
        return .supported(schema)
    }

    /// Existing records retain their declared version.  Only a new record uses
    /// the latest schema for its record family.
    public static func schemaForUpdate(of note: String) -> CalendarNoteSchema? {
        guard case let .supported(schema) = resolve(in: note) else { return nil }
        return schema
    }

    /// Renders a schema-owned record. Callers must carry forward sections and
    /// facts they do not understand when updating an existing record.
    public static func render(
        schema: CalendarNoteSchema,
        summary: String,
        sections: [CalendarNoteSection]
    ) throws -> String {
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, !summary.contains(markerPrefix) else {
            throw CalendarNoteSchemaError.blankSummary
        }
        var lines = [summary]
        for section in sections {
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heading.isEmpty, !heading.contains("\n"), !heading.hasPrefix(markerPrefix) else {
                throw CalendarNoteSchemaError.invalidSection
            }
            lines.append("")
            lines.append(heading)
            for fact in section.facts {
                let fact = fact.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fact.isEmpty, !fact.contains("\n"), !fact.hasPrefix(markerPrefix) else {
                    throw CalendarNoteSchemaError.invalidFact
                }
                lines.append("• \(fact)")
            }
        }
        lines.append("")
        lines.append("\(markerPrefix) \(schema.rawValue)")
        return lines.joined(separator: "\n")
    }
}
