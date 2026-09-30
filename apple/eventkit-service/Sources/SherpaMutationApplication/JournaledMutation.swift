/// Journal states of one external mutation. `started` is the only non-terminal
/// state: an operation left there has an outcome nobody recorded.
public enum NativeMutationStatus: String, Codable, Sendable {
    case started, completed, failed, partial, uncertain
}

/// Application-owned port for the mutation journal. The SQLite store implements it.
public protocol MutationJournal: Sendable {
    func start(capability: String) throws -> String
    func start(operationID: String, capability: String) throws
    func finish(operationID: String, status: NativeMutationStatus, stableErrorCode: String?) throws
}

/// What a thrown attempt says about its external effect. An error that does not
/// conform means the effect never started.
public protocol MutationAttemptFailure: Error {
    /// The attempt reached the provider and could not establish the outcome.
    var mayHaveApplied: Bool { get }
    var stableCode: String { get }
}

/// The outcome an attempt returns: its output and the terminal status to journal.
public struct MutationAttempt<Output: Sendable>: Sendable {
    public let output: Output
    public let status: NativeMutationStatus
    public let stableErrorCode: String?

    public init(output: Output, status: NativeMutationStatus = .completed, stableErrorCode: String? = nil) {
        self.output = output
        self.status = status
        self.stableErrorCode = stableErrorCode
    }
}

/// A journal write that did not happen. The operation row, if any, stays `started`.
public enum MutationJournalFailure: String, Error, Sendable, Equatable {
    case startFailed = "journal.start_failed"
    case finishFailed = "journal.finish_failed"
}

public struct JournaledMutationResult<Output: Sendable>: Sendable {
    public let operationID: String
    public let attempt: MutationAttempt<Output>
    /// Non-nil when the journal does not hold `attempt.status`.
    public let journalFailure: MutationJournalFailure?
}

/// The attempt did not return. `status` is what happened to the effect:
/// `failed` when it never started, `uncertain` when it may have applied.
public struct JournaledMutationError: Error, Sendable, Equatable {
    public let operationID: String?
    public let status: NativeMutationStatus
    public let stableCode: String
    /// Non-nil when the journal does not hold `status`.
    public let journalFailure: MutationJournalFailure?
}

/// Journals one external mutation: start, attempt, one terminal status.
///
/// The attempt and each journal write are separate error boundaries. The status
/// comes from the attempt alone; a journal write that fails never changes it,
/// is never retried as another status, and leaves the row `started`, which
/// `operations list` shows as an outcome nobody recorded.
public struct JournaledMutation<Journal: MutationJournal>: Sendable {
    private let journal: Journal

    public init(journal: Journal) {
        self.journal = journal
    }

    public func perform<Output: Sendable>(
        capability: String,
        operationID suppliedOperationID: String? = nil,
        _ attempt: @Sendable () async throws -> MutationAttempt<Output>
    ) async throws -> JournaledMutationResult<Output> {
        let operationID: String
        do {
            if let suppliedOperationID {
                try journal.start(operationID: suppliedOperationID, capability: capability)
                operationID = suppliedOperationID
            } else {
                operationID = try journal.start(capability: capability)
            }
        } catch {
            // Nothing was attempted, so the effect cannot have started.
            throw JournaledMutationError(
                operationID: nil,
                status: .failed,
                stableCode: MutationJournalFailure.startFailed.rawValue,
                journalFailure: .startFailed
            )
        }

        let outcome: MutationAttempt<Output>
        do {
            outcome = try await attempt()
        } catch {
            let failure = error as? any MutationAttemptFailure
            let status: NativeMutationStatus = failure?.mayHaveApplied == true ? .uncertain : .failed
            let code = failure?.stableCode ?? "failed"
            throw JournaledMutationError(
                operationID: operationID,
                status: status,
                stableCode: code,
                journalFailure: finish(operationID, status: status, stableErrorCode: code)
            )
        }
        return JournaledMutationResult(
            operationID: operationID,
            attempt: outcome,
            journalFailure: finish(
                operationID, status: outcome.status, stableErrorCode: outcome.stableErrorCode
            )
        )
    }

    /// Writes the one terminal status and reports a write that did not happen.
    private func finish(
        _ operationID: String,
        status: NativeMutationStatus,
        stableErrorCode: String?
    ) -> MutationJournalFailure? {
        do {
            try journal.finish(operationID: operationID, status: status, stableErrorCode: stableErrorCode)
            return nil
        } catch {
            return .finishFailed
        }
    }
}
