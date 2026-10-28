import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

enum ProcessRunner {
    /// Runs an executable to completion. `onLine` receives each stdout line as it arrives.
    static func run(_ executable: URL, _ arguments: [String], currentDirectory: URL? = nil,
                    environment: [String: String]? = nil,
                    onLine: ((String) -> Void)? = nil) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            var env = ProcessInfo.processInfo.environment
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            environment?.forEach { env[$0.key] = $0.value }
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            let lock = NSLock()
            var outData = Data(), errData = Data(), lineBuffer = ""
            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lock.lock(); outData.append(data)
                if let onLine {
                    lineBuffer += String(decoding: data, as: UTF8.self)
                    while let range = lineBuffer.rangeOfCharacter(from: CharacterSet(charactersIn: "\n\r")) {
                        let line = String(lineBuffer[..<range.lowerBound])
                        lineBuffer = String(lineBuffer[range.upperBound...])
                        if !line.isEmpty { onLine(line) }
                    }
                }
                lock.unlock()
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lock.lock(); errData.append(data); lock.unlock()
            }
            process.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                lock.lock()
                outData.append(out.fileHandleForReading.readDataToEndOfFile())
                errData.append(err.fileHandleForReading.readDataToEndOfFile())
                let result = ProcessResult(status: proc.terminationStatus, stdout: outData, stderr: errData)
                lock.unlock()
                continuation.resume(returning: result)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    @discardableResult
    static func check(_ executable: URL, _ arguments: [String], currentDirectory: URL? = nil,
                      environment: [String: String]? = nil,
                      onLine: ((String) -> Void)? = nil) async throws -> ProcessResult {
        let result = try await run(executable, arguments, currentDirectory: currentDirectory, environment: environment, onLine: onLine)
        guard result.status == 0 else {
            let message = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.processFailed(executable.lastPathComponent, message.isEmpty ? "exit \(result.status)" : String(message.suffix(600)))
        }
        return result
    }
}
