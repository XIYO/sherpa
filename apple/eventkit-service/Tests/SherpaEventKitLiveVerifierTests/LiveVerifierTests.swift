import Foundation
import Testing
@testable import SherpaEventKitLiveVerifierSupport

@Test func liveVerifierRejectsMissingWriteGate() {
    #expect(throws: LiveVerifierError.liveGate) {
        _ = try LiveVerifierConfiguration.parse(
            arguments: ["--worker", "/bin/echo"], environment: [:]
        )
    }
}

@Test func liveVerifierRejectsAnIncorrectConfirmation() {
    #expect(throws: LiveVerifierError.liveGate) {
        _ = try LiveVerifierConfiguration.parse(
            arguments: ["--worker", "/bin/echo"],
            environment: [
                "SHERPA_EVENTKIT_LIVE": "1",
                "SHERPA_EVENTKIT_LIVE_CONFIRM": "no",
            ]
        )
    }
}

@Test func liveVerifierRequiresExactlyOneWorkerArgument() {
    #expect(throws: LiveVerifierError.usage) {
        _ = try LiveVerifierConfiguration.parse(
            arguments: [],
            environment: [
                "SHERPA_EVENTKIT_LIVE": "1",
                "SHERPA_EVENTKIT_LIVE_CONFIRM": LiveVerifierConfiguration.confirmation,
            ]
        )
    }
}

@Test func liveVerifierAcceptsAnExecutableWorkerAfterExplicitGate() throws {
    let configuration = try LiveVerifierConfiguration.parse(
        arguments: ["--worker", "/bin/echo"],
        environment: [
            "SHERPA_EVENTKIT_LIVE": "1",
            "SHERPA_EVENTKIT_LIVE_CONFIRM": LiveVerifierConfiguration.confirmation,
        ]
    )
    #expect(configuration.workerPath == "/bin/echo")
    #expect(configuration.mode == .disposable)
    #expect(configuration.successSuite == "eventkit-disposable-calendar-and-reminder")
}

@Test func liveVerifierAuthorizationUnavailableModeRequiresItsOwnConfirmation() throws {
    let configuration = try LiveVerifierConfiguration.parse(
        arguments: [
            "--worker", "/bin/echo", "--expect-authorization-unavailable", "calendar",
        ],
        environment: [
            "SHERPA_EVENTKIT_LIVE": "1",
            "SHERPA_EVENTKIT_LIVE_CONFIRM":
                LiveVerifierConfiguration.authorizationUnavailableConfirmation,
        ]
    )
    #expect(configuration.mode == .authorizationUnavailable(.calendar))
    #expect(configuration.successSuite == "eventkit-authorization-unavailable-calendar")
}

@Test func liveVerifierReadOnlyModeRequiresOneOpaqueCalendarReference() throws {
    let configuration = try LiveVerifierConfiguration.parse(
        arguments: ["--worker", "/bin/echo", "--verify-read-only-calendar"],
        environment: [
            "SHERPA_EVENTKIT_LIVE": "1",
            "SHERPA_EVENTKIT_LIVE_CONFIRM": LiveVerifierConfiguration.readOnlyConfirmation,
            "SHERPA_EVENTKIT_READ_ONLY_CALENDAR_REFERENCE": "calendar-ref",
        ]
    )
    #expect(configuration.mode == .readOnlyCalendar(calendarReference: "calendar-ref"))
    #expect(configuration.successSuite == "eventkit-read-only-calendar")

    #expect(throws: LiveVerifierError.usage) {
        _ = try LiveVerifierConfiguration.parse(
            arguments: ["--worker", "/bin/echo", "--verify-read-only-calendar"],
            environment: [
                "SHERPA_EVENTKIT_LIVE": "1",
                "SHERPA_EVENTKIT_LIVE_CONFIRM": LiveVerifierConfiguration.readOnlyConfirmation,
            ]
        )
    }
}

@Test func liveVerifierFailureKeepsTheStableCodeStageAndSafeMismatch() {
    let failure = LiveVerifierFailure(
        stage: .futureReadback,
        error: .verificationFailed,
        mismatch: LiveVerifierMismatch(field: .start, expected: "2026-08-26T00:00:00Z", actual: "2026-08-26T01:00:00Z")
    )

    #expect(failure.stableCode == "live_verifier.verification_failed")
    #expect(failure.stage.rawValue == "future_readback")
    #expect(failure.mismatch == LiveVerifierMismatch(
        field: .start, expected: "2026-08-26T00:00:00Z", actual: "2026-08-26T01:00:00Z"
    ))
}

@Test func exactOccurrencesSelectsTheDetachedExceptionForTheRequestedOccurrenceDate() {
    let day = ISO8601DateFormatter().date(from: "2026-08-20T00:00:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let events: [EventSnapshot] = [
        eventOccurrence("series-occurrence", at: "2026-08-20T00:00:00Z"),
        eventOccurrence("detached-exception", at: "2026-08-20T00:00:00Z", detached: true),
        eventOccurrence("neighboring-occurrence", at: "2026-08-21T00:00:00Z"),
    ]

    let selected = exactOccurrences(events, on: day, calendar: calendar)

    #expect(selected.count == 1)
    #expect(selected[0].nativeLocator == "detached-exception")
}

@Test func exactOccurrencesMatchesAFloatingAllDayOccurrenceByItsLocalDay() {
    let day = ISO8601DateFormatter().date(from: "2026-08-30T15:00:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let events = [eventOccurrence("future-occurrence", at: "2026-08-31T00:00:00Z")]

    let selected = exactOccurrences(events, on: day, calendar: calendar)

    #expect(selected.map(\.nativeLocator) == ["future-occurrence"])
}

private func eventOccurrence(_ nativeLocator: String, at occurrenceDate: String, detached: Bool = false) -> EventSnapshot {
    EventSnapshot(
        nativeLocator: nativeLocator,
        eventCollection: EventCollectionSnapshot(
            nativeLocator: "collection", title: "Synthetic", type: "local",
            allowsContentModifications: true
        ),
        title: "Synthetic", start: occurrenceDate, end: occurrenceDate,
        allDay: true, timeZone: nil,
        notes: SnapshotField(nil), location: SnapshotField(nil), url: SnapshotField(nil),
        occurrenceDate: occurrenceDate, detached: detached, status: "confirmed",
        availability: "not_supported", alarms: SnapshotField([]), recurrenceRules: SnapshotField([])
    )
}
