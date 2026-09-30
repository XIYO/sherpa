import Foundation

/// Parses the RFC 3339 forms accepted by Sherpa's
/// public contracts. `ISO8601DateFormatter` does not accept fractional seconds
/// unless that option is selected explicitly, so both valid forms are tried.
func parseRFC3339(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }

    let wholeSeconds = ISO8601DateFormatter()
    wholeSeconds.formatOptions = [.withInternetDateTime]
    return wholeSeconds.date(from: value)
}
