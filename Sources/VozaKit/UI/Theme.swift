import SwiftUI

/// Design tokens — the single source of truth for Voza's look.
enum Theme {
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.28)   // coral
    static let cardCorner: CGFloat = 10
    static let popoverWidth: CGFloat = 420
    // Recording/ok states use the system Color.red/.green on purpose: that's
    // the universal macOS convention, and inventing brand colors for them
    // would only confuse.
}
