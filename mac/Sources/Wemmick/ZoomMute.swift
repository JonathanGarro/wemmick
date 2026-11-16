import AppKit
import ApplicationServices

// whether you're muted in zoom, read from its Meeting menu, which says "Mute audio" while
// you're heard and "Unmute audio" while you're muted. zoom has no local api for it, and it
// keeps the mic open while muted, so core audio can't tell either. reading another app's
// menus takes the accessibility permission. only the zoom app is seen, not zoom in a browser
enum ZoomMute {
    static let bundleID = "us.zoom.xos"

    // whether wemmick may read other apps' menus. prompt shows macos's request the first time
    static func allowed(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // true when muted, false when heard, nil when it can't tell: zoom isn't open or isn't in
    // a meeting, the permission isn't given, or the menu reads some other way, as in another
    // language. nil is taken as heard, so nothing is lost when zoom changes its menus
    static func isMuted() -> Bool? {
        guard allowed(),
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        // a busy zoom answers late, and the next check comes soon anyway
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let menuBar = element(kAXMenuBarAttribute, of: app) else { return nil }
        for item in children(of: menuBar) where title(of: item) == "Meeting" {
            for menu in children(of: item) {
                for entry in children(of: menu) {
                    let name = title(of: entry)?.lowercased() ?? ""
                    if name.hasPrefix("unmute audio") { return true }
                    if name.hasPrefix("mute audio") { return false }
                }
            }
        }
        return nil
    }

    private static func value(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    // swift's casts to a core foundation type don't check it, so the type id is checked here
    private static func element(_ name: String, of parent: AXUIElement) -> AXUIElement? {
        guard let value = value(name, of: parent), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let list = value(kAXChildrenAttribute, of: element) as? [CFTypeRef] else { return [] }
        return list.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private static func title(of element: AXUIElement) -> String? {
        value(kAXTitleAttribute, of: element) as? String
    }
}
