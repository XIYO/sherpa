import SherpaWorkerProtocol
@preconcurrency import EventKit
import Foundation

private struct EventOccurrenceKey: Hashable {
    let calendarIdentifier: String
    let seriesIdentifier: String
    let occurrenceDay: DateComponents
}

/// EventKit can return both the recurring-series occurrence and its detached
/// exception for the same logical occurrence. EventKit identifies a detached
/// occurrence by adding an `/RID=` suffix to the series event identifier.
/// Floating all-day occurrences are returned in the default time zone, so
/// compare the occurrence's local calendar day rather than its absolute
/// `Date` value. Keep the exception because it is what EventKit mutates when
/// the caller addresses that date.
func deduplicatedEventOccurrences(_ events: [EKEvent]) -> [EKEvent] {
    deduplicatingOccurrences(
        events,
        key: { event -> EventOccurrenceKey? in
            let seriesIdentifier = event.eventIdentifier?
                .components(separatedBy: "/RID=")
                .first ?? ""
            guard !seriesIdentifier.isEmpty else {
                return nil
            }
            let occurrenceDay = Calendar.current.dateComponents(
                [.year, .month, .day], from: event.occurrenceDate ?? event.startDate
            )
            return EventOccurrenceKey(
                calendarIdentifier: event.calendar.calendarIdentifier,
                seriesIdentifier: seriesIdentifier,
                occurrenceDay: occurrenceDay
            )
        },
        shouldReplace: { candidate, existing in
            candidate.isDetached && !existing.isDetached
        }
    )
}

func deduplicatingOccurrences<Value, Key: Hashable>(
    _ values: [Value],
    key: (Value) -> Key?,
    shouldReplace: (Value, Value) -> Bool
) -> [Value] {
    var indexes = [Key: Int]()
    var result = [Value]()

    for value in values {
        guard let key = key(value) else {
            result.append(value)
            continue
        }
        if let index = indexes[key] {
            if shouldReplace(value, result[index]) {
                result[index] = value
            }
        } else {
            indexes[key] = result.endIndex
            result.append(value)
        }
    }
    return result
}
