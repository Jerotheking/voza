import AppKit
import CoreGraphics

/// Places text on the clipboard, pastes via synthetic Cmd+V, then restores the
/// user's previous clipboard content.
enum Paster {

    private static let restoreTypes: [NSPasteboard.PasteboardType] = [
        .string, .rtf, .html, .png, .tiff, .fileURL,
    ]

    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let countBefore = pb.changeCount

        // Save first item's data so we can restore it afterwards.
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        if let first = pb.pasteboardItems?.first {
            for type in first.types where restoreTypes.contains(type) {
                if let data = first.data(forType: type) {
                    saved.append((type, data))
                }
            }
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(80_000) // let the target app see the new pasteboard

        sendCmdV()
        usleep(250_000) // give the app time to read the pasteboard

        // Restore previous clipboard only if nothing else touched it meanwhile.
        // After our write the count is countBefore+1; a higher count means someone
        // else copied something during the paste window — leave it alone.
        if pb.changeCount == countBefore + 1 {
            pb.clearContents()
            for (type, data) in saved {
                pb.setData(data, forType: type)
            }
        }
    }

    static func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)   // V = 9
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(20_000)
        up?.post(tap: .cghidEventTap)
    }
}
