import AppKit

// a bug report: a copy of the end of the log beside it, shown in finder, with the app's and the mac's
// versions at the top, and github's new issue page opened beside it. nothing is sent from the
// app. the user looks the log over and attaches it themselves
@MainActor
enum BugReport {
    static let newIssue = URL(string: "https://github.com/JonathanGarro/wemmick/issues/new")!
    // the log is never trimmed, and a report needs only the recent part
    private static let tailBytes: UInt64 = 2_000_000

    static func start() {
        let alert = NSAlert()
        alert.messageText = "Report a Bug"
        alert.informativeText = """
            Wemmick saves a copy of its log, shows it in Finder, and opens a new issue on GitHub, \
            where you can say what happened and drag the log in.

            The log lists meeting, file and people's names, but no transcripts or notes. Look it \
            over before sharing it. Nothing is sent until you do.
            """
        alert.addButton(withTitle: "Save Log and Open GitHub")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let file = try saveLog(setup: await setup())
                NSWorkspace.shared.activateFileViewerSelecting([file])
                NSWorkspace.shared.open(issue(log: file.lastPathComponent))
            } catch {
                let failed = NSAlert(error: error)
                failed.runModal()
            }
        }
    }

    // what's set up, from the server, as yes or no rather than names or keys. its own copy of
    // the log's end is left off, since the whole recent log follows. empty when the server
    // isn't running
    private static func setup() async -> String {
        guard let data = try? await API.data(["api", "diagnostics"]) else { return "" }
        let text = String(decoding: data, as: UTF8.self)
        return text.components(separatedBy: "\nlog:").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Server.logURL])
    }

    // "Wemmick 0.1.5 (153), macOS 26.1, Apple M3 Max, 64 GB"
    static var about: String {
        let info = Bundle.main.infoDictionary
        let version = "Wemmick \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "macOS \(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        let memory = "\(ProcessInfo.processInfo.physicalMemory >> 30) GB"
        return [version, macOS, chip, memory].compactMap { $0 }.joined(separator: ", ")
    }

    private static var chip: String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var name = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0) == 0 else { return nil }
        return String(cString: name)
    }

    private static func saveLog(setup: String) throws -> URL {
        let handle = try FileHandle(forReadingFrom: Server.logURL)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        var text = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        // starting partway through, the first line is cut, so it goes
        if size > tailBytes, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits)",
                                               timeZone: .current, calendar: .current))
        // beside the log rather than on the desktop, which would need a permission
        let file = Server.logURL.deletingLastPathComponent().appending(path: "Wemmick log \(stamp).txt")
        try ([about, setup, "log:", text].filter { !$0.isEmpty }.joined(separator: "\n\n")).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func issue(log name: String) -> URL {
        var components = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "body", value: """
            **What happened**


            **What you expected**


            **Steps to make it happen again**


            ---
            \(about)

            The log is "\(name)", in the Finder window Wemmick opened. Drag it here, after looking it over.
            """)]
        return components.url ?? newIssue
    }
}
