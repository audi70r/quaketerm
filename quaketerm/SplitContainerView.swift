import AppKit
import SwiftTerm

/// Manages the NSSplitView tree for a single tab.
/// Hosts the root view of the tab's SplitNode and handles divider styling.
class SplitContainerView: NSView, NSSplitViewDelegate {

    private(set) var tab: TerminalTab

    init(tab: TerminalTab) {
        self.tab = tab
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        installRootView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    /// Replace the current view tree with the tab's current root node view.
    func installRootView() {
        subviews.forEach { $0.removeFromSuperview() }
        let rootView = tab.rootNode.view
        rootView.frame = bounds
        rootView.autoresizingMask = [.width, .height]
        addSubview(rootView)
        applyDelegateToAllSplitViews(node: tab.rootNode)
    }

    /// Add a vertical split beside the given pane.
    func splitPane(_ pane: TerminalPaneViewController, with newPane: TerminalPaneViewController) {
        if let updated = tab.rootNode.addingSplit(beside: pane, newPane: newPane) {
            tab.rootNode = updated
            // Reinstall the root view since the tree structure changed
            // (e.g. leaf → split, which introduces a new NSSplitView)
            installRootView()
            // Equalize split positions after layout
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.equalizeSplitPositions(node: self.tab.rootNode)
            }
        }
    }

    /// Remove a pane from the split tree.
    /// Returns true if the tab still has panes, false if it's now empty.
    @discardableResult
    func removePane(_ pane: TerminalPaneViewController) -> Bool {
        pane.terminalView.terminate()

        if let updated = tab.rootNode.removingPane(pane) {
            tab.rootNode = updated
            // Reinstall the root in case the tree collapsed
            installRootView()
            return true
        }
        return false
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView,
                   constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMinimumPosition + 80
    }

    func splitView(_ splitView: NSSplitView,
                   constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMaximumPosition - 80
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        return true
    }

    // MARK: - Helpers

    private func applyDelegateToAllSplitViews(node: SplitNode) {
        switch node {
        case .leaf:
            break
        case .split(let sv, let children):
            sv.delegate = self
            for child in children {
                applyDelegateToAllSplitViews(node: child)
            }
        }
    }

    private func equalizeSplitPositions(node: SplitNode) {
        switch node {
        case .leaf:
            break
        case .split(let sv, let children):
            let count = CGFloat(children.count)
            let totalWidth = sv.bounds.width - (CGFloat(children.count - 1) * sv.dividerThickness)
            let paneWidth = totalWidth / count
            for (i, child) in children.enumerated() {
                if i < children.count - 1 {
                    sv.setPosition(paneWidth * CGFloat(i + 1) + sv.dividerThickness * CGFloat(i),
                                   ofDividerAt: i)
                }
                equalizeSplitPositions(node: child)
            }
        }
    }
}
