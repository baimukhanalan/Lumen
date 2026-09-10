import Foundation

/// Minimal, synchronous subprocess runner. Used for `pmset`/`ps` where the
/// output is small and bounded. Never passes untrusted strings to a shell —
/// arguments are handed to the executable directly (no `/bin/sh -c`).
public enum Shell {

    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    @discardableResult
    public static func run(_ launchPath: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }

        // Read before waiting to avoid deadlock on large output (bounded here,
        // but correct regardless).
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
