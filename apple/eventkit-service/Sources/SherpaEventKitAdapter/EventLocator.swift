import SherpaWorkerProtocol
@preconcurrency import EventKit
import Foundation

struct EventLocator: Equatable {
    private static let prefix = "ekev1"

    let eventIdentifier: String
    let occurrenceDate: Date?
    let observedStartDate: Date?

    init(eventIdentifier: String, occurrenceDate: Date?, observedStartDate: Date?) {
        self.eventIdentifier = eventIdentifier
        self.occurrenceDate = occurrenceDate
        self.observedStartDate = observedStartDate
    }

    init(event: EKEvent) throws {
        guard let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty else {
            throw WorkerProtocolError.invalidPayload
        }
        self.init(
            eventIdentifier: eventIdentifier,
            occurrenceDate: event.occurrenceDate,
            observedStartDate: event.startDate
        )
    }

    init(wireValue: String) throws {
        guard !wireValue.isEmpty, wireValue.utf8.count <= 4_096, !wireValue.contains("\0") else {
            throw WorkerProtocolError.invalidPayload
        }
        guard wireValue.hasPrefix(Self.prefix + ":") else {
            throw WorkerProtocolError.invalidPayload
        }
        let components = wireValue.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == Substring(Self.prefix),
              let identifier = Self.decode(String(components[1])),
              !identifier.isEmpty
        else { throw WorkerProtocolError.invalidPayload }
        let occurrence = try Self.decodeDate(String(components[2]))
        let observedStart = try Self.decodeDate(String(components[3]))
        guard observedStart != nil else { throw WorkerProtocolError.invalidPayload }
        self.init(
            eventIdentifier: identifier,
            occurrenceDate: occurrence,
            observedStartDate: observedStart
        )
    }

    var wireValue: String {
        [
            Self.prefix,
            Self.encode(eventIdentifier),
            occurrenceDate.map(Self.encodeDate) ?? "-",
            observedStartDate.map(Self.encodeDate) ?? "-",
        ].joined(separator: ":")
    }

    func matches(_ event: EKEvent) -> Bool {
        guard event.eventIdentifier == eventIdentifier else { return false }
        return switch (occurrenceDate, event.occurrenceDate) {
        case (nil, nil): true
        case let (expected?, actual?): abs(expected.timeIntervalSince(actual)) < 0.001
        default: false
        }
    }

    private static func encodeDate(_ value: Date) -> String {
        encode(makeFormatter().string(from: value))
    }

    private static func decodeDate(_ value: String) throws -> Date? {
        guard value != "-" else { return nil }
        guard let decoded = decode(value), let date = makeFormatter().date(from: decoded) else {
            throw WorkerProtocolError.invalidPayload
        }
        return date
    }

    private static func encode(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ value: String) -> String? {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else { return nil }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
