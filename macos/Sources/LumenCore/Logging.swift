import Foundation

/// Append-only logger for the daemon. Falls back to stderr when the log file
/// isn't writable (e.g. when run as a non-root user during testing).
public final class FileLogger: @unchecked Sendable {

    private let path: String
    private let queue = DispatchQueue(label: "com.lumen.logger")
    private let formatter: DateFormatter
    public var echoToStderr: Bool

    public init(path: String, echoToStderr: Bool = false) {
        self.path = path
        self.echoToStderr = echoToStderr
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.formatter = f
    }

    public func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.sync {
            if echoToStderr { FileHandle.standardError.write(Data(line.utf8)) }
            appendToFile(line)
        }
    }

    private func appendToFile(_ line: String) {
        let data = Data(line.utf8)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: data)
            return
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}
