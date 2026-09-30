import EventKit
import Foundation
import SherpaPlannerContract
import Testing
@testable import SherpaEventKitAdapter

@Test func mapsTypedAbsoluteAndRelativeAlarms() throws {
    let mapped = try eventKitAlarms([
        .absolute(date: "2026-08-01T00:00:00Z"), .relative(offsetSeconds: -900),
    ])
    let alarms = try #require(mapped)
    #expect(alarms.count == 2)
    #expect(alarms[0].absoluteDate != nil)
    #expect(alarms[1].relativeOffset == -900)
}

@Test func mapsTypedAdvancedMonthlyRecurrence() throws {
    let mapped = try eventKitRecurrenceRules([.init(
        frequency: "monthly", interval: 2,
        daysOfWeek: [.init(dayOfWeek: 2, weekNumber: -1)], daysOfMonth: nil,
        monthsOfYear: nil, weeksOfYear: nil, daysOfYear: nil, setPositions: [-1],
        end: .init(kind: "count", date: nil, count: 8)
    )])
    let rules = try #require(mapped)
    #expect(rules.count == 1)
    #expect(rules[0].frequency == .monthly)
    #expect(rules[0].interval == 2)
    #expect(rules[0].daysOfTheWeek?.first?.weekNumber == -1)
    #expect(rules[0].recurrenceEnd?.occurrenceCount == 8)
}

@Test func mapsAllRecurrenceEndVariants() throws {
    let date = "2027-01-01T00:00:00Z"
    let variants: [(EventRecurrenceEnd?, Int, Date?)] = [
        (nil, 0, nil),
        (.init(kind: "count", date: nil, count: 5), 5, nil),
        (.init(kind: "date", date: date, count: nil), 0, parseDate(date)),
    ]
    for (end, count, expectedDate) in variants {
        let mapped = try eventKitRecurrenceRules([.init(
            frequency: "daily", interval: 1, daysOfWeek: nil, daysOfMonth: nil,
            monthsOfYear: nil, weeksOfYear: nil, daysOfYear: nil, setPositions: nil, end: end
        )])
        let rule = try #require(mapped?.first)
        #expect(rule.recurrenceEnd?.occurrenceCount ?? 0 == count)
        #expect(rule.recurrenceEnd?.endDate == expectedDate)
    }
}

@Test func rejectsInvalidTypedScheduleRepresentations() {
    #expect(throws: (any Error).self) { _ = try eventKitAlarms([.absolute(date: "bad")]) }
    #expect(throws: (any Error).self) {
        _ = try eventKitRecurrenceRules([.init(
            frequency: "unknown", interval: 1, daysOfWeek: nil, daysOfMonth: nil,
            monthsOfYear: nil, weeksOfYear: nil, daysOfYear: nil, setPositions: nil, end: nil
        )])
    }
}

@Test func typedCollectionFieldDistinguishesAbsentAndValue() {
    let absent: SnapshotField<[AlarmSnapshot]> = collectionField(nil)
    let empty: SnapshotField<[AlarmSnapshot]> = collectionField([])
    let value: SnapshotField<[AlarmSnapshot]> = collectionField([.init(
        absoluteDate: nil, relativeOffsetSeconds: -60, proximity: "none", structuredLocation: nil
    )])
    #expect(absent.state == "absent")
    #expect(empty.state == "absent")
    #expect(value.state == "value")
}
