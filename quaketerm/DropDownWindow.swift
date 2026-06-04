import AppKit

/// Borderless NSPanel that serves as the dropdown terminal container.
/// Configured to float above all windows and appear on every Space.
class DropDownWindow: NSPanel {

    init(contentRect: NSRect) {
        // Borderless + utility panel style. NonactivatingPanel prevents
        // stealing focus from other apps when we just want to peek.
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Float above normal windows
        level = .floating

        // Visible on all Spaces and survives Expose/Mission Control
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Transparent titlebar-less appearance
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Allow the panel to become key so it can receive keyboard input
        // (overriding default borderless behavior which refuses key status)
        isMovableByWindowBackground = false
    }

    // MARK: - Key window overrides

    /// Borderless windows refuse key status by default.
    /// We must allow it so the terminal can receive keyboard events.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Prevent the system from constraining our frame to keep
    /// the titlebar on screen — we intentionally position offscreen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    /// Controls the duration of setFrame(_:display:animate:) animations.
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        return 0.25
    }

    // MARK: - Backdrop blur

    /// Applies a gaussian blur to the content behind the window.
    /// Uses the private CGSSetWindowBackgroundBlurRadius API.
    /// `radius` of 0 disables the blur.
    static func setBackgroundBlurRadius(window: NSWindow, radius: Int) {
        typealias CGSConnectionID = UInt32
        typealias CGSSetWindowBackgroundBlurRadiusFn =
            @convention(c) (CGSConnectionID, Int32, Int) -> Int32

        guard let cgs = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) else {
            return
        }
        defer { dlclose(cgs) }

        guard let connSym = dlsym(cgs, "CGSMainConnectionID"),
              let blurSym = dlsym(cgs, "CGSSetWindowBackgroundBlurRadius") else {
            return
        }

        let CGSMainConnectionID = unsafeBitCast(connSym, to: (@convention(c) () -> CGSConnectionID).self)
        let CGSSetWindowBackgroundBlurRadius = unsafeBitCast(blurSym, to: CGSSetWindowBackgroundBlurRadiusFn.self)

        let conn = CGSMainConnectionID()
        _ = CGSSetWindowBackgroundBlurRadius(conn, Int32(window.windowNumber), radius)
    }
}
