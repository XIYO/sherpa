import Foundation
import SherpaWorkerProtocol

@main
struct SherpaFoundationModelsMain {
    static func main() async {
        let response: WorkerResponse
        do {
            let input = try readWorkerRequest(maximumBytes: 2 * 1024 * 1024)
            let request = try WorkerRequest(data: input)
            WorkerLog.info(
                "[worker:foundation-models:request:start] capability=\(request.capability)"
            )
            response = await FoundationModelWorker().handle(request)
            if response.status == .succeeded {
                WorkerLog.info(
                    "[worker:foundation-models:request:success] capability=\(request.capability)"
                )
            } else {
                WorkerLog.error(
                    "[worker:foundation-models:request:failure] capability=\(request.capability) code=\(response.error?.code ?? "protocol.missing_error")"
                )
            }
        } catch let error as WorkerProtocolError {
            WorkerLog.error(
                "[worker:foundation-models:request:failure] code=\(error.stableCode)"
            )
            response = .uncorrelatedFailure(code: error.stableCode)
        } catch {
            WorkerLog.error(
                "[worker:foundation-models:request:failure] code=protocol.internal_failure"
            )
            response = .uncorrelatedFailure(code: "protocol.internal_failure")
        }
        do {
            FileHandle.standardOutput.write(try response.encoded(maximumBytes: 4 * 1024 * 1024))
        } catch {
            WorkerLog.error(
                "[worker:foundation-models:response:failure] code=protocol.encode_failure"
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
