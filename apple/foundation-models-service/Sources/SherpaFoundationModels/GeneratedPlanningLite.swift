import Foundation
import FoundationModels

/// Small generation grammar for the on-device model. It is converted into the
/// existing strict planning mapper before crossing the worker boundary.
@Generable
struct GeneratedPlanningLiteBatch {
    @Guide(description: "At most two grounded planning proposals in importance order.", .maximumCount(2))
    var proposals: [GeneratedLiteProposal]
}

/// A single union keeps the maximum proposal count in the generation grammar
/// itself. Three independent arrays cannot express a limit on their sum.
@Generable
enum GeneratedLiteProposal {
    case allDayEvent(GeneratedLiteAllDayEvent)
    case event(GeneratedLiteEvent)
    case reminder(GeneratedLiteReminder)
}

@Generable
struct GeneratedLiteAllDayEvent {
    var title: String
    @Guide(description: "Explicit YYYY-MM-DD start date.")
    var startDate: String
    @Guide(description: "Optional explicit inclusive YYYY-MM-DD final date.")
    var endDateInclusive: String?
    var notes: String?
    var location: String?
    var url: String?
    var schedule: GeneratedLiteSchedule?
    @Guide(description: "One-based evidence handles.", .count(1 ... 4))
    var evidenceHandles: [Int]
}

@Generable
struct GeneratedLiteEvent {
    var title: String
    @Guide(description: "Explicit RFC 3339 start with numeric offset.")
    var start: String
    @Guide(description: "Explicit later RFC 3339 end with numeric offset.")
    var end: String
    var notes: String?
    var location: String?
    var url: String?
    var schedule: GeneratedLiteSchedule?
    @Guide(description: "One-based evidence handles.", .count(1 ... 4))
    var evidenceHandles: [Int]
}

@Generable
struct GeneratedLiteReminder {
    var title: String
    var notes: String?
    var url: String?
    @Guide(description: "Optional explicit YYYY-MM-DD or RFC 3339 due value.")
    var due: String?
    @Guide(description: "Optional explicit YYYY-MM-DD or RFC 3339 start value.")
    var start: String?
    var schedule: GeneratedLiteSchedule?
    @Guide(description: "One-based evidence handles.", .count(1 ... 4))
    var evidenceHandles: [Int]
}

@Generable
struct GeneratedLiteSchedule {
    @Guide(description: "Explicit RFC 3339 alarm times.", .maximumCount(4))
    var alarmAt: [String]
    @Guide(description: "Explicit nonnegative minutes before.", .maximumCount(4))
    var alarmMinutesBefore: [Int]
    var recurrence: GeneratedLiteRecurrence?
}

@Generable
struct GeneratedLiteRecurrence {
    @Guide(description: "daily, weekly, monthly, or yearly.")
    var frequency: String
    @Guide(description: "Positive interval.", .range(1 ... 10_000))
    var interval: Int
    @Guide(description: "Compact selectors: weekday MO; month-day 25; month M8; week W2; year-day D120.", .maximumCount(16))
    var selectors: [String]
    @Guide(description: "Optional RFC 3339 end.")
    var until: String?
    var occurrenceCount: Int?
}

enum GeneratedPlanningLiteError: Error {
    case proposalLimit
    case reminderDate
    case recurrence

    var ruleCode: String {
        switch self {
        case .proposalLimit: "lite_proposal_limit"
        case .reminderDate: "lite_reminder_date"
        case .recurrence: "lite_recurrence"
        }
    }
}

func mapGeneratedPlanningLiteFilteringInvalid(
    _ generated: GeneratedPlanningLiteBatch,
    payload: AnalysisPayload,
    modelTranscript: ModelTranscript
) throws -> GeneratedPlanningMapping {
    guard generated.proposals.count <= payload.maximumProposals else {
        throw GeneratedPlanningLiteError.proposalLimit
    }
    var rejected = [String]()
    var allDayEvents = [GeneratedAllDayEvent]()
    var events = [GeneratedEvent]()
    var reminders = [GeneratedReminder]()
    for proposal in generated.proposals {
        do {
            switch proposal {
            case .allDayEvent(let value):
                allDayEvents.append(try convert(value, payload: payload))
            case .event(let value):
                events.append(try convert(value, payload: payload))
            case .reminder(let value):
                reminders.append(try convert(value, payload: payload))
            }
        } catch let error as GeneratedPlanningLiteError {
            rejected.append(error.ruleCode)
        } catch {
            rejected.append("lite_conversion")
        }
    }
    let mapping = try mapGeneratedPlanningFilteringInvalid(
        GeneratedPlanningBatch(
            allDayEvents: allDayEvents,
            events: events,
            reminders: reminders
        ),
        payload: payload,
        modelTranscript: modelTranscript
    )
    return GeneratedPlanningMapping(
        suggestions: mapping.suggestions,
        rejectedRules: rejected + mapping.rejectedRules
    )
}

