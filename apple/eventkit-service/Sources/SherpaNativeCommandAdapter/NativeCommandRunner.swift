import Darwin
import Foundation
import SherpaMutationApplication

public enum NativeCommandError: Error, Equatable {
    case executableUnavailable
    case invalidRequest
    case outputTooLarge
    case failed
    case timedOut
    case uncertain
    case rejected(String)
}

extension NativeCommandError: MutationAttemptFailure {
    /// Only `uncertain` is reported after a mutation command was handed its input.
    public var mayHaveApplied: Bool { self == .uncertain }
    public var stableCode: String { String(describing: self) }
}

public struct NativeCommandOutput: Sendable, Equatable {
    public let stdout: Data
    public let stderr: Data
}

public enum NativeCommandEffect: Sendable {
    case inferFromStandardInput
    case read
    case mutation
}

public struct NativeCommandRunner: Sendable {
    public init() {}

    public func resolve(configuredPath: String?, fallbackName: String) throws -> URL {
        if let configuredPath {
            let url = URL(fileURLWithPath: configuredPath)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw NativeCommandError.executableUnavailable
            }
            return url
        }
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        for directory in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(fallbackName)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw NativeCommandError.executableUnavailable
    }

    public func run(
        executable: URL,
        arguments: [String],
        stdin: Data = Data(),
        timeoutSeconds: TimeInterval = 30,
        outputLimit: Int = 4 * 1_024 * 1_024,
        effect: NativeCommandEffect = .inferFromStandardInput
    ) throws -> NativeCommandOutput {
        guard stdin.count <= 1_024 * 1_024, outputLimit > 0 else {
            throw NativeCommandError.invalidRequest
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sherpa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("stdin")
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        guard FileManager.default.createFile(
            atPath: inputURL.path, contents: stdin, attributes: [.posixPermissions: 0o600]
        ), FileManager.default.createFile(
            atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ), FileManager.default.createFile(
            atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else { throw NativeCommandError.failed }

        let input = try FileHandle(forReadingFrom: inputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        defer {
            try? input.close()
            try? output.close()
            try? error.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.environment = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? ""]
        try process.run()

        // The command now holds its input. For a mutation, any failure from here on
        // may follow an effect that already happened, so it is `uncertain` —
        // never an error that reads as "nothing was sent".
        do {
            return try collect(
                process,
                output: output,
                error: error,
                outputURL: outputURL,
                errorURL: errorURL,
                timeoutSeconds: timeoutSeconds,
                outputLimit: outputLimit
            )
        } catch let failure {
            guard isMutation(effect, stdin: stdin) else { throw failure }
            throw NativeCommandError.uncertain
        }
    }

    private func collect(
        _ process: Process,
        output: FileHandle,
        error: FileHandle,
        outputURL: URL,
        errorURL: URL,
        timeoutSeconds: TimeInterval,
        outputLimit: Int
    ) throws -> NativeCommandOutput {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.25)
            while process.isRunning, Date() < grace { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw NativeCommandError.timedOut
        }
        process.waitUntilExit()
        try output.synchronize()
        try error.synchronize()

        let stdout = try boundedRead(outputURL, limit: outputLimit)
        let stderr = try boundedRead(errorURL, limit: 64 * 1_024)
        guard process.terminationStatus == 0 else { throw NativeCommandError.failed }
        return NativeCommandOutput(stdout: stdout, stderr: stderr)
    }
}

private func isMutation(_ effect: NativeCommandEffect, stdin: Data) -> Bool {
    switch effect {
    case .inferFromStandardInput: !stdin.isEmpty
    case .read: false
    case .mutation: true
    }
}

private func boundedRead(_ url: URL, limit: Int) throws -> Data {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber, size.intValue <= limit else {
        throw NativeCommandError.outputTooLarge
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw NativeCommandError.outputTooLarge }
    return data
}
