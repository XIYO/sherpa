import Foundation
import SherpaMutationApplication
import Testing
@testable import SherpaNativeCommandAdapter

// A send passes through three places a failure can land: before the sender is
// launched, after it was handed the message, and after it accepted the message
// but before the journal holds that. Only the first may be journaled `failed`.
// The sender is a fixture `imsg` run by the real command runner, so the
// runner's own post-launch handling is what these tests exercise.

@Test func imessageSendRejectedBeforeDispatchIsJournaledAsFailed() async throws {
    let send = try FixtureSend(group: #"{"chat_id":8}"#, send: "exit 0")
    let journal = FakeJournal()
    let error = await #expect(throws: JournaledMutationError.self) {
        _ = try await send.perform(journal: journal)
    }
    #expect(error?.status == .failed)
    #expect(error?.journalFailure == nil)
    #expect(journal.state == .failed)
    #expect(!send.dispatched)
}

@Test func imessageSendWhoseOutputCannotBeReadAfterDispatchIsJournaledAsUncertain() async throws {
    let send = try FixtureSend(group: #"{"chat_id":7}"#, send: "head -c 4194305 /dev/zero")
    let journal = FakeJournal()
    let error = await #expect(throws: JournaledMutationError.self) {
        _ = try await send.perform(journal: journal)
    }
    #expect(error?.status == .uncertain)
    #expect(error?.journalFailure == nil)
    #expect(journal.state == .uncertain)
    #expect(send.dispatched)
}

@Test func imessageSendAcceptedButNotJournaledIsNeverRewrittenAsFailed() async throws {
    let send = try FixtureSend(
        group: #"{"chat_id":7}"#, send: #"printf '%s\n' '{"accepted":true}'"#
    )
    let journal = FakeJournal(refusing: [.completed])
    let result = try await send.perform(journal: journal)
    #expect(result.attempt.status == .completed)
    #expect(String(decoding: result.attempt.output, as: UTF8.self).contains("accepted"))
    #expect(result.journalFailure == .finishFailed)
    #expect(journal.requested == [.completed])
    #expect(journal.state == .started)
    #expect(send.dispatched)
}

@Test func imessageSendWhoseFailureCannotBeJournaledStaysStartedAndSaysSo() async throws {
    let send = try FixtureSend(group: #"{"chat_id":7}"#, send: "exit 3")
    let journal = FakeJournal(refusing: [.uncertain])
    let error = await #expect(throws: JournaledMutationError.self) {
        _ = try await send.perform(journal: journal)
    }
    #expect(error?.status == .uncertain)
    #expect(error?.journalFailure == .finishFailed)
    #expect(journal.requested == [.uncertain])
    #expect(journal.state == .started)
}

@Test func imessageSendIsNeverAttemptedWhenTheJournalCannotStart() async throws {
    let send = try FixtureSend(group: #"{"chat_id":7}"#, send: "exit 0")
    let journal = FakeJournal(refusingStart: true)
    let error = await #expect(throws: JournaledMutationError.self) {
        _ = try await send.perform(journal: journal)
    }
    #expect(error?.status == .failed)
    #expect(error?.operationID == nil)
    #expect(error?.journalFailure == .startFailed)
    #expect(journal.state == nil)
    #expect(!send.dispatched)
}

private final class FixtureSend {
    let fixture: FixtureScript
    let marker: URL

    init(group: String, send: String) throws {
        marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("sherpa-dispatch-\(UUID().uuidString)")
        fixture = try FixtureScript(body: """
        if [ "$1" = group ]; then
          printf '%s\\n' '\(group)'
          exit 0
        fi
        if [ "$1" = send ]; then
          : > '\(marker.path)'
          \(send)
          exit $?
        fi
        exit 90
        """)
    }

    deinit { try? FileManager.default.removeItem(at: marker) }

    var dispatched: Bool { FileManager.default.fileExists(atPath: marker.path) }

    func perform(journal: FakeJournal) async throws -> JournaledMutationResult<Data> {
        let adapter = IMessageAdapter(executable: fixture.url)
        return try await JournaledMutation(journal: journal).perform(capability: "imessage.send") {
            MutationAttempt(output: try adapter.send(chatID: 7, text: Data("hello".utf8)))
        }
    }
}

/// Holds one operation the way the SQLite journal does: a single `started` row
/// that accepts exactly one terminal status. `refusing` statuses fail to write.
private final class FakeJournal: MutationJournal, @unchecked Sendable {
    private struct Refused: Error {}

    private let lock = NSLock()
    private let refusing: Set<NativeMutationStatus>
    private let refusingStart: Bool
    private var storedState: NativeMutationStatus?
    private var requestedStatuses: [NativeMutationStatus] = []

    init(refusing: Set<NativeMutationStatus> = [], refusingStart: Bool = false) {
        self.refusing = refusing
        self.refusingStart = refusingStart
    }

    var state: NativeMutationStatus? { lock.withLock { storedState } }
    var requested: [NativeMutationStatus] { lock.withLock { requestedStatuses } }

    func start(capability: String) throws -> String {
        let operationID = "op-test"
        try start(operationID: operationID, capability: capability)
        return operationID
    }

    func start(operationID: String, capability: String) throws {
        try lock.withLock {
            guard !refusingStart, storedState == nil else { throw Refused() }
            storedState = .started
        }
    }

    func finish(operationID: String, status: NativeMutationStatus, stableErrorCode: String?) throws {
        try lock.withLock {
            requestedStatuses.append(status)
            guard !refusing.contains(status), storedState == .started else { throw Refused() }
            storedState = status
        }
    }
}