private func convert(
    _ value: GeneratedLiteAllDayEvent,
    payload: AnalysisPayload
) throws -> GeneratedAllDayEvent {
    GeneratedAllDayEvent(
        title: value.title,
        startDate: value.startDate,
        endDateInclusive: value.endDateInclusive,
        notes: value.notes,
        location: value.location,
        url: value.url,
        timeZone: payload.timezone,
        schedule: try convert(value.schedule),
        evidenceHandles: value.evidenceHandles
    )
}

private func convert(
    _ value: GeneratedLiteEvent,
    payload: AnalysisPayload
) throws -> GeneratedEvent {
    GeneratedEvent(
        title: value.title,
        start: value.start,
        end: value.end,
        notes: value.notes,
        location: value.location,
        url: value.url,
        timeZone: payload.timezone,
        schedule: try convert(value.schedule),
        evidenceHandles: value.evidenceHandles
    )
}

private func convert(
    _ value: GeneratedLiteReminder,
    payload: AnalysisPayload
) throws -> GeneratedReminder {
    GeneratedReminder(
        title: value.title,
        notes: value.notes,
        url: value.url,
        due: try value.due.map { try reminderDate($0, timezone: payload.timezone) },
        start: try value.start.map { try reminderDate($0, timezone: payload.timezone) },
        schedule: try convert(value.schedule),
        evidenceHandles: value.evidenceHandles
    )
}

private func convert(_ value: GeneratedLiteSchedule?) throws -> GeneratedSchedule? {
    guard let value else { return nil }
    return GeneratedSchedule(
        alarmAt: value.alarmAt,
        alarmMinutesBefore: value.alarmMinutesBefore,
        recurrence: try value.recurrence.map(convert)
    )
}

private func convert(_ value: GeneratedLiteRecurrence) throws -> GeneratedRecurrence {
    let frequency = value.frequency.lowercased()
    guard ["daily", "weekly", "monthly", "yearly"].contains(frequency) else {
        throw GeneratedPlanningLiteError.recurrence
    }
    var weekdays = [String]()
    var monthDays = [Int]()
    var months = [Int]()
    var weeks = [Int]()
    var yearDays = [Int]()
    for selector in value.selectors {
        if selector.hasPrefix("M"), let month = Int(selector.dropFirst()) {
            months.append(month)
        } else if selector.hasPrefix("W"), let week = Int(selector.dropFirst()) {
            weeks.append(week)
        } else if selector.hasPrefix("D"), let day = Int(selector.dropFirst()) {
            yearDays.append(day)
        } else if let day = Int(selector) {
            monthDays.append(day)
        } else {
            weekdays.append(selector)
        }
    }
    return GeneratedRecurrence(
        frequency: frequency,
        interval: value.interval,
        daysOfWeek: weekdays,
        daysOfMonth: monthDays,
        monthsOfYear: months,
        weeksOfYear: weeks,
        daysOfYear: yearDays,
        setPositions: [],
        until: value.until,
        occurrenceCount: value.occurrenceCount
    )
}

private func reminderDate(_ value: String, timezone: String) throws -> GeneratedReminderDate {
    if value.count == 10 {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { throw GeneratedPlanningLiteError.reminderDate }
        return GeneratedReminderDate(
            year: year,
            month: month,
            day: day,
            hour: nil,
            minute: nil,
            second: nil,
            timeZone: timezone
        )
    }
    guard let date = parseRFC3339(value), let zone = TimeZone(identifier: timezone) else {
        throw GeneratedPlanningLiteError.reminderDate
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day,
          let hour = parts.hour, let minute = parts.minute, let second = parts.second
    else { throw GeneratedPlanningLiteError.reminderDate }
    return GeneratedReminderDate(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        timeZone: timezone
    )
}
