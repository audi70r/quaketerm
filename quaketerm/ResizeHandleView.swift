import AppKit

/// A thin drag handle at the bottom of the dropdown window.
/// Dragging it resizes the window by moving the bottom edge while
/// keeping the top edge pinned.
class ResizeHandleView: NSView {

    static let handleHeight: CGFloat = 6

    private var dragStartY: CGFloat = 0
    private var dragStartFrame: NSRect = .zero

    // Minimum/maximum window height constraints
    private let minHeight: CGFloat = 150
    private let maxHeightRatio: CGFloat = 0.9

    private var settingsObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        applyColors()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyColors()
            self?.needsDisplay = true
        }
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func applyColors() {
        let s = Settings.shared
        let base = s.backgroundColor.blended(withFraction: 0.3, of: .black) ?? s.backgroundColor
        layer?.backgroundColor = base.cgColor
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        dragStartY = NSEvent.mouseLocation.y
        dragStartFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window, let screen = window.screen ?? NSScreen.main else { return }

        let currentY = NSEvent.mouseLocation.y
        let delta = dragStartY - currentY  // positive = dragged down = taller window

        // The window's top edge stays fixed. We move the origin down and increase height.
        let topEdge = dragStartFrame.maxY
        var newHeight = dragStartFrame.height + delta
        let maxHeight = screen.frame.height * maxHeightRatio
        newHeight = max(minHeight, min(newHeight, maxHeight))

        let newOrigin = NSPoint(x: dragStartFrame.origin.x, y: topEdge - newHeight)
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: dragStartFrame.width, height: newHeight))
        window.setFrame(newFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window = self.window else { return }
        Settings.shared.windowHeight = window.frame.height
    }

    // MARK: - Visual indicator

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw a small centered grip line
        let gripWidth: CGFloat = 36
        let gripHeight: CGFloat = 2
        let gripRect = NSRect(
            x: (bounds.width - gripWidth) / 2,
            y: (bounds.height - gripHeight) / 2,
            width: gripWidth,
            height: gripHeight
        )
        NSColor(white: 0.35, alpha: 1.0).setFill()
        let path = NSBezierPath(roundedRect: gripRect, xRadius: 1, yRadius: 1)
        path.fill()
    }
}
