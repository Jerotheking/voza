import Foundation

/// One snapshot of everything Voza needs to work, used by the Status home.
struct Readiness {
    var micGranted: Bool
    var accessibilityGranted: Bool
    var inputMonitoringGranted: Bool
    var hotkeyTapActive: Bool
    var engineFound: Bool
    var modelAvailable: Bool
    var brewAvailable: Bool
    var freeDiskMB: Int
}

enum ReadinessChecker {
    static func check() -> Readiness {
        Readiness(
            micGranted: Permissions.microphoneGranted,
            accessibilityGranted: Permissions.accessibilityGranted,
            inputMonitoringGranted: Permissions.inputMonitoringGranted,
            hotkeyTapActive: HotKeyManager.shared.tapActive,
            engineFound: Transcriber.locateBinary() != nil,
            modelAvailable: !ModelManager.shared.downloadedModels().isEmpty,
            brewAvailable: BrewInstaller.brewPath() != nil,
            freeDiskMB: freeDiskMB()
        )
    }

    /// Free disk needed to download a given model: its size plus a working margin
    /// for hashing/verification. Per-model, not a fixed constant (audit v2 §3.10).
    static func requiredFreeMB(for model: WhisperModel) -> Int {
        Int((Int64(model.bytes) + 256_000_000) / 1_048_576)
    }

    static func freeDiskMB() -> Int {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let bytes = values.volumeAvailableCapacity else { return Int.max }
        return Int(bytes / 1_048_576)
    }
}
