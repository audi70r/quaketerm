import AppKit

/// Represents the split tree within a single tab.
/// Each node is either a single terminal pane or a vertical split containing children.
indirect enum SplitNode {
    case leaf(TerminalPaneViewController)
    case split(NSSplitView, [SplitNode])

    /// All leaf panes in this subtree, left-to-right.
    var allPanes: [TerminalPaneViewController] {
        switch self {
        case .leaf(let pane):
            return [pane]
        case .split(_, let children):
            return children.flatMap { $0.allPanes }
        }
    }

    /// The top-level NSView for this node (either the pane's view or the split view).
    var view: NSView {
        switch self {
        case .leaf(let pane):
            return pane.view
        case .split(let splitView, _):
            return splitView
        }
    }

    /// Insert a new pane beside the given target pane, returning the updated node.
    /// Returns nil if the target wasn't found in this subtree.
    func addingSplit(beside target: TerminalPaneViewController,
                     newPane: TerminalPaneViewController) -> SplitNode? {
        switch self {
        case .leaf(let pane):
            guard pane === target else { return nil }
            let splitView = SplitNode.makeVerticalSplitView()
            splitView.addArrangedSubview(pane.view)
            splitView.addArrangedSubview(newPane.view)
            return .split(splitView, [.leaf(pane), .leaf(newPane)])

        case .split(let splitView, let children):
            var updatedChildren = children
            for (i, child) in children.enumerated() {
                if case .leaf(let pane) = child, pane === target {
                    // Insert newPane right after target in the existing split
                    splitView.insertArrangedSubview(newPane.view, at: i + 1)
                    updatedChildren.insert(.leaf(newPane), at: i + 1)
                    return .split(splitView, updatedChildren)
                } else if let updated = child.addingSplit(beside: target, newPane: newPane) {
                    updatedChildren[i] = updated
                    return .split(splitView, updatedChildren)
                }
            }
            return nil
        }
    }

    /// Remove the given pane, returning the updated node, or nil if this node should be removed entirely.
    func removingPane(_ target: TerminalPaneViewController) -> SplitNode? {
        switch self {
        case .leaf(let pane):
            return pane === target ? nil : self

        case .split(let splitView, let children):
            var remaining = [SplitNode]()
            for child in children {
                if let kept = child.removingPane(target) {
                    remaining.append(kept)
                }
            }
            target.view.removeFromSuperview()

            if remaining.isEmpty {
                return nil
            } else if remaining.count == 1 {
                // Collapse: unwrap single remaining child from the split view
                let survivor = remaining[0]
                survivor.view.removeFromSuperview()
                return survivor
            } else {
                return .split(splitView, remaining)
            }
        }
    }

    // MARK: - Helpers

    static func makeVerticalSplitView() -> NSSplitView {
        let sv = NSSplitView()
        sv.isVertical = true
        sv.dividerStyle = .thin
        sv.autoresizingMask = [.width, .height]
        return sv
    }
}

/// Represents one tab in the terminal, holding its split tree and metadata.
class TerminalTab {
    let id = UUID()
    var title: String = "Terminal"
    var rootNode: SplitNode

    /// The currently focused pane in this tab.
    weak var focusedPane: TerminalPaneViewController?

    init(pane: TerminalPaneViewController) {
        self.rootNode = .leaf(pane)
        self.focusedPane = pane
    }

    var allPanes: [TerminalPaneViewController] {
        rootNode.allPanes
    }
}
