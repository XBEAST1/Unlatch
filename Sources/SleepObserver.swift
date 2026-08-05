import Foundation
import AppKit

final class SleepObserver {
    static let shared = SleepObserver()

    private init() {}

    func startObserving() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleSleepNotification),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSLog("[Unlatch] SleepObserver active - subscribed to sleep/wake notifications.")
    }

    @objc private func handleSleepNotification(_ notification: Notification) {
        NSLog("[Unlatch] Mac going to sleep. Stopping multitouch listener...")
        MultitouchEngine.shared.stop()
    }

    @objc private func handleWakeNotification(_ notification: Notification) {
        NSLog("[Unlatch] Mac woke up. Re-connecting trackpad listener in 500ms...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MultitouchEngine.shared.reconnect()
        }
    }
}
