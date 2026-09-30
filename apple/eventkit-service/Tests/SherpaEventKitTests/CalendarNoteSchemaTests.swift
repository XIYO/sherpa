import SherpaPlannerContract
import Testing

@Test func calendarNoteSchemasResolveTheVersionsStoredInCalendar() {
    #expect(CalendarNoteSchemaRegistry.resolve(in: """
    카드 대금 결제 · 예시 카드

    카드
    • 발급사: 예시

    @schema: xiyo.calendar.card-payment@2.1
    """) == .supported(.cardPaymentV2_1))
    #expect(CalendarNoteSchemaRegistry.resolve(in: """
    카드 대금 결제 · 예시 카드

    카드
    • 발급사: 예시

    @schema: xiyo.calendar.card-payment@2.2
    """) == .supported(.cardPaymentV2_2))
    #expect(CalendarNoteSchemaRegistry.resolve(in: """
    예시 정수기 구독료 · 예시카드

    결제수단
    • 유형: 신용카드
    • 발급사: 예시카드

    @schema: xiyo.calendar.payment@3.0
    """) == .supported(.paymentV3_0))
}

@Test func calendarNoteSchemaIsTheTerminalDeclarationOnly() {
    #expect(CalendarNoteSchemaRegistry.resolve(in: "자유 노트") == .none)
    #expect(CalendarNoteSchemaRegistry.resolve(in: "@schema: xiyo.calendar.unknown@9") == .unsupported("xiyo.calendar.unknown@9"))
    #expect(CalendarNoteSchemaRegistry.resolve(in: """
    @schema: xiyo.calendar.card-payment@2.2
    이 뒤에 본문이 있으면 안 된다
    """) == .malformed)
}

@Test func calendarNoteSchemaRendererKeepsTheVersionMarkerAtTheEnd() throws {
    let note = try CalendarNoteSchemaRegistry.render(
        schema: .latestCardPayment,
        summary: "카드 대금 결제 · 예시 카드",
        sections: [
            .init(heading: "카드", facts: ["발급사: 예시카드"]),
            .init(heading: "결제", facts: ["결제일: 매월 14일"]),
        ]
    )
    #expect(note.hasSuffix("@schema: xiyo.calendar.card-payment@2.2"))
    #expect(CalendarNoteSchemaRegistry.resolve(in: note) == .supported(.cardPaymentV2_2))
}

@Test func cardPaymentSchemasRetainTheirVersionSpecificWritingChecklists() {
    let v21 = CalendarNoteSchema.cardPaymentV2_1.definition.sections
    let v22 = CalendarNoteSchema.cardPaymentV2_2.definition.sections

    #expect(v21.contains(.init("자동납부", ["항목", "상태", "신청일", "적용일", "확인일"])))
    #expect(!v21.contains(where: { $0.heading == "명세서" }))
    #expect(v22.contains(.init("명세서", ["수신처"])))
    #expect(v22.first(where: { $0.heading == "결제" })?.fields.contains("결제계좌") == true)
    #expect(v22.first(where: { $0.heading == "기본혜택" })?.fields.contains("포인트표") == true)
}

@Test func existingCalendarRecordDoesNotAutoMigrateToTheLatestSchema() {
    let v21 = """
    카드 대금 결제 · 예시 카드

    @schema: xiyo.calendar.card-payment@2.1
    """
    #expect(CalendarNoteSchema.cardPaymentV2_1.successor == .cardPaymentV2_2)
    #expect(CalendarNoteSchema.cardPaymentV2_2.successor == .paymentV3_0)
    #expect(CalendarNoteSchema.paymentV3_0.successor == nil)
    #expect(CalendarNoteSchemaRegistry.schemaForUpdate(of: v21) == .cardPaymentV2_1)
    #expect(CalendarNoteSchema.latestCardPayment == .cardPaymentV2_2)
    #expect(CalendarNoteSchema.latestPayment == .paymentV3_0)
}

@Test func paymentSchemaRendererRoundTripsWithNeutralSections() throws {
    let note = try CalendarNoteSchemaRegistry.render(
        schema: .latestPayment,
        summary: "예시 정수기 구독료 · 예시카드",
        sections: [
            .init(heading: "결제수단", facts: ["유형: 신용카드", "발급사: 예시카드"]),
            .init(heading: "결제", facts: ["결제일: 매월 20일"]),
            .init(heading: "자동납부", facts: ["항목: 예시전자 정수기 구독", "청구금액: 10,000원", "할인전금액: 20,000원"]),
            .init(heading: "구독", facts: ["제공사: 예시전자", "계약번호: 00000000", "약정기간: 2030-01-01 ~ 2035-12-31"]),
        ]
    )
    #expect(note.hasSuffix("@schema: xiyo.calendar.payment@3.0"))
    #expect(CalendarNoteSchemaRegistry.resolve(in: note) == .supported(.paymentV3_0))
}

@Test func paymentSchemaDefinesNeutralAndSubscriptionSections() {
    let v30 = CalendarNoteSchema.paymentV3_0.definition.sections

    #expect(v30.contains(where: { $0.heading == "결제수단" }))
    #expect(!v30.contains(where: { $0.heading == "카드" }))
    #expect(v30.first(where: { $0.heading == "결제수단" })?.fields.contains("유형") == true)
    #expect(v30.first(where: { $0.heading == "결제수단" })?.fields.contains("은행") == true)
    #expect(v30.first(where: { $0.heading == "결제수단" })?.fields.contains("계좌") == true)
    #expect(v30.contains(where: { $0.heading == "구독" }))
    #expect(v30.first(where: { $0.heading == "구독" })?.fields.contains("계약번호") == true)
    #expect(v30.first(where: { $0.heading == "구독" })?.fields.contains("약정기간") == true)
    #expect(v30.first(where: { $0.heading == "자동납부" })?.fields.contains("청구금액") == true)
    #expect(v30.first(where: { $0.heading == "자동납부" })?.fields.contains("할인전금액") == true)
}
