import Foundation
import Testing
import SherpaWorkerProtocol
@testable import SherpaFoundationModels

private extension JSONValue {
    var stringValue: String? { if case let .string(value) = self { value } else { nil } }
    var intValue: Int? { if case let .integer(value) = self { Int(exactly: value) } else { nil } }
    var objectValue: JSONObject? { if case let .object(value) = self { value } else { nil } }
    var objects: [JSONObject]? {
        guard case let .array(values) = self else { return nil }
        return values.map(\.objectValue).allSatisfy { $0 != nil } ? values.compactMap(\.objectValue) : nil
    }
}

@Test func payloadRequiresExactEvidencePairs() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    #expect(payload.evidence.count == 1)

    var invalid = payloadObject()
    invalid["evidence"] = [[
        "record_reference": "ctxm1_0000000000001",
        "revision_reference": "mailr1_0000000000001",
    ]]
    #expect(throws: Error.self) {
        _ = try AnalysisPayload(object: invalid)
    }
}

@Test func payloadAcceptsRustRFC3339FractionalSeconds() throws {
    var object = payloadObject()
    object["reference_time"] = "2026-08-01T11:34:27.385158+09:00"

    let payload = try AnalysisPayload(object: object)

    #expect(payload.referenceTime == "2026-08-01T11:34:27.385158+09:00")
}

@Test func payloadRequiresMatchingFreshEvidenceSuffixes() throws {
    _ = try AnalysisPayload(object: freshChatPayloadFixture())
    var invalid = freshChatPayloadFixture()
    invalid["evidence"] = [[
        "record_reference": "evi1_0000000000001",
        "revision_reference": "evr1_0000000000002",
    ]]

    #expect(throws: Error.self) {
        _ = try AnalysisPayload(object: invalid)
    }
}

@Test func RFC3339ParserAcceptsWholeAndFractionalSeconds() {
    #expect(parseRFC3339("2026-08-01T11:34:27+09:00") != nil)
    #expect(parseRFC3339("2026-08-01T11:34:27.385158+09:00") != nil)
    #expect(parseRFC3339("not-a-timestamp") == nil)
}

@Test func transcriptFormatSeparatesMessageTimestampsFromPlanningFacts() {
    let chat = transcriptFormatInstructions(source: "kakaotalk")
    let mail = transcriptFormatInstructions(source: "mail")

    #expect(chat.contains("timestamps, not planning facts"))
    #expect(chat.contains("content can supply"))
    #expect(mail.contains("received/sent columns are message timestamps"))
    #expect(mail.contains("Only subject/body content"))
}

@Test func analysisInstructionsSeparateOccurrencesFromUserActions() {
    let instructions = analysisInstructions(source: "kakaotalk")

    #expect(instructions.contains("delivery, or installation belongs in an Event"))
    #expect(instructions.contains("explicitly requests that action from the user"))
    #expect(instructions.contains("advertisements, product education, generic how-to"))
    #expect(instructions.contains("invalid Event into a Reminder"))
    #expect(instructions.contains("never use a message"))
    #expect(instructions.contains("timestamp, assume a duration"))
    #expect(instructions.contains("one-based ephemeral evidence handle"))
}

@Test func semanticTriagePayloadRequiresSequentialRowsAndExactCoverage() throws {
    let payload = try SemanticTriagePayload(object: semanticTriagePayloadFixture())
    #expect(payload.rowCount == 3)

    var invalid = semanticTriagePayloadFixture()
    invalid["transcript"] = "!TC1|row=at,e,part,t,p,d,k,c|z=Asia/Seoul\n260801-0900|2|1/1|T1|P1|in|text|첫 행\n"
    invalid["row_count"] = 1
    invalid["max_relations"] = 1
    #expect(throws: Error.self) {
        _ = try SemanticTriagePayload(object: invalid)
    }
}

@Test func semanticTriageInstructionsRejectMechanicalNaturalLanguageFiltering() {
    let instructions = semanticTriageInstructions(source: "kakaotalk")

    #expect(instructions.contains("not keyword matching"))
    #expect(instructions.contains("short acknowledgement, rejection, laughter"))
    #expect(instructions.contains("inspecting every row"))
}

