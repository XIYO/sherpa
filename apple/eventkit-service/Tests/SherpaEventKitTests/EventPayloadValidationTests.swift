import SherpaPlannerApplication
import SherpaPlannerContract
import Testing

@Test func eventValidatorRejectsInvalidCommandsBeforeNativeInvocation() throws {
    let validator = EventCommandValidator()
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(EventCreateRequest(
            schema: "sherpa.planner.event-create.request.v2", title: " ",
            start: "2027-01-01T01:00:00Z", end: "2027-01-01T00:00:00Z",
            allDay: false, collectionNativeLocator: nil, notes: nil, location: nil,
            url: nil, timeZone: nil, alarms: nil, recurrenceRules: nil
        ))
    }
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(EventListRequest(
            schema: "sherpa.planner.event-list.request.v2", from: "bad", to: "bad",
            limit: 0, collectionNativeLocator: nil
        ))
    }
}

@Test func eventUpdateRejectsEmptyAndClearRequiredPatch() throws {
    let validator = EventCommandValidator()
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(EventUpdateRequest(
            schema: "sherpa.planner.event-update.request.v2", nativeLocator: "missing",
            span: "this", changes: EventPatch()
        ))
    }
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(EventUpdateRequest(
            schema: "sherpa.planner.event-update.request.v2", nativeLocator: "missing",
            span: "this", changes: EventPatch(title: .clear)
        ))
    }
}

@Test func reminderValidatorRejectsInvalidCommandsBeforeNativeInvocation() throws {
    let validator = ReminderCommandValidator()
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(ReminderCreateRequest(
            schema: "sherpa.planner.reminder-create.request.v2", title: "",
            collectionNativeLocator: nil, notes: nil, url: nil, priority: 10,
            due: nil, start: nil, alarms: nil, recurrenceRules: nil
        ))
    }
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(ReminderListRequest(
            schema: "sherpa.planner.reminder-list.request.v2",
            collectionNativeLocator: nil, limit: 0, completed: nil
        ))
    }
}

@Test func reminderUpdatePatchPreservesClearAndRejectsEmpty() throws {
    let validator = ReminderCommandValidator()
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(ReminderUpdateRequest(
            schema: "sherpa.planner.reminder-update.request.v2", nativeLocator: "missing",
            changes: ReminderPatch()
        ))
    }
    try validator.validate(ReminderUpdateRequest(
        schema: "sherpa.planner.reminder-update.request.v2", nativeLocator: "missing",
        changes: ReminderPatch(notes: .clear)
    ))
}

@Test func validatorsAcceptUTCGMTAliasesAndValidListFilters() throws {
    let event = EventCommandValidator()
    for zone in ["UTC", "GMT"] {
        try event.validate(EventCreateRequest(
            schema: "sherpa.planner.event-create.request.v2", title: "Alias",
            start: "2027-01-01T00:00:00Z", end: "2027-01-01T01:00:00Z",
            allDay: false, collectionNativeLocator: "collection", notes: nil, location: nil,
            url: nil, timeZone: zone, alarms: nil, recurrenceRules: nil
        ))
    }
    try ReminderCommandValidator().validate(ReminderListRequest(
        schema: "sherpa.planner.reminder-list.request.v2",
        collectionNativeLocator: "collection", limit: 10_000, completed: false
    ))
}
