import Foundation
import ApplicationServices
import CoreGraphics

enum EventDispatcher {
    static func postLeftMouseUp() {
        guard let current = CGEvent(source: nil) else { return }
        let location = current.location

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)
    }
}