@Test func semanticTriageMappingRequiresTheFullReviewedRowBarrier() throws {
    let payload = try SemanticTriagePayload(object: semanticTriagePayloadFixture())
    let relation = GeneratedSemanticRelation(
        kind: "reschedule",
        handles: [1, 2, 3],
        ambiguous: false
    )
    let mapped = try mapGeneratedSemanticTriage(
        GeneratedSemanticTriageBatch(
            reviewedRows: 3,
            relations: [relation]
        ),
        payload: payload
    )

    #expect(mapped["reviewed_rows"]?.intValue == 3)
    let relations = try #require(mapped["relations"]?.objects)
    #expect(relations.count == 1)
    #expect(relations[0]["kind"]?.stringValue == "reschedule")

    #expect(throws: GeneratedSemanticTriageError.self) {
        _ = try mapGeneratedSemanticTriage(
            GeneratedSemanticTriageBatch(
                reviewedRows: 2,
                relations: [relation]
            ),
            payload: payload
        )
    }
}

@Test func semanticTriageMappingRejectsInventedOrDuplicateHandles() throws {
    let payload = try SemanticTriagePayload(object: semanticTriagePayloadFixture())
    let invalid = GeneratedSemanticRelation(
        kind: "commitment",
        handles: [2, 2, 4],
        ambiguous: true
    )

    #expect(throws: GeneratedSemanticTriageError.self) {
        _ = try mapGeneratedSemanticTriage(
            GeneratedSemanticTriageBatch(
                reviewedRows: 3,
                relations: [invalid]
            ),
            payload: payload
        )
    }
}

@Test func generatedOutputCannotCiteEvidenceOutsideTheInput() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let generated = GeneratedPlanningBatch(
        events: [GeneratedEvent(
            title: "Synthetic meeting",
            start: "2026-08-02T10:00:00+09:00",
            end: "2026-08-02T11:00:00+09:00",
            notes: nil,
            location: nil,
            url: nil,
            timeZone: "Asia/Seoul",
            evidenceHandles: [2]
        )],
        reminders: []
    )
    #expect(throws: GeneratedPlanningError.self) {
        _ = try mapGeneratedPlanning(generated, payload: payload)
    }
}

@Test func filteringDropsInvalidIntermediateProposalAndKeepsValidOne() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let invalid = GeneratedEvent(
        title: "Ungrounded synthetic event",
        start: "2026-08-02T10:00:00+09:00",
        end: "2026-08-02T11:00:00+09:00",
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [2]
    )
    let valid = GeneratedEvent(
        title: "Grounded synthetic event",
        start: "2026-08-02T12:00:00+09:00",
        end: "2026-08-02T13:00:00+09:00",
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1]
    )

    let mapping = try mapGeneratedPlanningFilteringInvalid(
        GeneratedPlanningBatch(events: [invalid, valid], reminders: []),
        payload: payload
    )
    let proposals = try #require(mapping.suggestions["proposals"]?.objects)

    #expect(mapping.rejectedRules == ["evidence_reference"])
    #expect(proposals.count == 1)
    #expect(proposals[0]["proposal_id"]?.stringValue == "p002")
}

@Test func generatedOutputMapsToTheStrictPublicSuggestionContract() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let generated = GeneratedPlanningBatch(
        events: [GeneratedEvent(
            title: "Synthetic meeting",
            start: "2026-08-02T10:00:00+09:00",
            end: "2026-08-02T11:00:00+09:00",
            notes: "Bring the synthetic document",
            location: nil,
            url: nil,
            timeZone: "Asia/Seoul",
            evidenceHandles: [1],
        )],
        reminders: []
    )
    let result = try mapGeneratedPlanning(generated, payload: payload)
    #expect(result["schema"]?.stringValue == planningSuggestionSchema)
    let proposals = try #require(result["proposals"]?.objects)
    #expect(proposals.count == 1)
    #expect(proposals[0]["proposal_id"]?.stringValue == "p001")
    let action = try #require(proposals[0]["action"]?.objectValue)
    let event = try #require(action["payload"]?.objectValue)
    #expect(event["calendar_reference"] == nil)
}

