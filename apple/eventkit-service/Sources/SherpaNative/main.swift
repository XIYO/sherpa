import Darwin
import Foundation
import SherpaEventKitAdapter
import SherpaMailShim
import SherpaMutationApplication
import SherpaNativeCommandAdapter
import SherpaReminderKitShim
import SherpaWorkerProtocol

@main
enum SherpaNativeMain {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--version"] || arguments == ["version"] {
                FileHandle.standardOutput.write(Data("sherpa 0.7.1\n".utf8))
                return
            }
            if arguments == ["--help"] || arguments == ["help"] || arguments.isEmpty {
                FileHandle.standardOutput.write(Data(nativeHelp.utf8))
                return
            }
            guard arguments.count >= 2 else { throw NativeCommandError.invalidRequest }
            let runner = NativeCommandRunner()
            let output: Data
            switch (arguments[0], arguments[1]) {
            case ("planner", "request"):
                output = try await plannerRequest()
            case ("imessage", "chats"):
                output = try imessage(runner).chats(limit: try integer(arguments, "--limit"))
            case ("imessage", "history"):
                output = try imessage(runner).history(
                    chatID: try unsigned(arguments, "--chat-id"),
                    start: try value(arguments, "--start"),
                    end: try value(arguments, "--end"),
                    limit: try integer(arguments, "--limit")
                )
            case ("imessage", "send"):
                let chatID = try unsigned(arguments, "--chat-id")
                try requireConfirmation(arguments, expected: String(chatID))
                output = try await journaledSend("imessage.send") {
                    try imessage(runner).send(chatID: chatID, text: try boundedStandardInput())
                }
            case ("kakaotalk", "search"):
                output = try kakaotalk(runner).search(
                    query: try boundedStandardInput(maximum: 4_096),
                    limit: try integer(arguments, "--limit")
                )
            case ("kakaotalk", "history"):
                output = try kakaotalk(runner).history(
                    chatName: try boundedStandardInput(maximum: 4_096),
                    limit: try integer(arguments, "--limit")
                )
            case ("kakaotalk", "archive"):
                output = try kakaotalk(runner).archive(
                    since: try value(arguments, "--since"),
                    timeZoneIdentifier: try value(arguments, "--time-zone"),
                    limit: try integer(arguments, "--limit")
                )
            case ("kakaotalk", "checkpoint"):
                try requireConfirmation(arguments, expected: "COMMIT_LOCAL_CHECKPOINT")
                output = try kakaotalk(runner).commitCheckpoint(
                    token: try boundedStandardInput(maximum: 256)
                )
            case ("mail", "authorization-status"):
                output = try mail(runner).authorizationStatus()
            case ("mail", "list"):
                output = try JSONEncoder().encode(MailReader().list(
                    from: try value(arguments, "--from"),
                    to: try value(arguments, "--to"),
                    limit: try integer(arguments, "--limit"),
                    maximumBodyBytes: try integer(arguments, "--max-body-bytes")
                ))
            case ("mail", "read"):
                output = try JSONEncoder().encode(MailReader().read(
                    sourceMessageID: try value(arguments, "--message-id"),
                    maximumBodyBytes: try integer(arguments, "--max-body-bytes")
                ))
            case ("mail", "request"):
                output = SherpaMailHandleRequest(
                    try readWorkerRequest(maximumBytes: 2 * 1_024 * 1_024)
                )
            case ("mail", "send"):
                try requireConfirmation(arguments, expected: "SEND_MAIL")
                let payload = try boundedStandardInput(maximum: 1_100_000)
                let message = try JSONDecoder().decode(MailMessage.self, from: payload)
                output = try await journaledSend("mail.send") { try mail(runner).send(message) }
            case ("reminder-kit", "request"):
                output = SherpaReminderKitHandleRequest(
                    try readWorkerRequest(maximumBytes: 64 * 1_024)
                )
            case ("operations", "list"):
                output = try JSONEncoder().encode(
                    NativeMutationStore.openDefault().recent(limit: try integer(arguments, "--limit"))
                )
            default:
                throw NativeCommandError.invalidRequest
            }
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0a]))
        } catch {
            let report = CommandReport(failure: error)
            WorkerLog.error(
                "[cli:sherpa:command-failure] \(report.logFields) error_type=\(type(of: error))"
            )
            FileHandle.standardOutput.write(encoded(report))
            FileHandle.standardOutput.write(Data([0x0a]))
            exit(EXIT_FAILURE)
        }
    }
}

