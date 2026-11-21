import AppKit
import Foundation

// starts and stops an audio hijack session alongside a recording, as a backup. audio hijack
// has no applescript dictionary or url to start a session, but it runs a .ahcommand file
// (javascript) opened with it, when "allow execution of external scripts" is on under its
// settings, advanced. the script writes what it did to a file, which is the only way to hear
// back: no answer within a few seconds means scripts are off, or audio hijack didn't open
enum AudioHijack {
    static let bundleID = "com.rogueamoeba.audiohijack"

    enum Outcome: String {
        case started, already, missing, stopped
    }

    static var installed: Bool { appURL != nil }

    private static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    // starts the session unless it's already running. nil when audio hijack didn't answer
    static func start(session: String) async -> Outcome? {
        await run(session: session, script: "s.running ? \"already\" : (s.start(), \"started\")")
    }

    static func stop(session: String) async -> Outcome? {
        await run(session: session, script: "(s.stop(), \"stopped\")")
    }

    private static func run(session: String, script: String) async -> Outcome? {
        guard let appURL else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "wemmick-audiohijack")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let command = folder.appending(path: "\(id).ahcommand")
        let result = folder.appending(path: "\(id).txt")
        defer {
            try? FileManager.default.removeItem(at: command)
            try? FileManager.default.removeItem(at: result)
        }
        // the name and the shell command go in as json strings, so quotes in them can't break out
        func json(_ s: String) -> String {
            (try? String(data: JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)) ?? "\"\""
        }
        // the temporary folder's path has no single quotes, so it's safe quoted for the shell
        let source = """
            var s = app.sessionWithName(\(json(session)));
            var r = s ? \(script) : "missing";
            app.runShellCommand("/bin/echo " + r + " > " + \(json("'\(result.path)'")));
            """
        do { try source.write(to: command, atomically: true, encoding: .utf8) } catch { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do { _ = try await NSWorkspace.shared.open([command], withApplicationAt: appURL, configuration: configuration) } catch {
            Server.log("couldn't open Audio Hijack: \(error.localizedDescription)")
            return nil
        }
        // audio hijack takes a few seconds to answer when it has to open first
        for _ in 0..<100 {
            if let text = try? String(contentsOf: result, encoding: .utf8),
               let outcome = Outcome(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return outcome
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
