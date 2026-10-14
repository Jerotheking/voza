import Darwin
import Foundation

/// Errors produced by `ProcessRunner` (V04-AC01..AC04 / D058).
enum ProcessRunnerError: LocalizedError, Equatable, Sendable {
    case launchFailed(String)
    case timedOut(TimeInterval)
    case cancelled
    case outputLimitExceeded(stream: String, limitBytes: Int)
    case invalidUTF8(stream: String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let msg):
            return "Process launch failed: \(msg)"
        case .timedOut(let seconds):
            return "Process timed out after \(Int(seconds))s"
        case .cancelled:
            return "Process cancelled"
        case .outputLimitExceeded(let stream, let limit):
            return "Process \(stream) exceeded limit of \(limit) bytes"
        case .invalidUTF8(let stream):
            return "Process \(stream) produced invalid UTF-8"
        case .nonZeroExit(let code, let stderr):
            return "Process exited with code \(code): \(stderr)"
        }
    }
}

/// Thread-safe cancellation token for `ProcessRunner` (V04-AC02).
final class ProcessCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var onCancelHandlers: [() -> Void] = []

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        let handlers: [() -> Void]
        lock.lock()
        if _isCancelled {
            lock.unlock()
            return
        }
        _isCancelled = true
        handlers = onCancelHandlers
        onCancelHandlers.removeAll()
        lock.unlock()
        for h in handlers { h() }
    }

    func register(_ handler: @escaping () -> Void) {
        lock.lock()
        if _isCancelled {
            lock.unlock()
            handler()
            return
        }
        onCancelHandlers.append(handler)
        lock.unlock()
    }
}

/// Deterministic, shell-free subprocess runner with concurrent bounded pipe draining,
/// monotonic timeout, cancellation, and SIGTERM -> SIGKILL escalation (V04 / D058).
struct ProcessRunner: Sendable {
    struct Output: Equatable, Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    var maxStdoutBytes: Int
    var maxStderrBytes: Int
    var sigkillGraceSeconds: TimeInterval

    init(
        maxStdoutBytes: Int = 4 * 1024 * 1024,
        maxStderrBytes: Int = 1 * 1024 * 1024,
        sigkillGraceSeconds: TimeInterval = 0.25
    ) {
        self.maxStdoutBytes = maxStdoutBytes
        self.maxStderrBytes = maxStderrBytes
        self.sigkillGraceSeconds = sigkillGraceSeconds
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval,
        cancellationToken: ProcessCancellationToken? = nil
    ) throws -> Output {
        if cancellationToken?.isCancelled == true {
            throw ProcessRunnerError.cancelled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let exitSem = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSem.signal()
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let pid = process.processIdentifier

        final class StreamCollector: @unchecked Sendable {
            let lock = NSLock()
            var data = Data()
            var exceeded = false

            func append(_ chunk: Data, maxBytes: Int) -> Bool {
                lock.lock(); defer { lock.unlock() }
                if data.count + chunk.count > maxBytes {
                    exceeded = true
                    return false
                }
                data.append(chunk)
                return true
            }
        }

        let outCollector = StreamCollector()
        let errCollector = StreamCollector()
        let drainGroup = DispatchGroup()

        let maxOut = maxStdoutBytes
        let maxErr = maxStderrBytes

        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { drainGroup.leave() }
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = (try? handle.read(upToCount: 65_536)) ?? nil
                guard let chunk, !chunk.isEmpty else { break }
                if !outCollector.append(chunk, maxBytes: maxOut) {
                    if process.isRunning { process.terminate() }
                    break
                }
            }
        }

        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { drainGroup.leave() }
            let handle = errPipe.fileHandleForReading
            while true {
                let chunk = (try? handle.read(upToCount: 65_536)) ?? nil
                guard let chunk, !chunk.isEmpty else { break }
                if !errCollector.append(chunk, maxBytes: maxErr) {
                    if process.isRunning { process.terminate() }
                    break
                }
            }
        }

        cancellationToken?.register {
            if process.isRunning {
                process.terminate()
            }
        }

        let startUptime = ProcessInfo.processInfo.systemUptime
        let deadlineUptime = startUptime + max(0.01, timeout)
        var timedOut = false

        while true {
            if cancellationToken?.isCancelled == true {
                break
            }
            if outCollector.exceeded || errCollector.exceeded {
                break
            }
            let remaining = deadlineUptime - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                timedOut = true
                break
            }
            let step = min(0.02, remaining)
            if exitSem.wait(timeout: .now() + step) == .success {
                break
            }
        }

        if process.isRunning || timedOut || cancellationToken?.isCancelled == true || outCollector.exceeded || errCollector.exceeded {
            if process.isRunning {
                process.terminate()
            }
            if exitSem.wait(timeout: .now() + sigkillGraceSeconds) == .timedOut {
                if process.isRunning && pid > 0 {
                    _ = Darwin.kill(pid, SIGKILL)
                }
                _ = exitSem.wait(timeout: .now() + 1.0)
            }
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }

        process.waitUntilExit()
        drainGroup.wait()

        if cancellationToken?.isCancelled == true {
            throw ProcessRunnerError.cancelled
        }
        if outCollector.exceeded {
            throw ProcessRunnerError.outputLimitExceeded(stream: "stdout", limitBytes: maxOut)
        }
        if errCollector.exceeded {
            throw ProcessRunnerError.outputLimitExceeded(stream: "stderr", limitBytes: maxErr)
        }
        if timedOut {
            throw ProcessRunnerError.timedOut(timeout)
        }

        guard let outString = String(bytes: outCollector.data, encoding: .utf8) else {
            throw ProcessRunnerError.invalidUTF8(stream: "stdout")
        }
        guard let errString = String(bytes: errCollector.data, encoding: .utf8) else {
            throw ProcessRunnerError.invalidUTF8(stream: "stderr")
        }

        return Output(stdout: outString, stderr: errString, exitCode: process.terminationStatus)
    }
}
