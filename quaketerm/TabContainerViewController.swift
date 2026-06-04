import AppKit
import SwiftTerm

/// Top-level view controller that manages tabs and the split tree within each tab.
/// Sits as the window's contentViewController.
class TabContainerViewController: NSViewController, TabBarViewDelegate {

    private var tabs: [TerminalTab] = []
    private var selectedTabIndex: Int = 0
    private var splitContainers: [UUID: SplitContainerView] = [:]

    private let tabBar = TabBarView()
    private let contentArea = NSView()
    private let resizeHandle = ResizeHandleView()

    // Shared background image (one per window, behind all split panes)
    private var backgroundImageView: NSImageView?
    private var imageDimOverlay: NSView?
    private var settingsObserver: Any?

    // Layout constraints that change when tab bar position flips
    private var tabBarTopConstraint: NSLayoutConstraint?
    private var tabBarBottomConstraint: NSLayoutConstraint?
    private var contentTopToTabBar: NSLayoutConstraint?
    private var contentTopToView: NSLayoutConstraint?
    private var contentBottomToTabBar: NSLayoutConstraint?
    private var contentBottomToResize: NSLayoutConstraint?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true

        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)

        contentArea.translatesAutoresizingMaskIntoConstraints = false
        contentArea.autoresizesSubviews = true
        view.addSubview(contentArea)

        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resizeHandle)

        // Background image layer (behind all split panes, inside contentArea)
        // Use autoresizing masks (not Auto Layout) to avoid the image's
        // intrinsic content size inflating the window.
        let imgView = NSImageView(frame: contentArea.bounds)
        imgView.autoresizingMask = [.width, .height]
        imgView.imageScaling = .scaleAxesIndependently
        imgView.isHidden = true
        contentArea.addSubview(imgView)
        backgroundImageView = imgView

        // Dark overlay on top of the image to control brightness
        let dimView = NSView(frame: contentArea.bounds)
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        dimView.isHidden = true
        contentArea.addSubview(dimView)
        imageDimOverlay = dimView

        // Positional constraints (toggled based on tab bar position)
        tabBarTopConstraint = tabBar.topAnchor.constraint(equalTo: view.topAnchor)
        tabBarBottomConstraint = tabBar.bottomAnchor.constraint(equalTo: resizeHandle.topAnchor)
        contentTopToTabBar = contentArea.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
        contentTopToView = contentArea.topAnchor.constraint(equalTo: view.topAnchor)
        contentBottomToTabBar = contentArea.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
        contentBottomToResize = contentArea.bottomAnchor.constraint(equalTo: resizeHandle.topAnchor)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.barHeight),

            contentArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            resizeHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: ResizeHandleView.handleHeight),
        ])

        applyTabBarPosition()
        applyBackgroundImage()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyBackgroundImage()
            self?.applyTabBarPosition()
        }

        addTab()
    }

    // MARK: - Tab management

    func addTab() {
        let pane = makePane()
        let tab = TerminalTab(pane: pane)
        tabs.append(tab)

        let container = SplitContainerView(tab: tab)
        splitContainers[tab.id] = container

        selectTab(at: tabs.count - 1)
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs[index]

        // Terminate all shells in this tab
        for pane in tab.allPanes {
            pane.terminalView.terminate()
            pane.removeFromParent()
        }

        splitContainers[tab.id]?.removeFromSuperview()
        splitContainers.removeValue(forKey: tab.id)
        tabs.remove(at: index)

        if tabs.isEmpty {
            // Last tab closed — hide the window
            view.window?.orderOut(nil)
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.toggleTerminal()
            }
            // Re-add a tab for next toggle
            addTab()
            return
        }

        let newIndex = min(index, tabs.count - 1)
        selectTab(at: newIndex)
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabIndex = index

        // Remove old split containers (keep background image and dim overlay)
        for sub in contentArea.subviews {
            if sub !== backgroundImageView && sub !== imageDimOverlay {
                sub.removeFromSuperview()
            }
        }
        let tab = tabs[index]
        if let container = splitContainers[tab.id] {
            container.frame = contentArea.bounds
            container.autoresizingMask = [.width, .height]
            contentArea.addSubview(container)
        }

        refreshTabBar()

        // Focus the tab's focused pane (or the first one)
        let pane = tab.focusedPane ?? tab.allPanes.first
        pane?.focus()
    }

    // MARK: - Split management

    func splitCurrentPane() {
        guard let tab = currentTab, let pane = currentFocusedPane else { return }
        let newPane = makePane(startingDirectory: pane.currentDirectory)

        if let container = splitContainers[tab.id] {
            container.splitPane(pane, with: newPane)
            tab.focusedPane = newPane
            newPane.focus()
        }
    }

    func closeCurrentPane() {
        guard let tab = currentTab, let pane = currentFocusedPane else { return }

        let panes = tab.allPanes
        if panes.count <= 1 {
            // Only one pane — close the entire tab
            closeTab(at: selectedTabIndex)
            return
        }

        // Find a neighbor to focus
        if let idx = panes.firstIndex(where: { $0 === pane }) {
            let nextFocus = idx > 0 ? panes[idx - 1] : panes[min(idx + 1, panes.count - 1)]
            tab.focusedPane = nextFocus

            if let container = splitContainers[tab.id] {
                container.removePane(pane)
            }
            pane.removeFromParent()
            nextFocus.focus()
        }
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        selectTab(at: (selectedTabIndex + 1) % tabs.count)
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        selectTab(at: (selectedTabIndex - 1 + tabs.count) % tabs.count)
    }

    func moveCurrentTabForward() {
        guard tabs.count > 1 else { return }
        let dest = (selectedTabIndex + 1) % tabs.count
        moveTab(from: selectedTabIndex, to: dest)
    }

    func moveCurrentTabBackward() {
        guard tabs.count > 1 else { return }
        let dest = (selectedTabIndex - 1 + tabs.count) % tabs.count
        moveTab(from: selectedTabIndex, to: dest)
    }

    private func moveTab(from source: Int, to dest: Int) {
        guard source != dest,
              tabs.indices.contains(source),
              tabs.indices.contains(dest) else { return }

        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: dest)
        selectedTabIndex = dest

        tabBar.moveButton(from: source, to: dest)
        refreshTabBar()
    }

    func focusNextPane() {
        guard let tab = currentTab else { return }
        let panes = tab.allPanes
        guard panes.count > 1,
              let current = tab.focusedPane,
              let idx = panes.firstIndex(where: { $0 === current }) else { return }
        let next = panes[(idx + 1) % panes.count]
        tab.focusedPane = next
        next.focus()
    }

    func focusPreviousPane() {
        guard let tab = currentTab else { return }
        let panes = tab.allPanes
        guard panes.count > 1,
              let current = tab.focusedPane,
              let idx = panes.firstIndex(where: { $0 === current }) else { return }
        let prev = panes[(idx - 1 + panes.count) % panes.count]
        tab.focusedPane = prev
        prev.focus()
    }

    // MARK: - TabBarViewDelegate

    func tabBarDidSelectTab(at index: Int) {
        selectTab(at: index)
    }

    func tabBarDidCloseTab(at index: Int) {
        closeTab(at: index)
    }

    func tabBarDidClickAddTab() {
        addTab()
    }

    func tabBarDidMoveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard tabs.indices.contains(sourceIndex),
              tabs.indices.contains(destinationIndex) else { return }

        let movedTab = tabs.remove(at: sourceIndex)
        tabs.insert(movedTab, at: destinationIndex)

        // Update selected index to follow the moved tab if needed
        if selectedTabIndex == sourceIndex {
            selectedTabIndex = destinationIndex
        } else if sourceIndex < selectedTabIndex && destinationIndex >= selectedTabIndex {
            selectedTabIndex -= 1
        } else if sourceIndex > selectedTabIndex && destinationIndex <= selectedTabIndex {
            selectedTabIndex += 1
        }

        refreshTabBar()
    }

    // MARK: - Keyboard shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        let command = event.modifierFlags.contains(.command)

        // Shift+Control (no Command): move tab order
        let control = event.modifierFlags.contains(.control)
        if shift && control && !command {
            switch event.charactersIgnoringModifiers {
            case "]":
                moveCurrentTabForward()
                return true
            case "[":
                moveCurrentTabBackward()
                return true
            default:
                break
            }
        }

        guard command else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "t" where !shift && !option:
            addTab()
            return true
        case "w" where !shift && !option:
            closeCurrentPane()
            return true
        case "d" where !shift && !option:
            splitCurrentPane()
            return true
        case "]" where shift && !option:
            selectNextTab()
            return true
        case "[" where shift && !option:
            selectPreviousTab()
            return true
        case let chars where option && !shift:
            if chars == NSRightArrowFunctionKey.description || event.keyCode == 124 {
                focusNextPane()
                return true
            } else if chars == NSLeftArrowFunctionKey.description || event.keyCode == 123 {
                focusPreviousPane()
                return true
            }
            return super.performKeyEquivalent(with: event)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Tab Bar Position

    private func applyTabBarPosition() {
        let onBottom = Settings.shared.tabBarOnBottom

        // Deactivate all positional constraints
        tabBarTopConstraint?.isActive = false
        tabBarBottomConstraint?.isActive = false
        contentTopToTabBar?.isActive = false
        contentTopToView?.isActive = false
        contentBottomToTabBar?.isActive = false
        contentBottomToResize?.isActive = false

        if onBottom {
            // Tab bar sits above the resize handle, content fills above it
            tabBarBottomConstraint?.isActive = true
            contentTopToView?.isActive = true
            contentBottomToTabBar?.isActive = true
        } else {
            // Tab bar at top (default)
            tabBarTopConstraint?.isActive = true
            contentTopToTabBar?.isActive = true
            contentBottomToResize?.isActive = true
        }

        view.layoutSubtreeIfNeeded()
    }

    // MARK: - Background Image

    private func applyBackgroundImage() {
        let s = Settings.shared
        let hasImage = s.backgroundImage != nil

        if hasImage {
            backgroundImageView?.image = s.backgroundImage
            backgroundImageView?.alphaValue = s.backgroundImageOpacity
            backgroundImageView?.isHidden = false
            imageDimOverlay?.alphaValue = 1.0 - s.backgroundImageBrightness
            imageDimOverlay?.isHidden = false
        } else {
            backgroundImageView?.isHidden = true
            imageDimOverlay?.isHidden = true
        }
    }

    // MARK: - Helpers

    private var currentTab: TerminalTab? {
        tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex] : nil
    }

    private var currentFocusedPane: TerminalPaneViewController? {
        currentTab?.focusedPane ?? currentTab?.allPanes.first
    }

    private func makePane(startingDirectory: String? = nil) -> TerminalPaneViewController {
        let pane = TerminalPaneViewController()
        pane.initialDirectory = startingDirectory
        addChild(pane)

        pane.onDirectoryChanged = { [weak self] changedPane, title in
            guard let self else { return }
            for tab in self.tabs {
                if tab.focusedPane === changedPane {
                    tab.title = title
                    self.refreshTabBar()
                    break
                }
            }
        }

        pane.onTitleChanged = { [weak self] changedPane, title in
            guard let self else { return }
            // Only use OSC title if we haven't received a directory update
            for tab in self.tabs {
                if tab.focusedPane === changedPane, tab.title == "Terminal" {
                    tab.title = title
                    self.refreshTabBar()
                    break
                }
            }
        }

        pane.onBecameFocused = { [weak self] focusedPane in
            guard let self else { return }
            for tab in self.tabs {
                if tab.allPanes.contains(where: { $0 === focusedPane }) {
                    tab.focusedPane = focusedPane
                    // Immediately update the tab title from the newly focused pane
                    if let title = focusedPane.lastReportedCwd {
                        tab.title = title
                        self.refreshTabBar()
                    }
                    break
                }
            }
        }

        pane.onProcessTerminated = { terminatedPane in
            // Restart the shell in-place
            terminatedPane.launchShell()
        }

        return pane
    }

    private func refreshTabBar() {
        let titles = tabs.map { $0.title }
        tabBar.updateTabs(titles: titles, selectedIndex: selectedTabIndex)
    }
}
