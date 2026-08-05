import Foundation
import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var enabledItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        _ = checkAccessibilityPermission(prompt: false)

        SleepObserver.shared.startObserving()

        let success = MultitouchEngine.shared.start()
        if !success {
            statusItem?.button?.title = "Unlatch!"
        }
        
        // Silently check for updates on launch
        Updater.shared.checkForUpdates(explicit: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MultitouchEngine.shared.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "u.square", accessibilityDescription: "Unlatch") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Unlatch"
            }
            button.toolTip = "Unlatch - 3-Finger Drag Release"
        }

        let menu = NSMenu(title: "")
        let aboutItem = NSMenuItem(
            title: "About Unlatch",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let enabledMenuItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)
        self.enabledItem = enabledMenuItem

        let accessMenuItem = NSMenuItem(
            title: "Request Accessibility Permission",
            action: #selector(requestAccessibilityPermission(_:)),
            keyEquivalent: ""
        )
        accessMenuItem.target = self
        menu.addItem(accessMenuItem)
        self.accessibilityItem = accessMenuItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Unlatch",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        let current = MultitouchEngine.shared.getEnabled()
        let next = !current
        MultitouchEngine.shared.setEnabled(next)
        enabledItem?.state = next ? .on : .off
    }

    @objc private func requestAccessibilityPermission(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission"
        alert.informativeText = "Unlatch requires Accessibility permission to function.\n\nIf you previously granted it but the app isn't working, macOS might have revoked it after an app update. To fix this:\n\n1. Select Unlatch in System Settings.\n2. Click the minus (-) button to remove it completely.\n3. Relaunch Unlatch to re-grant it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        // Trigger the native prompt just in case it hasn't been asked yet
        _ = checkAccessibilityPermission(prompt: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        Updater.shared.checkForUpdates(explicit: true)
    }

    @discardableResult
    private func checkAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        accessibilityItem?.title = isTrusted ? "Accessibility Granted" : "Request Accessibility Permission"
        accessibilityItem?.state = isTrusted ? .on : .off
        return isTrusted
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "About Unlatch"
        alert.informativeText = "A lightweight macOS menu bar utility for instantly removing the release delay after a three-finger drag.\n\nMade with 🖤 by xbeast."
        alert.alertStyle = .informational
        
        if let symbol = NSImage(systemSymbolName: "u.square", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            if let configuredSymbol = symbol.withSymbolConfiguration(config) {
                alert.icon = configuredSymbol
            }
        }
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/xbeast1/Unlatch") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
