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
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var fileHandle: FileHandle?
    private var pcmBytes: UInt64 = 0
    private(set) var outputURL: URL?
    private(set) var isRecording = false
    private var startedAt: Date?

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
        inputFormat = hardwareFormat
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
        return url
    }

    func cancel() {
        if isRecording {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
        }
        isRecording = false
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
        let bytes = Data(buffer: UnsafeBufferPointer(start: channel, count: frames))
        fileHandle?.write(bytes)
        pcmBytes += UInt64(bytes.count)
    }

    private func finalizeWAVHeader(at url: URL, pcmBytes: UInt64) {
        let sampleRate = UInt32(Config.targetSampleRate)
        let dataBytes = UInt32(pcmBytes)
        var header = Data()
        func append(_ value: some FixedWidthInteger) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
        }
        func appendStr(_ s: String) { header.append(Data(s.utf8)) }

        appendStr("RIFF"); append(36 + dataBytes); appendStr("WAVE")
        appendStr("fmt "); append(16); append(1) // PCM
        append(1)                                 // mono
        append(sampleRate)
        append(sampleRate * 4)                    // byte rate = rate * channels * 2 (float32 = 4)
        append(4)                                 // block align
        append(32)                                // bits per sample
        appendStr("data"); append(dataBytes)

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: 0)
        try? handle.write(contentsOf: header)
    }
}
