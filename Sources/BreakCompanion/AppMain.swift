import AppKit
import SwiftUI

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let store = CompanionStore()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    private var aboutWindow: NSWindow?
    private let updateController = UpdateController()
    private var keyMonitor: Any?
    private weak var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildMenuBarItem()
        updateController.onEvent = { [weak self] event in
            self?.handleUpdateEvent(event)
        }
        updateController.checkAutomatically()
        store.onSizeChange = { [weak self] mode in
            self?.resizePanel(for: mode)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.store.handleCompletionKey(
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode
            ) ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func buildPanel() {
        let panel = CompanionPanel(
            contentRect: NSRect(origin: .zero, size: size(for: store.mode)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: CompanionView(store: store))
        panel.setFrameOrigin(origin(for: panel.frame.size))
        store.companionHasKeyboardFocus = { [weak panel] in panel?.isKeyWindow ?? false }
        self.panel = panel
        resizePanel(for: store.mode)
    }

    private func buildMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: ProductIdentity.name)

        let menu = NSMenu()
        menu.addItem(withTitle: "Offer a break now", action: #selector(offerBreak), keyEquivalent: "")
        menu.addItem(withTitle: ProductIdentity.configureAreasMenuTitle, action: #selector(configureAreas), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: ProductIdentity.aboutMenuTitle, action: #selector(showAbout), keyEquivalent: "")
        let updateItem = menu.addItem(withTitle: updateController.menuTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateMenuItem = updateItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit \(ProductIdentity.name)", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func offerBreak() {
        store.noteCompanionInteraction()
        panel?.orderFrontRegardless()
        store.offerBreakNow()
    }

    @objc private func configureAreas() {
        store.noteCompanionInteraction()
        panel?.orderFrontRegardless()
        store.openAreaConfiguration()
    }

    func menuWillOpen(_ menu: NSMenu) {
        store.noteCompanionInteraction()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        store.noteCompanionInteraction()
    }

    func menuDidClose(_ menu: NSMenu) {
        store.noteCompanionInteraction()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(configureAreas) {
            return store.canOpenAreaConfiguration
        }
        if menuItem.action == #selector(checkForUpdates) {
            return !updateController.isBusy
        }
        return true
    }

    @objc private func showAbout() {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ProductIdentity.aboutMenuTitle.replacingOccurrences(of: "…", with: "")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutView(
            onClose: { [weak self] in self?.aboutWindow?.close() },
            onOpenReleases: { NSWorkspace.shared.open(ProductIdentity.releasesURL) }
        ))
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        switch updateController.state {
        case .available(let candidate):
            presentUpdate(candidate)
        case .ready(let downloaded):
            revealDownloadedUpdate(downloaded)
        case .checking, .downloading:
            break
        default:
            updateController.checkManually()
        }
    }

    private func handleUpdateEvent(_ event: UpdateController.Event) {
        updateMenuItem?.title = updateController.menuTitle
        switch event {
        case .stateChanged:
            break
        case .manualResult(let result):
            switch result {
            case .current:
                presentUpdateAlert(
                    title: "You’re up to date",
                    message: "\(ProductIdentity.name) \(ProductIdentity.currentVersion) is the newest verified version available from GitHub Releases."
                )
            case .available(let candidate):
                presentUpdate(candidate)
            case .failed(let failure):
                presentUpdateAlert(
                    title: "Update check unavailable",
                    message: "\(failure.localizedDescription)\n\nNothing was downloaded or changed. You can try again from the menu."
                )
            }
        case .downloaded(let downloaded):
            presentDownloadedUpdate(downloaded)
        case .downloadFailed(let failure):
            presentUpdateAlert(
                title: "Update was not downloaded",
                message: "\(failure.localizedDescription)\n\nNothing was opened or installed. The temporary download was removed; you can retry from the menu."
            )
        }
    }

    private func presentUpdate(_ candidate: UpdateCandidate) {
        let alert = NSAlert()
        alert.messageText = "A verified update is available"
        alert.informativeText = "Download \(ProductIdentity.name) \(candidate.version) from GitHub Releases? The ZIP and its SHA-256 checksum will be fetched over HTTPS and checked before anything is shown. Nothing is installed automatically."
        alert.addButton(withTitle: "Download and Verify")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            updateController.downloadAvailable()
        }
    }

    private func presentDownloadedUpdate(_ downloaded: DownloadedUpdate) {
        let alert = NSAlert()
        alert.messageText = "Update verified"
        alert.informativeText = "\(downloaded.candidate.artifactName) passed its SHA-256 check and is ready in a temporary folder. The running app was not replaced. Show it in Finder and open it yourself when ready."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            revealDownloadedUpdate(downloaded)
        }
    }

    private func revealDownloadedUpdate(_ downloaded: DownloadedUpdate) {
        guard FileManager.default.fileExists(atPath: downloaded.artifactURL.path) else {
            presentUpdateAlert(
                title: "Verified update is no longer available",
                message: "The temporary download was removed. Check for updates again to retry; the running app was not changed."
            )
            return
        }
        updateController.markReadyUpdateAsShown()
        NSWorkspace.shared.activateFileViewerSelecting([downloaded.artifactURL])
    }

    private func presentUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func resizePanel(for mode: CompanionStore.Mode) {
        guard let panel else { return }
        let newSize = size(for: mode)
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let right = panel.frame.maxX
        let top = panel.frame.maxY
        var frame = NSRect(x: right - newSize.width, y: top - newSize.height, width: newSize.width, height: newSize.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - newSize.width - 12)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - newSize.height - 12)
        panel.setFrame(frame, display: true, animate: true)
        switch mode {
        case .complete, .setup, .configuration:
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previouslyActiveApplication = frontmost
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        default:
            panel.orderFrontRegardless()
            if mode == .idle, let previouslyActiveApplication {
                previouslyActiveApplication.activate(options: [])
                self.previouslyActiveApplication = nil
            }
        }
    }

    private func size(for mode: CompanionStore.Mode) -> NSSize {
        switch mode {
        case .idle: return NSSize(width: 92, height: 92)
        case .setup, .configuration: return fittedSize(width: 370, minimumHeight: 480)
        case .checkIn: return fittedSize(width: 370, minimumHeight: 300)
        case .routine: return fittedSize(width: 370, minimumHeight: 390)
        case .complete: return fittedSize(width: 300, minimumHeight: 270)
        }
    }

    private func fittedSize(width: CGFloat, minimumHeight: CGFloat) -> NSSize {
        let measuring = NSHostingController(
            rootView: CompanionView(store: store).fixedSize(horizontal: false, vertical: true)
        )
        let needed = measuring.sizeThatFits(in: NSSize(width: width, height: 10_000)).height
        let available = (NSScreen.main?.visibleFrame.height ?? 600) - 44
        return NSSize(width: width, height: min(max(minimumHeight, needed.rounded(.up)), available))
    }

    private func origin(for size: NSSize) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: visible.maxX - size.width - 22, y: visible.maxY - size.height - 22)
    }
}

@main
enum BreakCompanionApp {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            exit(SelfCheck.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
