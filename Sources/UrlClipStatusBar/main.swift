import AppKit
import UrlClipCore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var store: LinkStore?
    private var lastError: String?
    private var patternPreferences = PatternPreferences.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "link.circle", accessibilityDescription: "Clipboard Pattern Tracker")
            button.image?.isTemplate = true
        }

        do {
            store = try LinkStore()
        } catch {
            lastError = error.localizedDescription
        }

        statusItem.menu = buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        let matches = ClipboardExtractor.extractMatches(from: text, patterns: patternPreferences.activePatterns)
        guard !matches.isEmpty else {
            return
        }

        do {
            _ = try store?.capture(matches: matches, clipboardText: text)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Clipboard Pattern Tracker", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if let stats = try? store?.stats() {
            let statsItem = NSMenuItem(
                title: "\(stats.uniqueURLs) items, \(stats.capturedCopies) copies",
                action: nil,
                keyEquivalent: ""
            )
            statsItem.isEnabled = false
            menu.addItem(statsItem)
        }

        if let lastError {
            let errorItem = NSMenuItem(title: lastError, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        addRecentLinks(to: menu)
        menu.addItem(.separator())

        menu.addItem(patternsMenuItem())
        menu.addItem(NSMenuItem(title: "Open Database Folder", action: #selector(openDatabaseFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        return menu
    }

    private func addRecentLinks(to menu: NSMenu) {
        guard let links = try? store?.recent(limit: 12), !links.isEmpty else {
            let emptyItem = NSMenuItem(title: "No items captured yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for link in links {
            let item = NSMenuItem(title: displayTitle(for: link), action: #selector(openOrCopyItem(_:)), keyEquivalent: "")
            item.representedObject = link.url
            item.toolTip = link.url
            menu.addItem(item)
        }
    }

    private func displayTitle(for link: CapturedLink) -> String {
        let count = link.copyCount > 1 ? " (\(link.copyCount)x)" : ""
        guard
            ClipboardExtractor.isLikelyURL(link.url),
            let components = URLComponents(string: URLExtractor.normalizedURL(link.url))
        else {
            return "\(link.url)\(count)"
        }

        let host = components.host ?? link.url
        let path = components.path == "/" ? "" : components.path
        return "\(host)\(path)\(count)"
    }

    private func patternsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Patterns", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for pattern in ClipboardPatternCatalog.predefined {
            let patternItem = NSMenuItem(title: pattern.name, action: #selector(togglePredefinedPattern(_:)), keyEquivalent: "")
            patternItem.representedObject = pattern.id
            patternItem.state = patternPreferences.enabledPredefinedPatternIDs.contains(pattern.id) ? .on : .off
            submenu.addItem(patternItem)
        }

        submenu.addItem(.separator())

        if patternPreferences.customPatterns.isEmpty {
            let emptyItem = NSMenuItem(title: "No custom regexes", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for pattern in patternPreferences.customPatterns {
                let patternItem = NSMenuItem(title: pattern.name, action: #selector(toggleCustomPattern(_:)), keyEquivalent: "")
                patternItem.representedObject = pattern.id
                patternItem.state = patternPreferences.enabledCustomPatternIDs.contains(pattern.id) ? .on : .off
                patternItem.toolTip = pattern.pattern
                submenu.addItem(patternItem)
            }
        }

        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "Add Custom Regex...", action: #selector(addCustomRegex), keyEquivalent: ""))
        if !patternPreferences.customPatterns.isEmpty {
            submenu.addItem(NSMenuItem(title: "Remove Custom Regex...", action: #selector(removeCustomRegex), keyEquivalent: ""))
        }
        submenu.addItem(NSMenuItem(title: "Reset Patterns", action: #selector(resetPatterns), keyEquivalent: ""))

        item.submenu = submenu
        return item
    }

    @objc private func openOrCopyItem(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else {
            return
        }

        if ClipboardExtractor.isLikelyURL(value), let url = URL(string: URLExtractor.normalizedURL(value)) {
            NSWorkspace.shared.open(url)
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    @objc private func openDatabaseFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([LinkStore.defaultURL])
    }

    @objc private func refreshMenu() {
        statusItem.menu = buildMenu()
    }

    @objc private func togglePredefinedPattern(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        patternPreferences.togglePredefinedPattern(id: id)
        patternPreferences.save()
        statusItem.menu = buildMenu()
    }

    @objc private func toggleCustomPattern(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        patternPreferences.toggleCustomPattern(id: id)
        patternPreferences.save()
        statusItem.menu = buildMenu()
    }

    @objc private func addCustomRegex() {
        guard let pattern = promptForCustomRegex() else {
            return
        }

        patternPreferences.customPatterns.append(pattern)
        patternPreferences.enabledCustomPatternIDs.insert(pattern.id)
        patternPreferences.save()
        statusItem.menu = buildMenu()
    }

    @objc private func removeCustomRegex() {
        guard let patternID = promptForCustomRegexRemoval() else {
            return
        }

        patternPreferences.customPatterns.removeAll { $0.id == patternID }
        patternPreferences.enabledCustomPatternIDs.remove(patternID)
        patternPreferences.save()
        statusItem.menu = buildMenu()
    }

    @objc private func resetPatterns() {
        patternPreferences = PatternPreferences()
        patternPreferences.save()
        statusItem.menu = buildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func promptForCustomRegex() -> ClipboardPattern? {
        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Name"

        let regexField = NSTextField(string: "")
        regexField.placeholderString = "Regex pattern"

        let stack = NSStackView(views: [nameField, regexField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 52)

        let alert = NSAlert()
        alert.messageText = "Add Custom Regex"
        alert.informativeText = "If the regex has capture groups, the first matched group is saved."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let regex = regexField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !regex.isEmpty, (try? NSRegularExpression(pattern: regex)) != nil else {
            lastError = "Custom regex is invalid."
            return nil
        }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClipboardPattern(
            id: "custom.\(UUID().uuidString)",
            name: name.isEmpty ? "Custom Regex" : name,
            pattern: regex
        )
    }

    private func promptForCustomRegexRemoval() -> String? {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        for pattern in patternPreferences.customPatterns {
            popup.addItem(withTitle: pattern.name)
            popup.lastItem?.representedObject = pattern.id
            popup.lastItem?.toolTip = pattern.pattern
        }

        let alert = NSAlert()
        alert.messageText = "Remove Custom Regex"
        alert.accessoryView = popup
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return popup.selectedItem?.representedObject as? String
    }
}

private struct PatternPreferences: Codable {
    private static let defaultsKey = "ClipboardPatternPreferences"

    var enabledPredefinedPatternIDs = ClipboardPatternCatalog.defaultEnabledPatternIDs
    var customPatterns: [ClipboardPattern] = []
    var enabledCustomPatternIDs: Set<String> = []

    var activePatterns: [ClipboardPattern] {
        let predefined = ClipboardPatternCatalog.predefined.filter {
            enabledPredefinedPatternIDs.contains($0.id)
        }
        let custom = customPatterns.filter {
            enabledCustomPatternIDs.contains($0.id)
        }
        return predefined + custom
    }

    static func load() -> PatternPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let preferences = try? JSONDecoder().decode(PatternPreferences.self, from: data)
        else {
            return PatternPreferences()
        }

        return preferences
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    mutating func togglePredefinedPattern(id: String) {
        if enabledPredefinedPatternIDs.contains(id) {
            enabledPredefinedPatternIDs.remove(id)
        } else {
            enabledPredefinedPatternIDs.insert(id)
        }
    }

    mutating func toggleCustomPattern(id: String) {
        if enabledCustomPatternIDs.contains(id) {
            enabledCustomPatternIDs.remove(id)
        } else {
            enabledCustomPatternIDs.insert(id)
        }
    }
}

@main
private enum URLClipStatusBarApp {
    @MainActor private static var delegate: AppDelegate?

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate

        app.run()
    }
}
