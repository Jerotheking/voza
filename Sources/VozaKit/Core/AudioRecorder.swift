import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError, Equatable {
    case deviceUnavailable
    case conversionFailed
    case writeFailed
    case byteLimitExceeded

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return L.t("Mic not available", es: "Micrófono no disponible")
        case .conversionFailed: return L.t("Audio conversion failed", es: "Fallo al convertir el audio")
        case .writeFailed: return L.t("Audio disk write failed", es: "Fallo al escribir el audio en disco")
        case .byteLimitExceeded: return L.t("Recording reached maximum length", es: "La grabación alcanzó la duración máxima")
        }
    }
}

/// Records microphone audio with AVAudioEngine and writes a 16 kHz mono IEEE Float32 WAV file (V05 / D059).
final class AudioRecorder {
    static let shared = AudioRecorder()

    /// Maximum PCM payload bytes per recording (~16.7 minutes at 16 kHz mono Float32 = 64 MB).
    /// Prevents unbounded disk/memory growth if a key or session is left open (V05-AC05).
    static let defaultMaxPCMBytes: UInt64 = 64 * 1024 * 1024

    private var engine: AVAudioEngine?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var fileHandle: FileHandle?
    private var pcmBytes: UInt64 = 0
    private var writeErrorOccurred = false
    private(set) var outputURL: URL?
    private(set) var lastAsset: AudioAsset?

    private let stateLock = NSLock()
    private var _isRecording = false
    private var _startedAt: Date?

