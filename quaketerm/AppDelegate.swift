import Carbon.HIToolbox
import Cocoa

/// Entry point: wires the AppDelegate and starts the run loop.
@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSAnimationDelegate {

    private var window: DropDownWindow!
    private var tabContainerVC: TabContainerViewController!
    private(set) var isVisible = false

    private var statusItem: NSStatusItem!
    private var settingsWC: SettingsWindowController?
    private var hotkeyRef: EventHotKeyRef?
    private var settingsObserver: Any?


    // Slide animation duration in seconds
    private let animationDuration: TimeInterval = 0.25

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Run as a menu-bar-only (tray) app — no Dock icon
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupMenu()
        setupWindow()
        setupHotkey()

        // Re-register hotkey when settings change
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupHotkey()
        }

        // Show the terminal on launch
        toggleTerminal()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Status item (tray)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal",
                                   accessibilityDescription: "QuakeTerm")
            // Fallback for older macOS without "terminal" symbol
            if button.image == nil {
                button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                       accessibilityDescription: "QuakeTerm")
            }
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Terminal",
                     action: #selector(toggleTerminalAction),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Settings...",
                     action: #selector(openSettings),
                     keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit QuakeTerm",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func toggleTerminalAction() {
        toggleTerminal()
    }

    // MARK: - Window setup

    private func windowHeight(for screen: NSScreen) -> CGFloat {
        let saved = Settings.shared.windowHeight
        if saved > 0 {
            return min(saved, screen.frame.height * 0.9)
        }
        return screen.frame.height * Settings.shared.defaultHeightRatio
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let height = windowHeight(for: screen)

        let offScreenFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY,
            width: screenFrame.width,
            height: height
        )

        window = DropDownWindow(contentRect: offScreenFrame)

        tabContainerVC = TabContainerViewController()
        window.contentViewController = tabContainerVC
    }

    // MARK: - Global hotkey (Carbon RegisterEventHotKey)

    /// Unique four-char identifier for our hotkey
    private let hotkeySignature: UInt32 = {
        let chars: [UInt8] = [0x51, 0x54, 0x48, 0x4B] // "QTHK"
        return UInt32(chars[0]) << 24 | UInt32(chars[1]) << 16 | UInt32(chars[2]) << 8 | UInt32(chars[3])
    }()

    private func setupHotkey() {
        // Unregister previous hotkey if any
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }

        let s = Settings.shared
        let keyCode = UInt32(s.hotkeyKeyCode)
        let carbonMods = carbonModifiers(from: NSEvent.ModifierFlags(rawValue: s.hotkeyModifiers))

        // Install a Carbon event handler on first call
        installCarbonHandlerOnce()

        // Register the hotkey with the system
        let hotkeyID = EventHotKeyID(signature: hotkeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hotkeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotkeyRef = ref
        }
    }

    /// Convert Cocoa modifier flags to Carbon modifier mask
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        return mods
    }

    private static var carbonHandlerInstalled = false

    private func installCarbonHandlerOnce() {
        guard !Self.carbonHandlerInstalled else { return }
        Self.carbonHandlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }

            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotkeyID)
            guard status == noErr else { return status }

            // Find our AppDelegate and toggle
            if let delegate = NSApp.delegate as? AppDelegate {
                DispatchQueue.main.async {
                    delegate.toggleTerminal()
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings...",
                        action: #selector(openSettings),
                        keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit QuakeTerm",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (copy/paste via responder chain)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Shell menu (tab/split shortcuts)
        let shellMenuItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Tab",
                          action: #selector(newTab),
                          keyEquivalent: "t")
        shellMenu.addItem(withTitle: "Close Pane",
                          action: #selector(closePane),
                          keyEquivalent: "w")
        shellMenu.addItem(NSMenuItem.separator())
        shellMenu.addItem(withTitle: "Split Vertically",
                          action: #selector(splitVertically),
                          keyEquivalent: "d")

        let nextTabItem = NSMenuItem(title: "Next Tab",
                                     action: #selector(nextTab),
                                     keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous Tab",
                                     action: #selector(previousTab),
                                     keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(prevTabItem)

        shellMenu.addItem(NSMenuItem.separator())

        let moveTabForward = NSMenuItem(title: "Move Tab Forward",
                                        action: #selector(moveTabForward),
                                        keyEquivalent: "]")
        moveTabForward.keyEquivalentModifierMask = [.shift, .control]
        shellMenu.addItem(moveTabForward)

        let moveTabBackward = NSMenuItem(title: "Move Tab Backward",
                                         action: #selector(moveTabBackward),
                                         keyEquivalent: "[")
        moveTabBackward.keyEquivalentModifierMask = [.shift, .control]
        shellMenu.addItem(moveTabBackward)

        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newTab() { tabContainerVC.addTab() }
    @objc private func closePane() { tabContainerVC.closeCurrentPane() }
    @objc private func splitVertically() { tabContainerVC.splitCurrentPane() }
    @objc private func nextTab() { tabContainerVC.selectNextTab() }
    @objc private func previousTab() { tabContainerVC.selectPreviousTab() }
    @objc private func moveTabForward() { tabContainerVC.moveCurrentTabForward() }
    @objc private func moveTabBackward() { tabContainerVC.moveCurrentTabBackward() }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
        }
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Toggle

    private var currentAnimation: NSViewAnimation?

    func toggleTerminal() {
        currentAnimation?.stop()

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let wh = isVisible ? window.frame.height : windowHeight(for: screen)
        let menuBarHeight = screenFrame.maxY - screen.visibleFrame.maxY
        let windowSize = NSSize(width: screenFrame.width, height: wh)

        let hiddenFrame = NSRect(
            origin: NSPoint(x: screenFrame.origin.x, y: screenFrame.maxY),
            size: windowSize
        )
        let shownFrame = NSRect(
            origin: NSPoint(x: screenFrame.origin.x,
                            y: screenFrame.maxY - menuBarHeight - wh),
            size: windowSize
        )

        if isVisible {
            let animInfo: [NSViewAnimation.Key: Any] = [
                .target: window!,
                .startFrame: NSValue(rect: shownFrame),
                .endFrame: NSValue(rect: hiddenFrame)
            ]
            let anim = NSViewAnimation(viewAnimations: [animInfo])
            anim.duration = animationDuration
            anim.animationCurve = .easeInOut
            anim.delegate = self
            anim.start()
            currentAnimation = anim
        } else {
            window.setFrame(hiddenFrame, display: false)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)

            let animInfo: [NSViewAnimation.Key: Any] = [
                .target: window!,
                .startFrame: NSValue(rect: hiddenFrame),
                .endFrame: NSValue(rect: shownFrame)
            ]
            let anim = NSViewAnimation(viewAnimations: [animInfo])
            anim.duration = animationDuration
            anim.animationCurve = .easeInOut
            anim.delegate = self
            anim.start()
            currentAnimation = anim
        }

        isVisible.toggle()
    }

    // MARK: - NSAnimationDelegate

    func animationDidEnd(_ animation: NSAnimation) {
        if !isVisible {
            window.orderOut(nil)
            // Give focus back to whatever app is currently behind us
            NSApp.hide(nil)
        } else {
            window.makeKey()
        }
        currentAnimation = nil
    }
}

