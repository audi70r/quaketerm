import AppKit
import Darwin
import SwiftTerm

/// Hosts a single SwiftTerm LocalProcessTerminalView running zsh.
/// Used as a leaf in the split tree within a tab.
class TerminalPaneViewController: NSViewController, LocalProcessTerminalViewDelegate {

    private(set) var terminalView: LocalProcessTerminalView!
    private var settingsObserver: Any?
    private var mouseMonitor: Any?
    private var cwdTimer: Timer?
    private(set) var lastReportedCwd: String?

    /// Called when the shell title changes (e.g. via OSC escape).
    var onTitleChanged: ((TerminalPaneViewController, String) -> Void)?
    /// Called when the shell's current directory changes.
    var onDirectoryChanged: ((TerminalPaneViewController, String) -> Void)?
    /// Called when the shell process terminates.
    var onProcessTerminated: ((TerminalPaneViewController) -> Void)?
    /// Called when the terminal view gains focus (e.g. user clicks in split pane).
    var onBecameFocused: ((TerminalPaneViewController) -> Void)?

    /// If set, the shell launches in this directory instead of $HOME.
    var initialDirectory: String?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        terminalView = DroppableTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.processDelegate = self
        view.addSubview(terminalView)

        applySettings()
        launchShell(in: initialDirectory)
        startCwdPolling()

        // Detect clicks in this pane to track focus across split panes
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            let loc = self.terminalView.convert(event.locationInWindow, from: nil)
            if self.terminalView.bounds.contains(loc) {
                self.onBecameFocused?(self)
            }
            return event
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Re-apply settings now that the view is in a window,
        // so window-level properties (blur, opacity) take effect.
        applySettings()
    }

    deinit {
        cwdTimer?.invalidate()
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CWD polling

    private func startCwdPolling() {
        cwdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollCurrentDirectory()
        }
    }

    private func pollCurrentDirectory() {
        let shellPid = terminalView.process.shellPid
        guard shellPid > 0 else { return }

        // Always get the cwd from the shell process
        let cwd = cwdOfProcess(shellPid)
        let dirName: String
        if let cwd, !cwd.isEmpty {
            let last = (cwd as NSString).lastPathComponent
            dirName = last.isEmpty ? "Terminal" : last
        } else {
            dirName = "Terminal"
        }

        // Check if there's a foreground process running (not the shell itself)
        var title = dirName
        if let fgName = foregroundProcessName() {
            title += " | \(fgName)"
        }

        if title != lastReportedCwd {
            lastReportedCwd = title
            onDirectoryChanged?(self, title)
        }
    }

    /// Gets the current working directory of a process via proc_pidinfo.
    private func cwdOfProcess(_ pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(size))
        guard ret == size else { return nil }

        return withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cpath in
                String(cString: cpath)
            }
        }
    }

    /// Uses tcgetpgrp on the PTY to find the foreground process group,
    /// then returns its name if it's not the shell itself.
    private func foregroundProcessName() -> String? {
        let fd = terminalView.process.childfd
        let shellPid = terminalView.process.shellPid
        guard fd >= 0, shellPid > 0 else { return nil }

        let fgpg = tcgetpgrp(fd)
        guard fgpg > 0, fgpg != shellPid else { return nil }

        return processName(of: fgpg)
    }

    /// Returns the process name for a given PID, filtering out shells.
    private func processName(of pid: pid_t) -> String? {
        var name = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let ret = proc_name(pid, &name, UInt32(name.count))
        guard ret > 0 else { return nil }
        let result = String(cString: name)
        let shells: Set<String> = ["zsh", "bash", "fish", "sh", "login"]
        if shells.contains(result) { return nil }
        return result
    }

    private func applySettings() {
        let s = Settings.shared
        terminalView.font = s.font
        terminalView.nativeForegroundColor = s.foregroundColor

        let hasImage = s.backgroundImage != nil
        let hasTransparency = s.windowTransparency > 0
        let needsTransparentBg = hasImage || hasTransparency

        // Terminal background alpha:
        // - Transparency slider controls how see-through the background is
        // - When a background image is set, make the terminal bg mostly transparent
        //   so the image shows through (image has its own opacity slider)
        if needsTransparentBg {
            var bgAlpha: CGFloat = 1.0 - s.windowTransparency
            if hasImage {
                bgAlpha = min(bgAlpha, 0.15)
            }
            terminalView.nativeBackgroundColor = s.backgroundColor.withAlphaComponent(bgAlpha)
            // SwiftTerm's setter also sets layer?.backgroundColor — override to clear
            terminalView.layer?.backgroundColor = NSColor.clear.cgColor
            terminalView.layer?.isOpaque = false
        } else {
            terminalView.nativeBackgroundColor = s.backgroundColor
            terminalView.layer?.isOpaque = true
        }

        // Window must be non-opaque for transparency to work,
        // but alphaValue stays 1.0 so text and controls remain fully visible
        if let window = view.window {
            window.alphaValue = 1.0
            window.isOpaque = false
            window.backgroundColor = .clear

            // Gaussian blur of content behind the window
            let blurRadius = Int(s.backdropBlurAmount * 64)
            DropDownWindow.setBackgroundBlurRadius(window: window, radius: blurRadius)
        }

        terminalView.needsDisplay = true
    }

    /// The shell's current working directory, read from the kernel.
    var currentDirectory: String? {
        let pid = terminalView.process.shellPid
        guard pid > 0 else { return nil }
        return cwdOfProcess(pid)
    }

    func launchShell(in directory: String? = nil) {
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let startDir = directory ?? NSHomeDirectory()
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-l"],
            environment: env,
            execName: nil,
            currentDirectory: startDir
        )
    }

    /// Make this pane the first responder so it receives keyboard input.
    func focus() {
        view.window?.makeFirstResponder(terminalView)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChanged?(self, title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        onDirectoryChanged?(self, directory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let callback = onProcessTerminated {
            callback(self)
        } else {
            launchShell()
        }
    }
}

// MARK: - Drag-and-drop support

/// Subclass that accepts file drops.
class DroppableTerminalView: LocalProcessTerminalView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                                options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }

        let paths = urls.map { shellEscape($0.path) }
        let text = paths.joined(separator: " ")
        insertText(text, replacementRange: NSRange(location: 0, length: 0))
        return true
    }

    /// Escapes a path for safe use in a shell command.
    private func shellEscape(_ path: String) -> String {
        // Single-quote the path, escaping any embedded single quotes
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
