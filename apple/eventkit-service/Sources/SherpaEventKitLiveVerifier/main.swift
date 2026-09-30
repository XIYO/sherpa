import Foundation
import SherpaEventKitLiveVerifierSupport

private struct FailureResponse: Encodable {
    let status = "failed"
    let code: String
    let stage: String?
    let mismatch: FailureMismatch?
}

private struct FailureMismatch: Encodable {
    let field: String
    let expected: String
    let actual: String
}

@main
struct SherpaEventKitLiveVerifierMain {
    static func main() {
        do {
            let configuration = try LiveVerifierConfiguration.parse(
                arguments: Array(CommandLine.arguments.dropFirst()),
                environment: ProcessInfo.processInfo.environment
            )
            try EventKitLiveVerifier(configuration: configuration).run()
            print("{\"status\":\"verified\",\"suite\":\"\(configuration.successSuite)\"}")
        } catch let failure as LiveVerifierFailure {
            let response = FailureResponse(
                code: failure.stableCode,
                stage: failure.stage.rawValue,
                mismatch: failure.mismatch.map {
                    FailureMismatch(
                        field: $0.field.rawValue,
                        expected: $0.expected,
                        actual: $0.actual
                    )
                }
            )
            let output = try? JSONEncoder().encode(response)
            print(output.flatMap { String(data: $0, encoding: .utf8) }
                ?? #"{"status":"failed","code":"live_verifier.internal_failure"}"#)
            Foundation.exit(EXIT_FAILURE)
        } catch let error as LiveVerifierError {
            print("{\"status\":\"failed\",\"code\":\"\(error.stableCode)\"}")
            Foundation.exit(EXIT_FAILURE)
        } catch {
            print(#"{"status":"failed","code":"live_verifier.internal_failure"}"#)
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
