import AppKit
import SwiftUI

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isMovableByWindowBackground = true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate, NSWindowDelegate {
    private let store = CompanionStore(stateStore: CompanionStateStore())
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    private var offerMenuItem: NSMenuItem?
    private var aboutWindow: NSWindow?
    private let updateController = UpdateController()
    private lazy var updateFlow = UpdateFlowCoordinator(controller: updateController)
    private var updateDialogWindow: NSWindow?
    private var keyMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private weak var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildMenuBarItem()
        updateFlow.onStateChange = { [weak self] _ in
            self?.updateFlowDidChange()
        }
        updateFlow.checkAutomatically()
        store.onSizeChange = { [weak self] mode in
            self?.updateMenuState()
            self?.resizePanel(for: mode)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.store.handleCompletionKey(
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode
            ) ? nil : event
        }
        store.startClock()
        observeSystemBoundaries()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.persistState()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func observeSystemBoundaries() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let boundaryNotifications: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        workspaceObservers = boundaryNotifications.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.store.noteSystemInactive()
                }
            }
        }
    }

    private func buildPanel() {
        let panel = CompanionPanel(
            contentRect: NSRect(origin: .zero, size: size(for: store.mode)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        // AppKit moves the panel from its non-control background. SwiftUI controls,
        // links, text selection, and accessibility actions retain their own hit testing.
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
        // AppKit's responder-chain auto-validation can disable an accessory app's
        // private action while a panel is changing state. These are explicit app
        // actions, so keep them enabled and validate only the update operation below.
        menu.autoenablesItems = false
        let offerItem = menu.addItem(withTitle: "Offer a break now", action: #selector(offerBreak), keyEquivalent: "")
        offerMenuItem = offerItem
        let settingsItem = menu.addItem(withTitle: ProductIdentity.settingsMenuTitle, action: #selector(configureAreas), keyEquivalent: "")
        settingsItem.isEnabled = true
        menu.addItem(withTitle: ProductIdentity.diagnosticsMenuTitle, action: #selector(copyDiagnostics), keyEquivalent: "")
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
        updateMenuState()
    }

    private func updateMenuState() {
        switch store.mode {
        case .checkIn where store.statusText != nil:
            offerMenuItem?.title = "Check-in scheduled"
        case .checkIn where store.isCheckInCollapsed:
            offerMenuItem?.title = "Show pause choices"
        case .checkIn:
            offerMenuItem?.title = "Pause offer pending"
        default:
            offerMenuItem?.title = "Offer a break now"
        }
        updateMenuItem?.isEnabled = !updateController.isBusy
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

    @objc private func copyDiagnostics() {
        store.noteCompanionInteraction()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.diagnosticReport(), forType: .string)
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
            // Settings is intentionally actionable from idle, pending, routine,
            // and completion states. The store preserves the state on return.
            return true
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
        switch updateFlow.state {
        case .available:
            showUpdateDialog()
        case .downloaded:
            showUpdateDialog()
        case .checking, .downloading, .installing:
            break
        default:
            updateFlow.checkManually()
        }
    }

    private func updateFlowDidChange() {
        updateMenuItem?.title = updateController.menuTitle
        updateMenuState()
        guard updateFlow.shouldPresentDialog else {
            dismissUpdateDialog()
            return
        }
        showUpdateDialog()
        if case .installing = updateFlow.state {
            updateDialogWindow?.standardWindowButton(.closeButton)?.isHidden = true
            NSApp.terminate(nil)
        }
    }

    private func showUpdateDialog() {
        guard let model = updateFlow.dialogModel else { return }
        if let window = updateDialogWindow {
            window.contentView = NSHostingView(rootView: UpdateDialogView(
                model: model,
                onPrimaryAction: { [weak self] in self?.handleUpdatePrimaryAction() },
                onSecondaryAction: { [weak self] in self?.handleUpdateSecondaryAction() }
            ))
            window.setContentSize(NSSize(width: 370, height: model.showsProgress ? 210 : 190))
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: model.showsProgress ? 210 : 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ProductIdentity.name
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: UpdateDialogView(
            model: model,
            onPrimaryAction: { [weak self] in self?.handleUpdatePrimaryAction() },
            onSecondaryAction: { [weak self] in self?.handleUpdateSecondaryAction() }
        ))
        window.center()
        updateDialogWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleUpdatePrimaryAction() {
        guard let model = updateFlow.dialogModel else { return }
        switch model.phase {
        case .available, .downloaded:
            updateFlow.installAvailableUpdate()
        case .failed:
            updateFlow.retry()
        case .current, .success:
            updateFlow.cancelOrDismiss()
        case .checking, .downloading, .installing:
            break
        }
    }

    private func handleUpdateSecondaryAction() {
        updateFlow.cancelOrDismiss()
    }

    private func dismissUpdateDialog() {
        updateDialogWindow?.orderOut(nil)
        updateDialogWindow = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === updateDialogWindow else { return true }
        updateFlow.cancelOrDismiss()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === updateDialogWindow else { return }
        updateFlow.cancelOrDismiss()
        updateDialogWindow = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func resizePanel(for mode: CompanionStore.Mode) {
        guard let panel else { return }
        let screen = screenForPanel(panel)
        let visible = screen?.visibleFrame ?? .zero
        let requestedSize = size(for: mode, screen: screen)
        let newSize = visible.isEmpty
            ? requestedSize
            : NSSize(
                width: min(requestedSize.width, max(1, visible.width - 24)),
                height: min(requestedSize.height, max(1, visible.height - 24))
            )
        let right = panel.frame.maxX
        let top = panel.frame.maxY
        var frame = NSRect(
            x: right - newSize.width,
            y: top - newSize.height,
            width: newSize.width,
            height: newSize.height
        )
        if !visible.isEmpty {
            let minimumX = visible.minX + 12
            let maximumX = max(minimumX, visible.maxX - frame.width - 12)
            let minimumY = visible.minY + 12
            let maximumY = max(minimumY, visible.maxY - frame.height - 12)
            frame.origin.x = min(max(frame.origin.x, minimumX), maximumX)
            frame.origin.y = min(max(frame.origin.y, minimumY), maximumY)
        }

        // Set the final frame before ordering the window. Animating this transition
        // could leave an automatic offer at the old orb frame for a run-loop turn,
        // which made a real pending offer appear to have been missed.
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()

        if mode == .checkIn, store.isCheckInCollapsed {
            if let previouslyActiveApplication {
                previouslyActiveApplication.activate(options: [])
                self.previouslyActiveApplication = nil
            }
            return
        }

        switch mode {
        case .complete, .setup, .configuration:
            rememberFrontmostApplication()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        case .checkIn where store.activityRecoveryExplanation == nil:
            rememberFrontmostApplication()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        default:
            if mode == .idle, let previouslyActiveApplication {
                previouslyActiveApplication.activate(options: [])
                self.previouslyActiveApplication = nil
            }
        }
    }

    private func rememberFrontmostApplication() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmost
        }
    }

    private func screenForPanel(_ panel: NSPanel) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.visibleFrame.contains(mouseLocation) })
            ?? panel.screen
            ?? NSScreen.main
    }

    private func size(for mode: CompanionStore.Mode, screen: NSScreen? = nil) -> NSSize {
        switch mode {
        case .idle: return NSSize(width: 92, height: 92)
        case .setup, .configuration: return fittedSize(width: 370, minimumHeight: 480, screen: screen)
        case .checkIn where store.isCheckInCollapsed: return size(for: .idle, screen: screen)
        case .checkIn:
            // Keep the offer compact and deterministic. A measured hosting view can
            // report the window's unconstrained height, leaving a large blank panel
            // and making the actual top-right control easy to miss.
            return NSSize(width: 370, height: 330)
        case .routine: return fittedSize(width: 370, minimumHeight: 390, screen: screen)
        case .complete: return fittedSize(width: 300, minimumHeight: 270, screen: screen)
        }
    }

    private func fittedSize(width: CGFloat, minimumHeight: CGFloat, screen: NSScreen? = nil) -> NSSize {
        let measuring = NSHostingController(
            rootView: CompanionView(store: store).fixedSize(horizontal: false, vertical: true)
        )
        let needed = measuring.sizeThatFits(in: NSSize(width: width, height: 10_000)).height
        let available = (screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 600) - 44
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
        if CommandLine.arguments.contains("--diagnostics") {
            let report = MainActor.assumeIsolated {
                CompanionStore().diagnosticReport(
                    activityIsActive: LocalActivitySignal.current().workActivityIdle < CompanionStore.defaultIdleThreshold
                )
            }
            print(report)
            exit(EXIT_SUCCESS)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