@Test func ordinalGroundingMapsThroughTheExactAllowlist() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let generated = GeneratedPlanningBatch(
        events: [GeneratedEvent(
            title: "Synthetic meeting",
            start: "2026-08-02T10:00:00+09:00",
            end: "2026-08-02T11:00:00+09:00",
            notes: nil,
            location: nil,
            url: nil,
            timeZone: "Asia/Seoul",
            evidenceHandles: [1],
        )],
        reminders: []
    )

    let result = try mapGeneratedPlanning(generated, payload: payload)
    let proposals = try #require(result["proposals"]?.objects)
    let evidence = try #require(proposals[0]["evidence"]?.objects)

    #expect(evidence[0]["record_reference"]?.stringValue == "ctxm1_0000000000001")
    #expect(evidence[0]["revision_reference"]?.stringValue == "ctxr1_0000000000001")
}

@Test func ordinalHandleSelectsOneExactEvidencePair() throws {
    let payload = try AnalysisPayload(object: twoEvidencePayloadFixture())
    let reminder = GeneratedReminder(
        title: "Synthetic action",
        notes: nil,
        url: nil,
        due: nil,
        start: nil,
        evidenceHandles: [2]
    )

    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(events: [], reminders: [reminder]), payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    let evidence = try #require(proposals[0]["evidence"]?.objects)

    #expect(evidence.count == 1)
    #expect(evidence[0]["record_reference"]?.stringValue == "ctxm1_0000000000002")
}

@Test func duplicateOrdinalHandlesAreRejected() throws {
    let payload = try AnalysisPayload(object: twoEvidencePayloadFixture())
    let reminder = GeneratedReminder(
        title: "Synthetic action",
        notes: nil,
        url: nil,
        due: nil,
        start: nil,
        evidenceHandles: [1, 1]
    )

    #expect(throws: GeneratedPlanningError.self) {
        _ = try mapGeneratedPlanning(
            GeneratedPlanningBatch(events: [], reminders: [reminder]), payload: payload
        )
    }
}

@Test func modelTranscriptRemovesOpaqueEvidencePairs() throws {
    let payload = try AnalysisPayload(object: payloadObject())

    let transcript = try makeModelTranscript(payload).text

    #expect(transcript.contains("!CHAT1|"))
    #expect(transcript.contains("e=ordinal"))
    #expect(transcript.contains("B|1|synthetic"))
    #expect(!transcript.contains("E1"))
    #expect(!transcript.contains("ctxm1_"))
    #expect(!transcript.contains("0000000000001|0000000000001"))
}

@Test func mailModelTranscriptRemovesIdentifiersAndKeepsSubjectAndBody() throws {
    let payload = try AnalysisPayload(object: mailPayloadFixture())

    let transcript = try makeModelTranscript(payload)

    #expect(transcript.text.contains("!MAIL1|"))
    #expect(transcript.text.contains("Synthetic subject"))
    #expect(transcript.text.contains("Synthetic body"))
    #expect(transcript.text.contains("0900|1|M001"))
    #expect(!transcript.text.contains("mail1_"))
    #expect(!transcript.text.contains("mailr1_"))
    #expect(!transcript.text.contains("0000000000001|0000000000001"))
    #expect(transcript.evidenceContent[1] == "Synthetic subject\nSynthetic body")
}

@Test func freshChatTranscriptUsesOnlyOrdinalEvidenceInsideTheModelBoundary() throws {
    let payload = try AnalysisPayload(object: freshChatPayloadFixture())

    let transcript = try makeModelTranscript(payload)

    #expect(transcript.text.contains("!CHAT1|"))
    #expect(transcript.text.contains("row=at,evidence,thread,speaker,direction,kind,content"))
    #expect(transcript.text.contains("2026-08-01T09:00:00+09:00|1|T1|P1|in|text|Fresh chat body"))
    #expect(!transcript.text.contains("evi1_"))
    #expect(!transcript.text.contains("evr1_"))
    #expect(transcript.evidenceContent[1] == "Fresh chat body")
}