private let nativeHelp = """
Sherpa 0.7.1 — native macOS assistant CLI

USAGE:
  sherpa planner request
  sherpa imessage chats --limit <count>
  sherpa imessage history --chat-id <id> --start <iso8601> --end <iso8601> --limit <count>
  sherpa imessage send --chat-id <id> --confirm <id>
  sherpa kakaotalk search --limit <count>
  sherpa kakaotalk history --limit <count>
  sherpa kakaotalk archive --since <yyyy-mm-dd|checkpoint> --time-zone <iana> --limit <count>
  sherpa kakaotalk checkpoint --confirm COMMIT_LOCAL_CHECKPOINT
  sherpa mail authorization-status
  sherpa mail list --from <iso8601> --to <iso8601> --limit <count> --max-body-bytes <count>
  sherpa mail read --message-id <id> --max-body-bytes <count>
  sherpa mail request
  sherpa mail send --confirm SEND_MAIL
  sherpa reminder-kit request
  sherpa operations list --limit <count>

Planner, Mail request, and ReminderKit request accept strict JSON on standard input.
iMessage and Mail send bodies are also read from standard input.
KakaoTalk search reads one UTF-8 query from standard input. History reads one
exact display name from standard input and uses a fixed seven-day window.
Archive reads an explicit local-date range across synchronized rooms. A complete
archive returns a pending local checkpoint token; checkpoint reads that token
from standard input and commits it after analysis. All return bounded,
privacy-filtered local-database projections.
"""

private func plannerRequest() async throws -> Data {
    let input = try readWorkerRequest(maximumBytes: 64 * 1_024)
    let request = try WorkerRequest(data: input)
    guard request.policy.effect == .mutation else {
        return try await EventKitWorker().handle(request).encoded(maximumBytes: 8 * 1_024 * 1_024)
    }
    // The response states what happened to the effect, so it is returned even when
    // the journal could not record it; `journaled` logs that failure.
    let result = try await journaled(request.capability, operationID: request.operationID) {
        let response = await EventKitWorker().handle(request)
        let status: NativeMutationStatus = switch response.status {
        case .succeeded: .completed
        case .failed: .failed
        case .partial: .partial
        case .uncertain: .uncertain
        }
        return MutationAttempt(
            output: response, status: status, stableErrorCode: response.stableErrorCode
        )
    }
    return try result.attempt.output.encoded(maximumBytes: 8 * 1_024 * 1_024)
}

/// What stdout carries when a command does not end with its normal output. Every
/// field is a Sherpa-owned code, status, or operation ID; provider text and error
/// descriptions never reach it.
private struct CommandReport: Encodable {
    let status: String
    let error: String?
    let operationID: String?
    let journalError: String?

    enum CodingKeys: String, CodingKey {
        case status, error
        case operationID = "operation_id"
        case journalError = "journal_error"
    }

    init(status: String, error: String?, operationID: String? = nil, journalError: String? = nil) {
        self.status = status
        self.error = error
        self.operationID = operationID
        self.journalError = journalError
    }

    /// Names every failure. An error without a stable code of its own becomes
    /// `sherpa.internal_failure`.
    init(failure: any Error) {
        switch failure {
        case let failure as JournaledMutationError:
            self.init(
                status: failure.status.rawValue,
                error: failure.stableCode,
                operationID: failure.operationID,
                journalError: failure.journalFailure?.rawValue
            )
        case let failure as NativeCommandError:
            self.init(status: "failed", error: failure.stableCode)
        case let failure as WorkerProtocolError:
            self.init(status: "failed", error: failure.stableCode)
        default:
            self.init(status: "failed", error: "sherpa.internal_failure")
        }
    }

