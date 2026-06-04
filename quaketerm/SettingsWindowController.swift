import AppKit
import ServiceManagement
import UniformTypeIdentifiers

class SettingsWindowController: NSWindowController {

    private let hotkeyButton = NSButton()
    private var isRecordingHotkey = false
    private var hotkeyLocalMonitor: Any?
    private let fontLabel = NSTextField(labelWithString: "")
    private let fgColorWell = NSColorWell()
    private let bgColorWell = NSColorWell()
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "0%")
    private let blurSlider = NSSlider()
    private let blurLabel = NSTextField(labelWithString: "0%")
    private let imagePreview = NSImageView()
    private let imagePathLabel = NSTextField(labelWithString: "No image selected")
    private let imageOpacitySlider = NSSlider()
    private let imageOpacityLabel = NSTextField(labelWithString: "30%")
    private let imageBrightnessSlider = NSSlider()
    private let imageBrightnessLabel = NSTextField(labelWithString: "100%")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let tabBarPositionPopup = NSPopUpButton()
    private let defaultHeightSlider = NSSlider()
    private let defaultHeightLabel = NSTextField(labelWithString: "40%")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 660),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        self.init(window: window)
        setupUI()
        loadCurrentValues()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // -- Hotkey --
        let hotkeySection = sectionLabel("Toggle Hotkey")

        hotkeyButton.title = Settings.shared.hotkeyDescription
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.target = self
        hotkeyButton.action = #selector(recordHotkey(_:))
        hotkeyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let hotkeyHint = NSTextField(labelWithString: "Click, then press new shortcut")
        hotkeyHint.font = .systemFont(ofSize: 10)
        hotkeyHint.textColor = .secondaryLabelColor

        let hotkeyRow = NSStackView(views: [hotkeyButton, hotkeyHint])
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 8

        stack.addArrangedSubview(hotkeySection)
        stack.addArrangedSubview(hotkeyRow)

        // -- Launch at Login --
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged(_:))

        stack.addArrangedSubview(launchAtLoginCheckbox)

        // -- Tab Bar Position --
        let tabPosLabel = NSTextField(labelWithString: "Tab Bar:")
        tabBarPositionPopup.addItems(withTitles: ["Top", "Bottom"])
        tabBarPositionPopup.target = self
        tabBarPositionPopup.action = #selector(tabBarPositionChanged(_:))

        let tabPosRow = NSStackView(views: [tabPosLabel, tabBarPositionPopup])
        tabPosRow.orientation = .horizontal
        tabPosRow.spacing = 8

        stack.addArrangedSubview(tabPosRow)

        // -- Default Height --
        let heightSection = sectionLabel("Default Height")

        defaultHeightSlider.minValue = 0.2
        defaultHeightSlider.maxValue = 0.9
        defaultHeightSlider.target = self
        defaultHeightSlider.action = #selector(defaultHeightChanged(_:))
        defaultHeightSlider.isContinuous = true
        defaultHeightSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        defaultHeightLabel.alignment = .right
        defaultHeightLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let heightRow = NSStackView(views: [defaultHeightSlider, defaultHeightLabel])
        heightRow.orientation = .horizontal
        heightRow.spacing = 8

        let heightHint = NSTextField(labelWithString: "Used when no custom height has been set by dragging")
        heightHint.font = .systemFont(ofSize: 10)
        heightHint.textColor = .secondaryLabelColor

        let resetHeightButton = NSButton(title: "Reset to Default", target: self, action: #selector(resetWindowHeight(_:)))

        let heightButtonRow = NSStackView(views: [resetHeightButton, heightHint])
        heightButtonRow.orientation = .horizontal
        heightButtonRow.spacing = 8

        stack.addArrangedSubview(heightSection)
        stack.addArrangedSubview(heightRow)
        stack.addArrangedSubview(heightButtonRow)

        // -- Font --
        let fontSection = sectionLabel("Font")
        fontLabel.isEditable = false
        fontLabel.isBordered = false
        fontLabel.backgroundColor = .clear
        fontLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let fontButton = NSButton(title: "Select Font...", target: self, action: #selector(selectFont(_:)))
        let fontRow = NSStackView(views: [fontLabel, fontButton])
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        stack.addArrangedSubview(fontSection)
        stack.addArrangedSubview(fontRow)

        // -- Colors --
        let colorSection = sectionLabel("Colors")

        let fgLabel = NSTextField(labelWithString: "Text:")
        fgColorWell.color = Settings.shared.foregroundColor
        fgColorWell.target = self
        fgColorWell.action = #selector(foregroundColorChanged(_:))

        let bgLabel = NSTextField(labelWithString: "Background:")
        bgColorWell.color = Settings.shared.backgroundColor
        bgColorWell.target = self
        bgColorWell.action = #selector(backgroundColorChanged(_:))

        let colorRow = NSStackView(views: [fgLabel, fgColorWell, bgLabel, bgColorWell])
        colorRow.orientation = .horizontal
        colorRow.spacing = 8

        stack.addArrangedSubview(colorSection)
        stack.addArrangedSubview(colorRow)

        // -- Transparency --
        let opacitySection = sectionLabel("Transparency")

        opacitySlider.minValue = 0.0
        opacitySlider.maxValue = 0.8
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.isContinuous = true
        opacitySlider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        opacityLabel.alignment = .right
        opacityLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let opacityRow = NSStackView(views: [opacitySlider, opacityLabel])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 8

        stack.addArrangedSubview(opacitySection)
        stack.addArrangedSubview(opacityRow)

        // -- Backdrop Blur --
        let blurSection = sectionLabel("Backdrop Blur")

        blurSlider.minValue = 0.0
        blurSlider.maxValue = 1.0
        blurSlider.target = self
        blurSlider.action = #selector(blurChanged(_:))
        blurSlider.isContinuous = true
        blurSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        blurLabel.alignment = .right
        blurLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let blurRow = NSStackView(views: [blurSlider, blurLabel])
        blurRow.orientation = .horizontal
        blurRow.spacing = 8

        stack.addArrangedSubview(blurSection)
        stack.addArrangedSubview(blurRow)

        // -- Background Image --
        let imageSection = sectionLabel("Background Image")

        let chooseButton = NSButton(title: "Choose Image...", target: self, action: #selector(chooseImage(_:)))
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearImage(_:)))

        imagePathLabel.lineBreakMode = .byTruncatingMiddle
        imagePathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        imagePreview.imageScaling = .scaleProportionallyUpOrDown
        imagePreview.widthAnchor.constraint(equalToConstant: 60).isActive = true
        imagePreview.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let imageButtonRow = NSStackView(views: [chooseButton, clearButton, imagePreview])
        imageButtonRow.orientation = .horizontal
        imageButtonRow.spacing = 8

        let imgOpLabel = NSTextField(labelWithString: "Image Opacity:")
        imageOpacitySlider.minValue = 0.0
        imageOpacitySlider.maxValue = 1.0
        imageOpacitySlider.target = self
        imageOpacitySlider.action = #selector(imageOpacityChanged(_:))
        imageOpacitySlider.isContinuous = true
        imageOpacitySlider.widthAnchor.constraint(equalToConstant: 150).isActive = true

        imageOpacityLabel.alignment = .right
        imageOpacityLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let imgOpRow = NSStackView(views: [imgOpLabel, imageOpacitySlider, imageOpacityLabel])
        imgOpRow.orientation = .horizontal
        imgOpRow.spacing = 8

        let imgBrLabel = NSTextField(labelWithString: "Image Brightness:")
        imageBrightnessSlider.minValue = 0.0
        imageBrightnessSlider.maxValue = 1.0
        imageBrightnessSlider.target = self
        imageBrightnessSlider.action = #selector(imageBrightnessChanged(_:))
        imageBrightnessSlider.isContinuous = true
        imageBrightnessSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true

        imageBrightnessLabel.alignment = .right
        imageBrightnessLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let imgBrRow = NSStackView(views: [imgBrLabel, imageBrightnessSlider, imageBrightnessLabel])
        imgBrRow.orientation = .horizontal
        imgBrRow.spacing = 8

        stack.addArrangedSubview(imageSection)
        stack.addArrangedSubview(imagePathLabel)
        stack.addArrangedSubview(imageButtonRow)
        stack.addArrangedSubview(imgOpRow)
        stack.addArrangedSubview(imgBrRow)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func loadCurrentValues() {
        let s = Settings.shared
        fontLabel.stringValue = "\(s.fontName) — \(Int(s.fontSize))pt"
        fgColorWell.color = s.foregroundColor
        bgColorWell.color = s.backgroundColor
        opacitySlider.doubleValue = Double(s.windowTransparency)
        opacityLabel.stringValue = "\(Int(s.windowTransparency * 100))%"
        imageOpacitySlider.doubleValue = Double(s.backgroundImageOpacity)
        imageOpacityLabel.stringValue = "\(Int(s.backgroundImageOpacity * 100))%"
        imageBrightnessSlider.doubleValue = Double(s.backgroundImageBrightness)
        imageBrightnessLabel.stringValue = "\(Int(s.backgroundImageBrightness * 100))%"

        blurSlider.doubleValue = Double(s.backdropBlurAmount)
        blurLabel.stringValue = "\(Int(s.backdropBlurAmount * 100))%"

        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        tabBarPositionPopup.selectItem(withTitle: Settings.shared.tabBarOnBottom ? "Bottom" : "Top")

        defaultHeightSlider.doubleValue = Double(s.defaultHeightRatio)
        defaultHeightLabel.stringValue = "\(Int(s.defaultHeightRatio * 100))%"

        if let path = s.backgroundImagePath {
            imagePathLabel.stringValue = (path as NSString).lastPathComponent
            imagePreview.image = NSImage(contentsOfFile: path)
        } else {
            imagePathLabel.stringValue = "No image selected"
            imagePreview.image = nil
        }
    }

    // MARK: - Actions

    @objc private func recordHotkey(_ sender: Any) {
        if isRecordingHotkey {
            stopRecordingHotkey()
            return
        }
        isRecordingHotkey = true
        hotkeyButton.title = "Press shortcut..."

        hotkeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingHotkey else { return event }

            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])

            // Escape cancels recording
            if event.keyCode == 53 {
                self.stopRecordingHotkey()
                return nil
            }

            // Require at least one modifier (to avoid plain letter keys)
            guard !mods.isEmpty else { return nil }

            Settings.shared.hotkeyKeyCode = event.keyCode
            Settings.shared.hotkeyModifiers = mods.rawValue
            self.stopRecordingHotkey()
            return nil // consume
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        if let monitor = hotkeyLocalMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyLocalMonitor = nil
        }
        hotkeyButton.title = Settings.shared.hotkeyDescription
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert checkbox if registration failed
            sender.state = sender.state == .on ? .off : .on
        }
    }

    @objc private func tabBarPositionChanged(_ sender: NSPopUpButton) {
        Settings.shared.tabBarPosition = sender.titleOfSelectedItem == "Bottom" ? "bottom" : "top"
    }

    @objc private func defaultHeightChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        Settings.shared.defaultHeightRatio = value
        defaultHeightLabel.stringValue = "\(Int(value * 100))%"
    }

    @objc private func resetWindowHeight(_ sender: Any) {
        Settings.shared.windowHeight = 0
    }

    @objc private func selectFont(_ sender: Any) {
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.setSelectedFont(Settings.shared.font, isMultiple: false)
        fontManager.orderFrontFontPanel(self)
    }

    // Called by NSFontManager when user picks a font
    @objc func changeFont(_ sender: NSFontManager?) {
        guard let manager = sender else { return }
        let newFont = manager.convert(Settings.shared.font)
        Settings.shared.fontName = newFont.fontName
        Settings.shared.fontSize = newFont.pointSize
        fontLabel.stringValue = "\(newFont.fontName) — \(Int(newFont.pointSize))pt"
    }

    @objc private func foregroundColorChanged(_ sender: NSColorWell) {
        Settings.shared.foregroundColor = sender.color
    }

    @objc private func backgroundColorChanged(_ sender: NSColorWell) {
        Settings.shared.backgroundColor = sender.color
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        Settings.shared.windowTransparency = value
        opacityLabel.stringValue = "\(Int(value * 100))%"
    }

    @objc private func blurChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        Settings.shared.backdropBlurAmount = value
        blurLabel.stringValue = "\(Int(value * 100))%"
    }

    @objc private func chooseImage(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Settings.shared.backgroundImagePath = url.path
            self?.imagePathLabel.stringValue = url.lastPathComponent
            self?.imagePreview.image = NSImage(contentsOf: url)
        }
    }

    @objc private func clearImage(_ sender: Any) {
        Settings.shared.backgroundImagePath = nil
        imagePathLabel.stringValue = "No image selected"
        imagePreview.image = nil
    }

    @objc private func imageOpacityChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        Settings.shared.backgroundImageOpacity = value
        imageOpacityLabel.stringValue = "\(Int(value * 100))%"
    }

    @objc private func imageBrightnessChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        Settings.shared.backgroundImageBrightness = value
        imageBrightnessLabel.stringValue = "\(Int(value * 100))%"
    }
}