@Test func freshMailTranscriptUsesOnlyOrdinalEvidenceInsideTheModelBoundary() throws {
    let payload = try AnalysisPayload(object: freshMailPayloadFixture())

    let transcript = try makeModelTranscript(payload)

    #expect(transcript.text.contains("!MAIL1|"))
    #expect(transcript.text.contains("row=at,evidence,sender,subject,body"))
    #expect(transcript.text.contains("2026-08-01T09:00:00+09:00|1|P1|Fresh subject|Fresh body"))
    #expect(!transcript.text.contains("evi1_"))
    #expect(!transcript.text.contains("evr1_"))
    #expect(transcript.evidenceContent[1] == "Fresh subject\nFresh body")
}

@Test func chatModelTranscriptPreservesEscapedContentSemantics() throws {
    var object = payloadObject()
    object["transcript"] = "!CCT7|g=120|z=Asia/Seoul|r=ctxm1_|v=ctxr1_\nT|K001\nD|260801\nS|0900\nB|0000000000001|0000000000001|shared\\|piece\\nline\n"
    let payload = try AnalysisPayload(object: object)

    let transcript = try makeModelTranscript(payload)

    #expect(transcript.text.contains("B|1|shared\\|piece\\nline"))
    #expect(transcript.evidenceContent[1] == "shared|piece\nline")
}

@Test func datedAllDayEventGetsAnExclusiveNextDayBoundary() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let event = GeneratedAllDayEvent(
        title: "Synthetic delivery",
        startDate: "2026-08-01",
        endDateInclusive: nil,
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1],
    )

    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(allDayEvents: [event], events: [], reminders: []), payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    let action = try #require(proposals[0]["action"]?.objectValue)
    let mapped = try #require(action["payload"]?.objectValue)

    #expect(mapped["end"]?.stringValue == "2026-08-02T00:00:00+09:00")
}

@Test func allDayEventUsesTheUniqueGroundedDateInsteadOfAModelGuess() throws {
    var object = payloadObject()
    object["transcript"] = "!CCT7|g=120|z=Asia/Seoul|r=ctxm1_|v=ctxr1_\nT|K001\nD|260801\nS|0900\nB|0000000000001|0000000000001|synthetic delivery 8/1\n"
    let payload = try AnalysisPayload(object: object)
    let event = GeneratedAllDayEvent(
        title: "Synthetic delivery",
        startDate: "2026-08-02",
        endDateInclusive: nil,
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1]
    )

    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(allDayEvents: [event], events: [], reminders: []), payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    let action = try #require(proposals[0]["action"]?.objectValue)
    let mapped = try #require(action["payload"]?.objectValue)

    #expect(mapped["start"]?.stringValue == "2026-08-01T00:00:00+09:00")
    #expect(mapped["end"]?.stringValue == "2026-08-02T00:00:00+09:00")
}

@Test func allDayEventRejectsAnUnsupportedGuessWhenGroundedDatesAreAmbiguous() throws {
    var object = payloadObject()
    object["transcript"] = "!CCT7|g=120|z=Asia/Seoul|r=ctxm1_|v=ctxr1_\nT|K001\nD|260801\nS|0900\nB|0000000000001|0000000000001|synthetic options 8/1 or 8/2\n"
    let payload = try AnalysisPayload(object: object)
    let event = GeneratedAllDayEvent(
        title: "Synthetic delivery",
        startDate: "2026-08-03",
        endDateInclusive: nil,
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1]
    )

    #expect(throws: GeneratedPlanningError.self) {
        _ = try mapGeneratedPlanning(
            GeneratedPlanningBatch(allDayEvents: [event], events: [], reminders: []),
            payload: payload
        )
    }
}

@Test func allDayEventRejectsAnInvalidCalendarDate() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let event = GeneratedAllDayEvent(
        title: "Synthetic delivery",
        startDate: "2026-02-30",
        endDateInclusive: nil,
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1],
    )

    #expect(throws: GeneratedPlanningError.self) {
        _ = try mapGeneratedPlanning(
            GeneratedPlanningBatch(allDayEvents: [event], events: [], reminders: []),
            payload: payload
        )
    }
}

