import AppKit

protocol TabBarViewDelegate: AnyObject {
    func tabBarDidSelectTab(at index: Int)
    func tabBarDidCloseTab(at index: Int)
    func tabBarDidClickAddTab()
    func tabBarDidMoveTab(from sourceIndex: Int, to destinationIndex: Int)
}

/// A horizontal strip of tab buttons with a "+" button at the trailing edge.
class TabBarView: NSView {

    weak var delegate: TabBarViewDelegate?

    static let barHeight: CGFloat = 28

    private var tabButtons: [TabButton] = []
    private let addButton = NSButton()
    private let stackView = NSStackView()
    private var selectedIndex: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private var settingsObserver: Any?

    private func setup() {
        wantsLayer = true
        applyColors()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: Settings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyColors()
            // Re-render tab button backgrounds
            for btn in self?.tabButtons ?? [] {
                btn.applyColors()
            }
        }

        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        addButton.title = "+"
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.font = .systemFont(ofSize: 16, weight: .light)
        addButton.contentTintColor = .lightGray
        addButton.target = self
        addButton.action = #selector(addTabClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            addButton.leadingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 4),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    // MARK: - Public API

    func updateTabs(titles: [String], selectedIndex: Int) {
        self.selectedIndex = selectedIndex

        // Add or remove buttons to match count
        while tabButtons.count < titles.count {
            let btn = TabButton()
            btn.onSelect = { [weak self] in
                guard let self else { return }
                if let idx = self.tabButtons.firstIndex(of: btn) {
                    self.delegate?.tabBarDidSelectTab(at: idx)
                }
            }
            btn.onClose = { [weak self] in
                guard let self else { return }
                if let idx = self.tabButtons.firstIndex(of: btn) {
                    self.delegate?.tabBarDidCloseTab(at: idx)
                }
            }
            btn.onDragReorder = { [weak self] dragButton, pointInBar in
                self?.handleTabDrag(dragButton, pointInBar: pointInBar)
            }
            tabButtons.append(btn)
            stackView.addArrangedSubview(btn)
        }
        while tabButtons.count > titles.count {
            let btn = tabButtons.removeLast()
            stackView.removeArrangedSubview(btn)
            btn.removeFromSuperview()
        }

        // Update titles and selection state
        let showClose = titles.count > 1
        for (i, btn) in tabButtons.enumerated() {
            btn.update(title: titles[i], isSelected: i == selectedIndex, showClose: showClose)
        }
    }

    func applyColors() {
        let s = Settings.shared
        let base = s.backgroundColor.blended(withFraction: 0.3, of: .black) ?? s.backgroundColor
        layer?.backgroundColor = base.cgColor
    }

    // MARK: - Tab reorder

    /// Move a tab button from one index to another (used by keyboard shortcuts).
    func moveButton(from source: Int, to dest: Int) {
        guard tabButtons.indices.contains(source),
              tabButtons.indices.contains(dest),
              source != dest else { return }

        let btn = tabButtons.remove(at: source)
        tabButtons.insert(btn, at: dest)
        rebuildStackViewAnimated()
    }

    private func handleTabDrag(_ dragButton: TabButton, pointInBar: NSPoint) {
        guard let sourceIndex = tabButtons.firstIndex(of: dragButton) else { return }

        // Determine destination based on which tab's midpoint the cursor has passed
        for (i, btn) in tabButtons.enumerated() {
            guard i != sourceIndex else { continue }
            let mid = btn.frame.midX
            let shouldSwap: Bool
            if i > sourceIndex {
                shouldSwap = pointInBar.x > mid
            } else {
                shouldSwap = pointInBar.x < mid
            }
            guard shouldSwap else { continue }

            let movedBtn = tabButtons.remove(at: sourceIndex)
            tabButtons.insert(movedBtn, at: i)
            rebuildStackViewAnimated()
            delegate?.tabBarDidMoveTab(from: sourceIndex, to: i)
            break
        }
    }

    private func rebuildStackViewAnimated() {
        // Detach all from the stack without removing from superview (preserves frames)
        let currentArranged = stackView.arrangedSubviews
        for v in currentArranged {
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        // Re-add in new order
        for btn in tabButtons {
            stackView.addArrangedSubview(btn)
        }
        // Animate the layout change
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.stackView.layoutSubtreeIfNeeded()
        }
    }

    @objc private func addTabClicked() {
        delegate?.tabBarDidClickAddTab()
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - TabButton

/// A single tab item view within the tab bar.
class TabButton: NSView {

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDragReorder: ((_ dragButton: TabButton, _ localPoint: NSPoint) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeBtn = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isSelected = false

    private var dragStartPoint: NSPoint?
    private static let dragThreshold: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 4

        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .lightGray
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeBtn.title = "×"
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 13, weight: .medium)
        closeBtn.contentTintColor = .gray
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.isHidden = true
        addSubview(closeBtn)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            heightAnchor.constraint(equalToConstant: TabBarView.barHeight - 4),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeBtn.leadingAnchor, constant: -2),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 16),
            closeBtn.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func update(title: String, isSelected: Bool, showClose: Bool) {
        self.isSelected = isSelected
        titleLabel.stringValue = title
        titleLabel.textColor = isSelected ? .white : .lightGray
        closeBtn.isHidden = !showClose
        updateBackground()
    }

    func applyColors() {
        updateBackground()
    }

    private func updateBackground() {
        let base = Settings.shared.backgroundColor
        if isSelected {
            layer?.backgroundColor = base.blended(withFraction: 0.15, of: .white)?.cgColor ?? base.cgColor
        } else if isHovered {
            layer?.backgroundColor = base.blended(withFraction: 0.08, of: .white)?.cgColor ?? base.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    // MARK: - Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                      owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = abs(current.x - startPoint.x)
        if dx > Self.dragThreshold {
            // Convert to tab bar coordinate space for reorder logic
            let pointInBar = superview?.convert(event.locationInWindow, from: nil) ?? current
            onDragReorder?(self, pointInBar)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
    }

    @objc private func closeTapped() {
        onClose?()
    }

    // MARK: - Equatable by identity

    static func == (lhs: TabButton, rhs: TabButton) -> Bool {
        return lhs === rhs
    }
}
