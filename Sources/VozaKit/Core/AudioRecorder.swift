import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case deviceUnavailable
    case conversionFailed
    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return L.t("Mic not available", es: "Micrófono no disponible")
        case .conversionFailed: return L.t("Audio conversion failed", es: "Fallo al convertir el audio")
        }
    }
}

/// Records microphone audio with AVAudioEngine and writes a 16 kHz mono WAV file.
/// The heavy lifting (capture → PCM → WAV header) is implemented without external
/// binaries so the app works on a clean machine with zero dependencies.
final class AudioRecorder {
    static let shared = AudioRecorder()

    private var engine: AVAudioEngine?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var fileHandle: FileHandle?
    private var pcmBytes: UInt64 = 0
    private(set) var outputURL: URL?
    private(set) var isRecording = false
    private var startedAt: Date?

    // MARK: - Level meter (D021: audio-reactive HUD)

    private let levelLock = NSLock()
    private var _level: Double = 0

    /// Normalized 0...1 mic loudness (dB-mapped, -60 dB floor), written on the
    /// capture thread, read from the main thread via the lock. 0 when idle.
    var level: Double {
        levelLock.lock()
        defer { levelLock.unlock() }
        return _level
    }

    private func setLevel(_ v: Double) {
        levelLock.lock()
        _level = v
        levelLock.unlock()
    }

    /// Pure RMS → meter mapping: −60 dB floor maps to 0, −6 dB to 1.
    /// Testable without any audio hardware.
    static func meterLevel(rms: Double) -> Double {
        let clamped = min(max(rms, 1e-7), 1.0)
        let db = 20 * log10(clamped)
        return max(0, min(1, (db + 60) / 54))
    }

    var elapsedSeconds: Double {
        guard let startedAt, isRecording else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRecording else { return }

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
        ) else {
            throw AudioRecorderError.conversionFailed
        }
        guard let converter = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw AudioRecorderError.conversionFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voza-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 100...999)).wav")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw AudioRecorderError.conversionFailed
        }

        handle.write(Data(repeating: 0, count: 44)) // WAV header placeholder

        self.engine = engine
        targetFormat = target
        self.converter = converter
        outputURL = url
        fileHandle = handle
        pcmBytes = 0
        startedAt = Date()

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.enqueue(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        setLevel(0)
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil

        if let handle = fileHandle {
            try? handle.close()
        }
        fileHandle = nil

        guard let url = outputURL else { return nil }
        finalizeWAVHeader(at: url, pcmBytes: pcmBytes)
        // Full state reset: the file's ownership transfers to the caller; the
        // recorder must not retain anything from the finished session.
        outputURL = nil
        pcmBytes = 0
        startedAt = nil
        return url
    }

    func cancel() {
        if isRecording {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
        }
        isRecording = false
        setLevel(0)
        engine = nil
        converter = nil
        try? fileHandle?.close()
        fileHandle = nil
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        pcmBytes = 0
    }

    // MARK: - Conversion (thread-safe via serial queue inside AVAudioConverter)

    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let target = targetFormat else { return }

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

        // Level meter: RMS over this converted chunk (capture thread).
        var sum: Float = 0
        for i in 0..<frames { let s = channel[i]; sum += s * s }
        setLevel(Self.meterLevel(rms: Double(sqrt(sum / Float(frames)))))

        let bytes = Data(buffer: UnsafeBufferPointer(start: channel, count: frames))
        fileHandle?.write(bytes)
        pcmBytes += UInt64(bytes.count)
    }

    private func finalizeWAVHeader(at url: URL, pcmBytes: UInt64) {
        let header = Self.wavHeader(dataBytes: UInt32(pcmBytes))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seek(toOffset: 0)
            try? handle.write(contentsOf: header)
        }
    }

    /// Canonical 44-byte WAV header for 16 kHz mono Float32.
    /// FIX (audit v2 §3.5 + deeper): (1) the format code must be 3
    /// (WAVE_FORMAT_IEEE_FLOAT), not 1 — the payload IS Float32; (2) every field
    /// must carry an EXPLICIT integer type — bare literals infer Int and write
    /// 8 bytes each, producing a 64-byte malformed header (caught by the new
    /// smoke check; whisper-cli never consumed our own WAVs before, only
    /// external files, so it went unnoticed).
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
        appendU32(sampleRate * 4)                 // byte rate = rate × 1 ch × 4 bytes/sample
        appendU16(4)                              // block align
        appendU16(32)                             // bits per sample
        appendStr("data"); appendU32(dataBytes)
        return header
    }
}