@Test func allDayBoundaryUsesCalendarDaysAcrossDST() throws {
    var object = payloadObject()
    object["timezone"] = "America/Los_Angeles"
    let payload = try AnalysisPayload(object: object)
    let event = GeneratedAllDayEvent(
        title: "Synthetic DST day",
        startDate: "2026-03-08",
        endDateInclusive: nil,
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "America/Los_Angeles",
        evidenceHandles: [1],
    )

    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(allDayEvents: [event], events: [], reminders: []), payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    let action = try #require(proposals[0]["action"]?.objectValue)
    let mapped = try #require(action["payload"]?.objectValue)

    #expect(mapped["start"]?.stringValue == "2026-03-08T00:00:00-08:00")
    #expect(mapped["end"]?.stringValue == "2026-03-09T00:00:00-07:00")
}

@Test func zeroDurationTimedEventRemainsInvalid() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let event = GeneratedEvent(
        title: "Synthetic timed event",
        start: "2026-08-01T10:00:00+09:00",
        end: "2026-08-01T10:00:00+09:00",
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1],
    )

    #expect(throws: GeneratedPlanningError.self) {
        _ = try mapGeneratedPlanning(
            GeneratedPlanningBatch(events: [event], reminders: []), payload: payload
        )
    }
}

@Test func timedEventUsesTheUniqueGroundedDateInsteadOfAModelGuess() throws {
    var object = payloadObject()
    object["transcript"] = "!CCT7|g=120|z=Asia/Seoul|r=ctxm1_|v=ctxr1_\nT|K001\nD|260801\nS|0900\nB|0000000000001|0000000000001|synthetic meeting 8/1 10:00 11:00\n"
    let payload = try AnalysisPayload(object: object)
    let event = GeneratedEvent(
        title: "Synthetic meeting",
        start: "2026-08-02T10:00:00+09:00",
        end: "2026-08-02T11:00:00+09:00",
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1]
    )

    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(events: [event], reminders: []), payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    let action = try #require(proposals[0]["action"]?.objectValue)
    let mapped = try #require(action["payload"]?.objectValue)

    #expect(mapped["start"]?.stringValue == "2026-08-01T10:00:00+09:00")
    #expect(mapped["end"]?.stringValue == "2026-08-01T11:00:00+09:00")
}

@Test func filteringRejectsTimedEventWhoseClockIsNotInGroundedContent() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let event = GeneratedEvent(
        title: "Unsupported clock",
        start: "2026-08-01T14:00:00+09:00",
        end: "2026-08-01T15:00:00+09:00",
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1]
    )

    let mapping = try mapGeneratedPlanningFilteringInvalid(
        GeneratedPlanningBatch(events: [event], reminders: []), payload: payload
    )
    let proposals = try #require(mapping.suggestions["proposals"]?.objects)

    #expect(proposals.isEmpty)
    #expect(mapping.rejectedRules == ["event_start_evidence"])
}

@Test func filteringRejectsAllDayEventWhoseDateIsNotInGroundedContent() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let event = GeneratedAllDayEvent(
        title: "Unsupported date",
        startDate: "2026-12-31",
        endDateInclusive: nil,
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        evidenceHandles: [1]
    )

    let mapping = try mapGeneratedPlanningFilteringInvalid(
        GeneratedPlanningBatch(allDayEvents: [event], events: [], reminders: []), payload: payload
    )
    let proposals = try #require(mapping.suggestions["proposals"]?.objects)

    #expect(proposals.isEmpty)
    #expect(mapping.rejectedRules == ["all_day_start_evidence"])
}

@Test func noSupportedPlanningItemIsAValidResult() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(events: [], reminders: []),
        payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    #expect(proposals.isEmpty)
}

@Test func explicitScheduleMapsToProviderNeutralAlarmAndRecurrence() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let event = GeneratedEvent(
        title: "Weekly synthetic meeting",
        start: "2026-08-03T10:00:00+09:00",
        end: "2026-08-03T11:00:00+09:00",
        notes: nil,
        location: nil,
        url: nil,
        timeZone: "Asia/Seoul",
        schedule: GeneratedSchedule(
            alarmAt: [],
            alarmMinutesBefore: [15],
            recurrence: GeneratedRecurrence(
                frequency: "weekly",
                interval: 1,
                daysOfWeek: ["MO"],
                daysOfMonth: [],
                monthsOfYear: [],
                weeksOfYear: [],
                daysOfYear: [],
                setPositions: [],
                until: nil,
                occurrenceCount: 4
            )
        ),
        evidenceHandles: [1],
    )
    let result = try mapGeneratedPlanning(
        GeneratedPlanningBatch(events: [event], reminders: []), payload: payload
    )
    let proposals = try #require(result["proposals"]?.objects)
    let action = try #require(proposals[0]["action"]?.objectValue)
    let mapped = try #require(action["payload"]?.objectValue)
    let alarms = try #require(mapped["alarms"]?.objects)
    let rules = try #require(mapped["recurrence_rules"]?.objects)
    #expect(alarms[0]["offset_seconds"]?.intValue == -900)
    #expect(rules[0]["frequency"]?.stringValue == "weekly")
    #expect((rules[0]["end"]?.objectValue)?["count"]?.intValue == 4)
}