    var isRecording: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isRecording
    }

    private let ioQueue = DispatchQueue(label: "voza.audiorecorder.io")
    let maxPCMBytes: UInt64

    // MARK: - Level meter (D021: audio-reactive HUD)

    private let levelLock = NSLock()
    private var _level: Double = 0

    var level: Double {
        levelLock.lock(); defer { levelLock.unlock() }
        return _level
    }

    private func setLevel(_ v: Double) {
        levelLock.lock()
        _level = v
        levelLock.unlock()
    }

    static func meterLevel(rms: Double) -> Double {
        let clamped = min(max(rms, 1e-7), 1.0)
        let db = 20 * log10(clamped)
        return max(0, min(1, (db + 60) / 54))
    }

    var elapsedSeconds: Double {
        stateLock.lock()
        let active = _isRecording
        let start = _startedAt
        stateLock.unlock()
        guard active, let start else { return 0 }
        return Date().timeIntervalSince(start)
    }

    init(maxPCMBytes: UInt64 = AudioRecorder.defaultMaxPCMBytes) {
        self.maxPCMBytes = maxPCMBytes
    }

    // MARK: - Lifecycle

    func start(
        directory: URL? = nil,
        engineStartHook: (() throws -> Void)? = nil
    ) throws {
        stateLock.lock()
        if _isRecording {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioRecorderError.deviceUnavailable
        }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw AudioRecorderError.conversionFailed
        }

        let targetDir = directory ?? FileManager.default.temporaryDirectory
        let url = try Self.createPrivateWAVFile(in: targetDir)
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data(repeating: 0, count: 44))
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw AudioRecorderError.writeFailed
        }

        ioQueue.sync {
            self.fileHandle = handle
            self.pcmBytes = 0
            self.writeErrorOccurred = false
        }

        self.engine = engine
        self.targetFormat = target
        self.converter = converter
        self.outputURL = url
        self.lastAsset = nil

        stateLock.lock()
        self._startedAt = Date()
        self._isRecording = true
        stateLock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.enqueue(buffer)
        }
        engine.prepare()
        do {
            if let engineStartHook {
                try engineStartHook()
            } else {
                try engine.start()
            }
        } catch {
            stateLock.lock()
            self._isRecording = false
            self._startedAt = nil
            stateLock.unlock()
            input.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            self.targetFormat = nil
            ioQueue.sync {
                try? self.fileHandle?.close()
                self.fileHandle = nil
                self.pcmBytes = 0
                self.writeErrorOccurred = false
            }
            try? FileManager.default.removeItem(at: url)
            self.outputURL = nil
            throw error
        }
    }

    /// Creates a private (`0o600`) temporary WAV placeholder with a random UUID name (V05 Step 3).
    static func createPrivateWAVFile(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("voza-\(UUID().uuidString).wav")
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw AudioRecorderError.writeFailed
        }
        return url
    }

    /// Appends raw Float32 mono samples on `ioQueue` (used by both live capture and hermetic V05 tests).
    func appendSamplesForTesting(_ samples: [Float], directory: URL) throws {
        if !isRecording {
            let url = try Self.createPrivateWAVFile(in: directory)
            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data(repeating: 0, count: 44))
            ioQueue.sync {
                self.fileHandle = handle
                self.pcmBytes = 0
                self.writeErrorOccurred = false
            }
            self.outputURL = url
            stateLock.lock()
            self._startedAt = Date()
            self._isRecording = true
            stateLock.unlock()
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        var threw: Error?
        ioQueue.sync {
            do {
                try self.writePCMDataOnIOQueue(data)
            } catch {
                threw = error
            }
        }
        if let threw { throw threw }
    }

    func stop() -> URL? {
        stateLock.lock()
        guard _isRecording else {
            stateLock.unlock()
            return nil
        }
        _isRecording = false
        _startedAt = nil
        stateLock.unlock()

        setLevel(0)
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        targetFormat = nil

        var finalBytes: UInt64 = 0
        var hadWriteError = false
        ioQueue.sync {
            finalBytes = self.pcmBytes
            hadWriteError = self.writeErrorOccurred
            try? self.fileHandle?.close()
            self.fileHandle = nil
            self.pcmBytes = 0
            self.writeErrorOccurred = false
        }

        guard let url = outputURL else { return nil }
        outputURL = nil

        if hadWriteError {
            try? FileManager.default.removeItem(at: url)
            lastAsset = nil
            return nil
        }

        Self.finalizeWAVHeader(at: url, pcmBytes: finalBytes)
        lastAsset = try? AudioAsset.inspectWAV(at: url, ownsFile: true)
        return url
    }

    func cancel() {
        stateLock.lock()
        let wasRecording = _isRecording
        _isRecording = false
        _startedAt = nil
        stateLock.unlock()

        if wasRecording {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
        }
        setLevel(0)
        engine = nil
        converter = nil
        targetFormat = nil

        ioQueue.sync {
            try? self.fileHandle?.close()
            self.fileHandle = nil
            self.pcmBytes = 0
            self.writeErrorOccurred = false
        }

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        lastAsset = nil
    }

    // MARK: - Conversion & Serialized I/O

    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let active = _isRecording
        stateLock.unlock()
        guard active, let converter, let target = targetFormat else { return }

        let inputFrames = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate + 64)
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(inputFrames, 1024)) else { return }
        var fed = false
        var error: NSError?

        let result = converter.convert(to: converted, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, result == .haveData, let channel = converted.floatChannelData?[0] else { return }
        let frames = Int(converted.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for i in 0..<frames { let s = channel[i]; sum += s * s }
        setLevel(Self.meterLevel(rms: Double(sqrt(sum / Float(frames)))))

        let data = Data(buffer: UnsafeBufferPointer(start: channel, count: frames))
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? self.writePCMDataOnIOQueue(data)
        }
    }

    private func writePCMDataOnIOQueue(_ data: Data) throws {
        guard let handle = fileHandle, !writeErrorOccurred else { return }
        if pcmBytes + UInt64(data.count) > maxPCMBytes {
            writeErrorOccurred = true
            throw AudioRecorderError.byteLimitExceeded
        }
        do {
            try handle.write(contentsOf: data)
            pcmBytes += UInt64(data.count)
        } catch {
            writeErrorOccurred = true
            throw AudioRecorderError.writeFailed
        }
    }

    static func finalizeWAVHeader(at url: URL, pcmBytes: UInt64) {
        let clampedBytes = UInt32(min(pcmBytes, UInt64(UInt32.max - 36)))
        let header = Self.wavHeader(dataBytes: clampedBytes)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seek(toOffset: 0)
            try? handle.write(contentsOf: header)
        }
    }

    static func wavHeader(dataBytes: UInt32, sampleRate: UInt32 = UInt32(Config.targetSampleRate)) -> Data {
        var header = Data(capacity: 44)
        func appendStr(_ s: String) { header.append(Data(s.utf8)) }
        func appendU32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { header.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { header.append(contentsOf: $0) } }

        appendStr("RIFF"); appendU32(36 + dataBytes); appendStr("WAVE")
        appendStr("fmt "); appendU32(16)          // fmt chunk size
        appendU16(3)                              // WAVE_FORMAT_IEEE_FLOAT (payload is Float32)
        appendU16(1)                              // mono
        appendU32(sampleRate)
        appendU32(sampleRate * 4)                 // byte rate = rate * 1 ch * 4 bytes/sample
        appendU16(4)                              // block align
        appendU16(32)                             // bits per sample
        appendStr("data"); appendU32(dataBytes)
        return header
    }
}
