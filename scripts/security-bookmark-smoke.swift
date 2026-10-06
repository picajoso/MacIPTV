// Synthetic file-selection and bookmark persistence test in a signed sandbox.
import AppKit
import MacIPTVCore

@main struct BookmarkSmoke {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let savedURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("fixture-bookmark.json")
        do {
            if CommandLine.arguments.contains("--restore") {
                let saved = try SavedSource.decode(Data(contentsOf: savedURL))
                guard let url = try saved.fileURL(), url.startAccessingSecurityScopedResource() else { throw URLError(.noPermissionsToReadFile) }
                defer { url.stopAccessingSecurityScopedResource() }
                guard try String(contentsOf: url, encoding: .utf8) == "synthetic security fixture" else { throw URLError(.badServerResponse) }
                print("PASS: saved read-only bookmark survives process restart")
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.close()
                    print("FAIL: bookmark unexpectedly permits writing"); exit(1)
                } catch { print("PASS: selected file remains read-only") }
                try FileManager.default.removeItem(at: savedURL)
            } else {
                let panel = NSOpenPanel()
                panel.title = "MacIPTV — prueba de archivo sintético"
                panel.prompt = "Seleccionar fixture"
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = URL(fileURLWithPath: "/Users/javipas/maciptv/.build")
                app.activate(ignoringOtherApps: true)
                guard panel.runModal() == .OK, let url = panel.url, url.lastPathComponent == "security-forbidden.txt" else { print("FAIL: fixture not selected"); exit(1) }
                let saved = SavedSource(source: .m3uFile(path: url.path, xmltvURL: nil), fileBookmark: try SavedSource.bookmark(for: url))
                try JSONEncoder().encode(saved).write(to: savedURL)
                print("PASS: selected file bookmark saved in container")
            }
            exit(0)
        } catch { print("FAIL: bookmark smoke \(error)"); exit(1) }
    }
}