@Test func liteAllDayEventMapsThroughTheStrictGroundedContract() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let generated = GeneratedPlanningLiteBatch(
        proposals: [.allDayEvent(GeneratedLiteAllDayEvent(
            title: "Synthetic all-day event",
            startDate: "2026-08-01",
            endDateInclusive: nil,
            notes: nil,
            location: nil,
            url: nil,
            schedule: nil,
            evidenceHandles: [1]
        ))]
    )

    let mapping = try mapGeneratedPlanningLiteFilteringInvalid(
        generated,
        payload: payload,
        modelTranscript: makeModelTranscript(payload)
    )
    let proposals = try #require(mapping.suggestions["proposals"]?.objects)
    let action = try #require(proposals.first?["action"]?.objectValue)
    let event = try #require(action["payload"]?.objectValue)

    #expect(action["kind"]?.stringValue == "create_event")
    #expect(event["start"]?.stringValue == "2026-08-01T00:00:00+09:00")
    #expect(event["end"]?.stringValue == "2026-08-02T00:00:00+09:00")
}

@Test func liteReminderConvertsCompactRecurrenceSelectors() throws {
    let payload = try AnalysisPayload(object: payloadObject())
    let generated = GeneratedPlanningLiteBatch(
        proposals: [.reminder(GeneratedLiteReminder(
            title: "Synthetic recurring action",
            notes: nil,
            url: nil,
            due: "2026-08-03",
            start: nil,
            schedule: GeneratedLiteSchedule(
                alarmAt: [],
                alarmMinutesBefore: [15],
                recurrence: GeneratedLiteRecurrence(
                    frequency: "weekly",
                    interval: 1,
                    selectors: ["MO"],
                    until: nil,
                    occurrenceCount: 4
                )
            ),
            evidenceHandles: [1]
        ))]
    )

    let mapping = try mapGeneratedPlanningLiteFilteringInvalid(
        generated,
        payload: payload,
        modelTranscript: makeModelTranscript(payload)
    )
    let proposals = try #require(mapping.suggestions["proposals"]?.objects)
    let action = try #require(proposals.first?["action"]?.objectValue)
    let reminder = try #require(action["payload"]?.objectValue)
    let recurrence = try #require(reminder["recurrence_rules"]?.objects)

    #expect(action["kind"]?.stringValue == "create_reminder")
    #expect((reminder["due"]?.objectValue)?["year"]?.intValue == 2026)
    #expect(recurrence.first?["frequency"]?.stringValue == "weekly")
    let days = try #require(recurrence.first?["days_of_week"]?.objects)
    #expect(days.first?["day_of_week"]?.intValue == 2)
    #expect(days.first?["week_number"]?.intValue == 0)
    #expect((recurrence.first?["end"]?.objectValue)?["count"]?.intValue == 4)
}

private func payloadObject() -> JSONObject {
    [
        "schema": .string(contextAnalysisSchema),
        "analysis_id": "analysis-test",
        "source": "kakaotalk",
        "transcript": "!CCT7|g=120|z=Asia/Seoul|r=ctxm1_|v=ctxr1_\nT|K001\nD|260801\nS|0900\nB|0000000000001|0000000000001|synthetic 8/1 8/2 8/3 3/8 10:00 11:00 12:00 13:00\n",
        "timezone": "Asia/Seoul",
        "reference_time": "2026-08-01T00:00:00+09:00",
        "max_proposals": 8,
        "evidence": [[
            "record_reference": "ctxm1_0000000000001",
            "revision_reference": "ctxr1_0000000000001",
        ]],
    ]
}

