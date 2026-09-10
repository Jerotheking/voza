import XCTest
import SwiftUI
@testable import VozaKit

/// Verifies the previewed views actually RENDER (SwiftUI tree builds and
/// lays out with non-trivial geometry) — compilation alone proves nothing.
///
/// Host design: ONE static, process-lifetime window + hosting controller.
/// Creating AppKit windows per-test and tearing them down made XCTest's
/// leak checker segfault during autorelease-pool drain (reproduced twice,
/// crash in `XCTMemoryChecker _assertInvalidObjectsDeallocatedAfterScope`),
/// so nothing AppKit-owned is deallocated while a test is running.
/// Nothing here touches the real profile: fixtures only set @Published
/// fields; no pipeline is invoked.
@MainActor
final class PreviewRenderTests: XCTestCase {

    private static var host: NSHostingController<AnyView>!
    private static var hostWindow: NSWindow!

    override class func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        hostWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                              styleMask: [.titled],
                              backing: .buffered, defer: false)
        host = NSHostingController(rootView: AnyView(EmptyView()))
        hostWindow.contentView = host.view
    }

    private func assertRenders(_ view: some View, name: String, file: StaticString = #filePath, line: UInt = #line) {
        Self.host.rootView = AnyView(view)
        Self.host.view.layoutSubtreeIfNeeded()
        let size = Self.host.view.fittingSize
        XCTAssertGreaterThan(size.width, 80, "\(name): width did not lay out", file: file, line: line)
        XCTAssertGreaterThan(size.height, 80, "\(name): height did not lay out", file: file, line: line)
        Self.host.rootView = AnyView(EmptyView())
    }

    func testSettingsRenders() {
        assertRenders(SettingsView().environmentObject(AppState.shared), name: "SettingsView")
    }

    func testStatusViewRendersWithPerfSuggestion() {
        let state = AppState.shared
        state.phase = .idle
        state.recent = []
        state.perfSuggestion = PerformanceMonitor.Suggestion(direction: .lighter, targetModelId: "small.en")
        assertRenders(StatusView().environmentObject(state), name: "StatusView")
    }

    func testOnboardingRenders() {
        assertRenders(OnboardingView().environmentObject(AppState.shared), name: "OnboardingView")
    }

    func testPopoverRendersInBothPhases() {
        let state = AppState.shared
        for phase in [VozaPhase.idle, .recording(cleanup: false), .transcribing] {
            state.phase = phase
            state.recent = []
            assertRenders(PopoverView().environmentObject(state), name: "PopoverView(\(phase))")
        }
    }
}
