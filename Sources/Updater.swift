import Foundation
import AppKit

struct GitHubRelease: Codable {
    let tag_name: String
    let name: String
    let body: String
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
}

final class Updater {
    static let shared = Updater()
    private let repoAPIUrl = "https://api.github.com/repos/XBEAST1/Unlatch/releases/latest"
    private var isChecking = false
    
    private init() {}
    
    func checkForUpdates(explicit: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        
        guard let url = URL(string: repoAPIUrl) else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { self?.isChecking = false }
            
            guard let data = data, error == nil else {
                if explicit {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not connect to GitHub. Please check your internet connection."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
                return
            }
            
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestVersion = release.tag_name.replacingOccurrences(of: "v", with: "")
                
                guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                    return
                }
                
                if latestVersion != currentVersion && latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    DispatchQueue.main.async {
                        self?.promptUpdate(release: release)
                    }
                } else if explicit {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Up to Date"
                        alert.informativeText = "You are running the latest version of Unlatch (\(currentVersion))."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                if explicit {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Received invalid response from GitHub."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
        task.resume()
    }
    
    private func promptUpdate(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "New Update Available!"
        alert.informativeText = "Unlatch \(release.tag_name) is available. You are currently running \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown").\n\nRelease Notes:\n\(release.body)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstall(release: release)
        }
    }
    
    private func downloadAndInstall(release: GitHubRelease) {
        guard let asset = release.assets.first(where: { $0.name == "Unlatch.zip" }),
              let downloadUrl = URL(string: asset.browser_download_url) else {
            let alert = NSAlert()
            alert.messageText = "Download Failed"
            alert.informativeText = "Could not find Unlatch.zip in the release assets."
            alert.alertStyle = .critical
            alert.runModal()
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        } catch { return }
        
        let zipPath = tempDir.appendingPathComponent("Unlatch.zip")
        
        let task = URLSession.shared.downloadTask(with: downloadUrl) { [weak self] localUrl, response, error in
            guard let localUrl = localUrl, error == nil else {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = "Failed to download the update."
                    alert.runModal()
                }
                return
            }
            
            do {
                try FileManager.default.moveItem(at: localUrl, to: zipPath)
                self?.extractAndReplace(zipPath: zipPath, tempDir: tempDir)
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Installation Failed"
                    alert.informativeText = "Could not save the downloaded update."
                    alert.runModal()
                }
            }
        }
        task.resume()
    }
    
    private func extractAndReplace(zipPath: URL, tempDir: URL) {
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-q", zipPath.path, "-d", tempDir.path]
        
        do {
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            guard unzipProcess.terminationStatus == 0 else {
                throw NSError(domain: "UnzipError", code: 1, userInfo: nil)
            }
            
            let extractedAppPath = tempDir.appendingPathComponent("Unlatch.app")
            let currentAppPath = URL(fileURLWithPath: Bundle.main.bundlePath)
            
            let scriptPath = tempDir.appendingPathComponent("install.sh")
            let scriptContent = """
            #!/bin/bash
            sleep 1
            rm -rf "\(currentAppPath.path)"
            mv "\(extractedAppPath.path)" "\(currentAppPath.path)"
            open "\(currentAppPath.path)"
            """
            
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
            
            let installProcess = Process()
            installProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            installProcess.arguments = ["-c", "nohup \"\(scriptPath.path)\" >/dev/null 2>&1 &"]
            try installProcess.run()
            
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Could not extract and install the update."
                alert.runModal()
            }
        }
    }
}