private func twoEvidencePayloadFixture() -> JSONObject {
    [
        "schema": .string(contextAnalysisSchema),
        "analysis_id": "analysis-two-evidence",
        "source": "kakaotalk",
        "transcript": "!CCT7|g=120|z=Asia/Seoul|r=ctxm1_|v=ctxr1_\nT|K001\nD|260801\nS|0900\nB|0000000000001|0000000000001|shared alpha\nB|0000000000002|0000000000002|shared beta unique\n",
        "timezone": "Asia/Seoul",
        "reference_time": "2026-08-01T00:00:00+09:00",
        "max_proposals": 8,
        "evidence": [
            [
                "record_reference": "ctxm1_0000000000001",
                "revision_reference": "ctxr1_0000000000001",
            ],
            [
                "record_reference": "ctxm1_0000000000002",
                "revision_reference": "ctxr1_0000000000002",
            ],
        ],
    ]
}

private func mailPayloadFixture() -> JSONObject {
    [
        "schema": .string(contextAnalysisSchema),
        "analysis_id": "analysis-mail",
        "source": "mail",
        "transcript": "!MCT2|z=Asia/Seoul|r=mail1_|v=mailr1_|row=received,ref,revision,thread,sent,from,to,cc,bcc,subject,mailbox,body,truncated,attachments\nD|260801\n0900|0000000000001|0000000000001|M001|260801-0859|A001|A002|-|-|Synthetic subject|Inbox|Synthetic body|0|-\n",
        "timezone": "Asia/Seoul",
        "reference_time": "2026-08-01T00:00:00+09:00",
        "max_proposals": 8,
        "evidence": [[
            "record_reference": "mail1_0000000000001",
            "revision_reference": "mailr1_0000000000001",
        ]],
    ]
}

private func freshChatPayloadFixture() -> JSONObject {
    [
        "schema": .string(contextAnalysisSchema),
        "analysis_id": "analysis-fresh-chat",
        "source": "kakaotalk",
        "transcript": "!FCHAT1|z=Asia/Seoul|row=at,ref,revision,thread,speaker,direction,kind,content\n2026-08-01T09:00:00+09:00|evi1_0000000000001|evr1_0000000000001|T1|P1|in|text|Fresh chat body\n",
        "timezone": "Asia/Seoul",
        "reference_time": "2026-08-01T09:00:00+09:00",
        "max_proposals": 8,
        "evidence": [[
            "record_reference": "evi1_0000000000001",
            "revision_reference": "evr1_0000000000001",
        ]],
    ]
}

private func freshMailPayloadFixture() -> JSONObject {
    [
        "schema": .string(contextAnalysisSchema),
        "analysis_id": "analysis-fresh-mail",
        "source": "mail",
        "transcript": "!FMAIL1|z=Asia/Seoul|row=at,ref,revision,sender,subject,body\n2026-08-01T09:00:00+09:00|evi1_0000000000001|evr1_0000000000001|P1|Fresh subject|Fresh body\n",
        "timezone": "Asia/Seoul",
        "reference_time": "2026-08-01T09:00:00+09:00",
        "max_proposals": 8,
        "evidence": [[
            "record_reference": "evi1_0000000000001",
            "revision_reference": "evr1_0000000000001",
        ]],
    ]
}

private func semanticTriagePayloadFixture() -> JSONObject {
    [
        "schema": .string(contextSemanticTriageRequestSchema),
        "analysis_id": "analysis-triage",
        "chunk_id": "chunk-0001",
        "source": "kakaotalk",
        "transcript": "!TC1|row=at,e,part,t,p,d,k,c|z=Asia/Seoul\n260801-0900|1|1/1|T1|P1|in|text|다음 주에 만나자\n260801-0901|2|1/1|T1|P2|in|text|아니 다다음 주로 바꾸자\n260801-0902|3|1/1|T1|ME|out|text|넵\n",
        "timezone": "Asia/Seoul",
        "reference_time": "2026-08-01T09:00:00+09:00",
        "row_count": 3,
        "max_relations": 3,
    ]
}
