import AppKit
import SwiftUI

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = CompanionStore()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private weak var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildMenuBarItem()
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
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func buildMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: ProductIdentity.name)

        let menu = NSMenu()
        menu.addItem(withTitle: "Offer a break now", action: #selector(offerBreak), keyEquivalent: "")
        menu.addItem(withTitle: ProductIdentity.configureAreasMenuTitle, action: #selector(configureAreas), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit \(ProductIdentity.name)", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func offerBreak() {
        panel?.orderFrontRegardless()
        store.offerBreakNow()
    }

    @objc private func configureAreas() {
        panel?.orderFrontRegardless()
        store.openAreaConfiguration()
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
        if mode == .complete {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previouslyActiveApplication = frontmost
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
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
        case .setup, .configuration: return NSSize(width: 370, height: 480)
        case .checkIn: return NSSize(width: 370, height: 300)
        case .routine: return NSSize(width: 370, height: 390)
        case .complete: return NSSize(width: 300, height: 270)
        }
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
