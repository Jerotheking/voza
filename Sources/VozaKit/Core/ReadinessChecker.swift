import Foundation

/// One snapshot of everything Voza needs to work, used by the Status home.
struct Readiness {
    var micGranted: Bool
    var accessibilityGranted: Bool
    var engineFound: Bool
    var modelAvailable: Bool
    var brewAvailable: Bool
    var freeDiskMB: Int

    static let minimumDownloadMB = 400
}

enum ReadinessChecker {
    static func check() -> Readiness {
        Readiness(
            micGranted: Permissions.microphoneGranted,
            accessibilityGranted: Permissions.accessibilityGranted,
            engineFound: Transcriber.locateBinary() != nil,
            modelAvailable: !ModelManager.shared.downloadedModels().isEmpty,
            brewAvailable: BrewInstaller.brewPath() != nil,
            freeDiskMB: freeDiskMB()
        )
    }

    static func freeDiskMB() -> Int {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let bytes = values.volumeAvailableCapacity else { return Int.max }
        return Int(bytes / 1_048_576)
    }
}