    var logFields: String {
        var fields = "status=\(status) code=\(error ?? "none")"
        if let operationID { fields += " operation_id=\(operationID)" }
        if let journalError { fields += " journal_error=\(journalError)" }
        return fields
    }
}

private func encoded(_ report: CommandReport) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        return try encoder.encode(report)
    } catch {
        WorkerLog.error("[cli:sherpa:report-failure] status=\(report.status)")
        return Data(#"{"status":"\#(report.status)"}"#.utf8)
    }
}

private func imessage(_ runner: NativeCommandRunner) throws -> IMessageAdapter {
    let executable = try runner.resolve(
        configuredPath: ProcessInfo.processInfo.environment["IMSG_BIN"], fallbackName: "imsg"
    )
    return IMessageAdapter(executable: executable, runner: runner)
}

private func mail(_ runner: NativeCommandRunner) throws -> MailAdapter {
    let executable = try runner.resolve(
        configuredPath: ProcessInfo.processInfo.environment["OSASCRIPT_BIN"],
        fallbackName: "osascript"
    )
    return MailAdapter(osascript: executable, runner: runner)
}

private func kakaotalk(_ runner: NativeCommandRunner) throws -> KakaoTalkLocalSearchAdapter {
    let executable = try runner.resolve(
        configuredPath: ProcessInfo.processInfo.environment["KAKAOCLI_BIN"],
        fallbackName: "kakaocli"
    )
    return KakaoTalkLocalSearchAdapter(executable: executable, runner: runner)
}

private func value(_ arguments: [String], _ name: String) throws -> String {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1)
    else { throw NativeCommandError.invalidRequest }
    return arguments[index + 1]
}

private func integer(_ arguments: [String], _ name: String) throws -> Int {
    guard let result = Int(try value(arguments, name)) else {
        throw NativeCommandError.invalidRequest
    }
    return result
}

private func unsigned(_ arguments: [String], _ name: String) throws -> UInt64 {
    guard let result = UInt64(try value(arguments, name)) else {
        throw NativeCommandError.invalidRequest
    }
    return result
}

private func boundedStandardInput(maximum: Int = 64 * 1_024) throws -> Data {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty, data.count <= maximum else {
        throw NativeCommandError.invalidRequest
    }
    return data
}

private func requireConfirmation(_ arguments: [String], expected: String) throws {
    guard try value(arguments, "--confirm") == expected else {
        throw NativeCommandError.invalidRequest
    }
}

/// Sends through the journal. A send that completed but could not be journaled
/// still reports `completed`, with the journal error, instead of its output.
private func journaledSend(
    _ capability: String,
    send: @Sendable () throws -> Data
) async throws -> Data {
    let result = try await journaled(capability) { MutationAttempt(output: try send()) }
    guard let journalFailure = result.journalFailure else { return result.attempt.output }
    return encoded(CommandReport(
        status: result.attempt.status.rawValue,
        error: nil,
        operationID: result.operationID,
        journalError: journalFailure.rawValue
    ))
}

private func journaled<Output: Sendable>(
    _ capability: String,
    operationID: String? = nil,
    _ attempt: @Sendable () async throws -> MutationAttempt<Output>
) async throws -> JournaledMutationResult<Output> {
    let journal = JournaledMutation(journal: try NativeMutationStore.openDefault())
    WorkerLog.info("[cli:sherpa:mutation-start] capability=\(capability)")
    let result = try await journal.perform(
        capability: capability, operationID: operationID, attempt
    )
    let fields = "capability=\(capability) operation_id=\(result.operationID) "
        + "status=\(result.attempt.status.rawValue)"
    if let journalFailure = result.journalFailure {
        WorkerLog.error("[cli:sherpa:journal-failure] \(fields) code=\(journalFailure.rawValue)")
    } else {
        WorkerLog.info("[cli:sherpa:mutation-finish] \(fields)")
    }
    return result
}
