import Foundation

/// Lightweight logging to stderr and a file so we can inspect runtime state.
enum Diag {
    static let path = "/tmp/taskbar-debug.log"

    static func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}
