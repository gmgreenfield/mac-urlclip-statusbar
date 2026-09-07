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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "link.circle", accessibilityDescription: "URL Clipboard Tracker")
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

        let urls = URLExtractor.extractURLs(from: text)
        guard !urls.isEmpty else {
            return
        }

        do {
            _ = try store?.capture(urls: urls, clipboardText: text)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "URL Clipboard Tracker", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if let stats = try? store?.stats() {
            let statsItem = NSMenuItem(
                title: "\(stats.uniqueURLs) URLs, \(stats.capturedCopies) copies",
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

        menu.addItem(NSMenuItem(title: "Open Database Folder", action: #selector(openDatabaseFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        return menu
    }

    private func addRecentLinks(to menu: NSMenu) {
        guard let links = try? store?.recent(limit: 12), !links.isEmpty else {
            let emptyItem = NSMenuItem(title: "No URLs captured yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for link in links {
            let item = NSMenuItem(title: displayTitle(for: link), action: #selector(openLink(_:)), keyEquivalent: "")
            item.representedObject = link.url
            item.toolTip = link.url
            menu.addItem(item)
        }
    }

    private func displayTitle(for link: CapturedLink) -> String {
        guard let components = URLComponents(string: link.normalizedURL) else {
            return link.url
        }

        let host = components.host ?? link.url
        let path = components.path == "/" ? "" : components.path
        let count = link.copyCount > 1 ? " (\(link.copyCount)x)" : ""
        return "\(host)\(path)\(count)"
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        guard
            let rawURL = sender.representedObject as? String,
            let url = URL(string: URLExtractor.normalizedURL(rawURL))
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openDatabaseFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([LinkStore.defaultURL])
    }

    @objc private func refreshMenu() {
        statusItem.menu = buildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
