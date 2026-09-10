#if DEBUG
import SwiftUI

/// Xcode SwiftUI previews (owner-directed tooling, 2026-09-09) for the UI
/// polish loop. One file, zero edits to the views themselves.
///
/// Fixtures mutate only `@Published` fields of `AppState.shared`: construction
/// is side-effect-free (private init, no I/O) and the preview harness is an
/// isolated process — the real profile is never written from a preview.
/// Refresh()/pipeline paths are NOT invoked here on purpose.
@MainActor
private enum PreviewFixtures {
    static func entry(_ text: String, cleaned: Bool = false, minutesAgo: Int = 3) -> TranscriptEntry {
        TranscriptEntry(id: UUID(),
                        date: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60),
                        text: text,
                        cleaned: cleaned)
    }

    static var sampleHistory: [TranscriptEntry] {
        [entry("Draft kick at 92 BPM, sidechain the bass", minutesAgo: 1),
         entry("Remember to renew the domain before the 30th", cleaned: true, minutesAgo: 14),
         entry("La reunión se mueve al jueves a las diez", minutesAgo: 47)]
    }
}

// MARK: - Settings (tab container as the owner sees it)

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState.shared)
        .frame(width: 540, height: 440)
}

// MARK: - Status with a real perf suggestion rendered

#Preview("Status · perf suggestion") {
    let state = AppState.shared
    state.phase = .idle
    state.recent = PreviewFixtures.sampleHistory
    state.perfSuggestion = PerformanceMonitor.Suggestion(direction: .lighter, targetModelId: "small.en")
    return StatusView()
        .environmentObject(state)
        .frame(width: 520, height: 420)
}

// MARK: - Onboarding (mixed permission state)

#Preview("Onboarding · pending permissions") {
    OnboardingView()
        .environmentObject(AppState.shared)
        .frame(width: 420, height: 470)
}

// MARK: - Popover: idle + recording

#Preview("Popover · idle with history") {
    let state = AppState.shared
    state.phase = .idle
    state.recent = PreviewFixtures.sampleHistory
    return PopoverView()
        .environmentObject(state)
        .frame(width: 340, height: 420)
}

#Preview("Popover · recording (Literal)") {
    let state = AppState.shared
    state.phase = .recording(cleanup: false)
    state.elapsedSeconds = 4.2
    state.recent = PreviewFixtures.sampleHistory
    return PopoverView()
        .environmentObject(state)
        .frame(width: 340, height: 420)
}

// MARK: - Floating dictation HUD (D020)

#Preview("HUD · recording") {
    let state = AppState.shared
    state.phase = .recording(cleanup: false)
    state.elapsedSeconds = 7.0
    return DictationHUDView()
        .environmentObject(state)
        .frame(width: 190, height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("HUD · transcribing") {
    let state = AppState.shared
    state.phase = .transcribing
    return DictationHUDView()
        .environmentObject(state)
        .frame(width: 190, height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
}
#endif
