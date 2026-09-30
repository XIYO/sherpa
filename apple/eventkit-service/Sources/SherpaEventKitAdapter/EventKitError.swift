import SherpaWorkerProtocol
@preconcurrency import EventKit
import Foundation

enum EventKitWorkerError: Error {
    case notFound
    case readOnlyDestination
    case accessUnavailable
    case verificationFailed
}

func workerFailure(request: WorkerRequest, error: EventKitWorkerError) -> WorkerResponse {
    switch error {
    case .notFound:
        .failure(request: request, code: "eventkit.not_found")
    case .readOnlyDestination:
        .failure(request: request, code: "eventkit.destination_read_only", retry: .afterUserAction)
    case .accessUnavailable:
        .failure(request: request, code: "eventkit.access_unavailable", retry: .afterUserAction)
    case .verificationFailed:
        .failure(request: request, code: "eventkit.verification_failed", retry: .never)
    }
}

func eventKitFailure(request: WorkerRequest, error: Error) -> WorkerResponse? {
    let nativeError = error as NSError
    guard nativeError.domain == EKError.errorDomain else { return nil }
    let code = if nativeError.code == EKError.eventStoreNotAuthorized.rawValue {
        "eventkit.access_unavailable"
    } else {
        "eventkit.error_\(nativeError.code)"
    }
    return .failure(request: request, code: code, retry: .afterUserAction)
}

// Deterministic error-mapping tests do not cross the worker boundary and
// therefore intentionally use an uncorrelated response.
func workerFailure(requestID: String, error: EventKitWorkerError) -> WorkerResponse {
    let code = switch error {
    case .notFound: "eventkit.not_found"
    case .readOnlyDestination: "eventkit.destination_read_only"
    case .accessUnavailable: "eventkit.access_unavailable"
    case .verificationFailed: "eventkit.verification_failed"
    }
    return .uncorrelatedFailure(code: code)
}

func eventKitFailure(requestID: String, error: Error) -> WorkerResponse? {
    let nativeError = error as NSError
    guard nativeError.domain == EKError.errorDomain else { return nil }
    let code = nativeError.code == EKError.eventStoreNotAuthorized.rawValue
        ? "eventkit.access_unavailable" : "eventkit.error_\(nativeError.code)"
    return .uncorrelatedFailure(code: code)
}
