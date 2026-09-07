import Foundation

/// Records real-world transcription speed (real-time factor = transcribe time ÷ audio time)
/// per model, and turns evidence into model suggestions. Never forces anything.
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    struct Suggestion: Equatable {
        enum Direction: String { case lighter, heavier }
        let direction: Direction
        let targetModelId: String
        var suppressionKey: String { "\(targetModelId):\(direction.rawValue)" }
    }

    private struct Records: Codable {
        var byModel: [String: [Double]] = [:]
    }

    private var records = Records()
    private let file = URL(fileURLWithPath: Config.appSupportDirectory + "/perf.json")
    private let maxSamples = 20
    private static let dismissalDays = 14.0

    init() {
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode(Records.self, from: data) {
            records = decoded
        }
    }

    func record(rtf: Double, model: String) {
        guard rtf > 0, rtf < 100 else { return }
        var samples = records.byModel[model] ?? []
        samples.append(rtf)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        records.byModel[model] = samples
        save()
    }

    /// Median RTF for a model, nil if not enough data.
    func medianRTF(model: String) -> Double? {
        guard var samples = records.byModel[model], samples.count >= 3 else { return nil }
        samples.sort()
        let mid = samples.count / 2
        return samples.count.isMultiple(of: 2)
            ? (samples[mid - 1] + samples[mid]) / 2
            : samples[mid]
    }

    /// Human speed label, e.g. "1.8× realtime". Nil without data.
    func speedLabel(model: String) -> String? {
        guard let median = medianRTF(model: model), median > 0 else { return nil }
        return String(format: "%.1f× realtime", 1 / median)
    }

    /// Evidence-based suggestion, or nil. Requires ≥3 samples on the current model.
    func suggestion(currentModel: String, ramGB: Int) -> Suggestion? {
        guard let median = medianRTF(model: currentModel),
              let index = WhisperCatalog.all.firstIndex(where: { $0.id == currentModel }) else { return nil }

        let direction: Suggestion.Direction
        if median > 0.5 && index > 0 {
            direction = .lighter
        } else if median < 0.08 && ramGB >= 32 && index < WhisperCatalog.all.count - 1 {
            direction = .heavier
        } else {
            return nil
        }

        let targetIndex = direction == .lighter ? index - 1 : index + 1
        let target = WhisperCatalog.all[targetIndex]
        let candidate = Suggestion(direction: direction, targetModelId: target.id)

        // Respect dismissal window.
        let dismissed = UserDefaults.standard.object(forKey: "voza.perfDismissed." + candidate.suppressionKey) as? Date
        if let dismissed, Date().timeIntervalSince(dismissed) < Self.dismissalDays * 86_400 {
            return nil
        }
        return candidate
    }

    func dismiss(_ suggestion: Suggestion) {
        UserDefaults.standard.set(Date(), forKey: "voza.perfDismissed." + suggestion.suppressionKey)
    }

    // MARK: - Persistence + test hooks

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: file, options: .atomic)
        }
    }

    func _test_setSamples(_ rtfs: [Double], model: String) {
        records.byModel[model] = rtfs
        save()
    }

    func _test_clear() {
        records = Records()
        save()
    }
}
