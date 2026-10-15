import Foundation

enum AudioAssetError: LocalizedError, Equatable, Sendable {
    case fileMissing
    case headerTooShort(Int)
    case invalidMagic
    case invalidFormatCode(UInt16)
    case invalidChannels(UInt16)
    case invalidSampleRate(UInt32)
    case invalidBitsPerSample(UInt16)
    case payloadSizeMismatch(headerBytes: UInt32, actualBytes: UInt64)

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "WAV file does not exist"
        case .headerTooShort(let n):
            return "WAV header too short (\(n) bytes, expected 44)"
        case .invalidMagic:
            return "WAV file missing RIFF/WAVE/fmt/data markers"
        case .invalidFormatCode(let code):
            return "WAV format code must be 3 (IEEE Float32), got \(code)"
        case .invalidChannels(let ch):
            return "WAV channel count must be 1 (mono), got \(ch)"
        case .invalidSampleRate(let rate):
            return "WAV sample rate invalid: \(rate)"
        case .invalidBitsPerSample(let bits):
            return "WAV bitsPerSample must be 32, got \(bits)"
        case .payloadSizeMismatch(let expected, let actual):
            return "WAV payload size mismatch (header=\(expected), actual=\(actual))"
        }
    }
}

/// Verified audio recording or imported fixture with explicit file ownership (V05 / D059).
///
/// Invariant (`make-illegal-states-unrepresentable`):
/// - Temporary recordings created by `AudioRecorder` have `ownsFile == true` and are deleted
///   by `cleanupIfOwned()`.
/// - Read-only imported files have `ownsFile == false` and are never deleted by `cleanupIfOwned()`.
struct AudioAsset: Equatable, Sendable {
    let url: URL
    let frameCount: Int
    let sampleRate: Double
    let pcmBytes: UInt64
    let ownsFile: Bool

    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(frameCount) / sampleRate
    }

    /// Removes the backing WAV file on disk ONLY when owned by Voza (`ownsFile == true`).
    func cleanupIfOwned() {
        guard ownsFile else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Parses and validates a 44-byte canonical IEEE Float32 WAV file on disk (V05-AC01).
    static func inspectWAV(at url: URL, ownsFile: Bool = true) throws -> AudioAsset {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? UInt64,
              let handle = try? FileHandle(forReadingFrom: url) else {
            throw AudioAssetError.fileMissing
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 44)) ?? Data()
        guard fileSize >= 44, data.count == 44 else {
            throw AudioAssetError.headerTooShort(Int(fileSize))
        }

        func readU16(_ offset: Int) -> UInt16 {
            data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        }
        func readU32(_ offset: Int) -> UInt32 {
            data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        }

        let riff = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        let wave = String(data: data.subdata(in: 8..<12), encoding: .ascii)
        let fmt  = String(data: data.subdata(in: 12..<16), encoding: .ascii)
        let dataTag = String(data: data.subdata(in: 36..<40), encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE", fmt == "fmt ", dataTag == "data" else {
            throw AudioAssetError.invalidMagic
        }

        let formatCode = readU16(20)
        guard formatCode == 3 else {
            throw AudioAssetError.invalidFormatCode(formatCode)
        }
        let channels = readU16(22)
        guard channels == 1 else {
            throw AudioAssetError.invalidChannels(channels)
        }
        let sampleRate = readU32(24)
        guard sampleRate > 0 else {
            throw AudioAssetError.invalidSampleRate(sampleRate)
        }
        let bitsPerSample = readU16(34)
        guard bitsPerSample == 32 else {
            throw AudioAssetError.invalidBitsPerSample(bitsPerSample)
        }

        let dataBytesHeader = readU32(40)
        let actualPayload = fileSize - 44
        guard UInt64(dataBytesHeader) == actualPayload else {
            throw AudioAssetError.payloadSizeMismatch(headerBytes: dataBytesHeader, actualBytes: actualPayload)
        }

        let frames = Int(actualPayload / 4)
        return AudioAsset(
            url: url,
            frameCount: frames,
            sampleRate: Double(sampleRate),
            pcmBytes: actualPayload,
            ownsFile: ownsFile
        )
    }
}
