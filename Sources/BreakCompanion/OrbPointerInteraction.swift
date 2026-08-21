import AppKit
import SwiftUI

enum PointerMovementClassifier {
    enum Result: Equatable {
        case tap
        case drag
    }

    static let defaultDragThreshold: CGFloat = 4

    static func classify(
        from start: CGPoint,
        to end: CGPoint,
        threshold: CGFloat = defaultDragThreshold
    ) -> Result {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let distanceSquared = deltaX * deltaX + deltaY * deltaY
        return distanceSquared > threshold * threshold ? .drag : .tap
    }
}

struct OrbPointerInteraction: NSViewRepresentable {
    let onTap: () -> Void

    func makeNSView(context: Context) -> OrbPointerView {
        OrbPointerView(onTap: onTap)
    }

    func updateNSView(_ view: OrbPointerView, context: Context) {
        view.onTap = onTap
    }
}

final class OrbPointerView: NSView {
    var onTap: () -> Void

    private var pointerDownLocation: NSPoint?
    private var windowOriginAtPointerDown: NSPoint?
    private var didDrag = false

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        pointerDownLocation = NSEvent.mouseLocation
        windowOriginAtPointerDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pointerDownLocation, let windowOriginAtPointerDown, let window else { return }
        let currentLocation = NSEvent.mouseLocation

        if PointerMovementClassifier.classify(from: pointerDownLocation, to: currentLocation) == .drag {
            didDrag = true
        }

        guard didDrag else { return }
        window.setFrameOrigin(
            NSPoint(
                x: windowOriginAtPointerDown.x + currentLocation.x - pointerDownLocation.x,
                y: windowOriginAtPointerDown.y + currentLocation.y - pointerDownLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard let pointerDownLocation else {
            resetInteraction()
            return
        }

        let result = PointerMovementClassifier.classify(
            from: pointerDownLocation,
            to: NSEvent.mouseLocation
        )
        let shouldActivate = !didDrag && result == .tap
        resetInteraction()

        if shouldActivate {
            onTap()
        }
    }

    private func resetInteraction() {
        pointerDownLocation = nil
        windowOriginAtPointerDown = nil
        didDrag = false
    }
}
