import AppKit
import Carbon.HIToolbox

/// Persisted app settings backed by UserDefaults.
/// Posts `Settings.didChangeNotification` whenever a value changes.
class Settings {

    static let shared = Settings()
    static let didChangeNotification = Notification.Name("SettingsDidChange")

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let foregroundColor = "foregroundColor"
        static let backgroundColor = "backgroundColor"
        static let windowTransparency = "windowTransparency"
        static let backgroundImagePath = "backgroundImagePath"
        static let backgroundImageOpacity = "backgroundImageOpacity"
        static let backgroundImageBrightness = "backgroundImageBrightness"
        static let backdropBlurAmount = "backdropBlurAmount"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let windowHeight = "windowHeight"
        static let defaultHeightRatio = "defaultHeightRatio"
        static let tabBarPosition = "tabBarPosition"
    }

    // MARK: - Properties

    var fontName: String {
        didSet { defaults.set(fontName, forKey: Key.fontName); notifyChange() }
    }

    var fontSize: CGFloat {
        didSet { defaults.set(fontSize, forKey: Key.fontSize); notifyChange() }
    }

    var foregroundColor: NSColor {
        didSet { saveColor(foregroundColor, forKey: Key.foregroundColor); notifyChange() }
    }

    var backgroundColor: NSColor {
        didSet { saveColor(backgroundColor, forKey: Key.backgroundColor); notifyChange() }
    }

    /// Window transparency (0.0 = fully opaque, 1.0 = nearly invisible). Range 0.0–0.8.
    var windowTransparency: CGFloat {
        didSet { defaults.set(windowTransparency, forKey: Key.windowTransparency); notifyChange() }
    }

    /// File path to an optional background image.
    var backgroundImagePath: String? {
        didSet {
            if let path = backgroundImagePath {
                defaults.set(path, forKey: Key.backgroundImagePath)
            } else {
                defaults.removeObject(forKey: Key.backgroundImagePath)
            }
            notifyChange()
        }
    }

    /// Opacity of the background image (0.0–1.0).
    var backgroundImageOpacity: CGFloat {
        didSet { defaults.set(backgroundImageOpacity, forKey: Key.backgroundImageOpacity); notifyChange() }
    }

    /// Brightness of the background image (0.0 = fully dark, 1.0 = original). Default 1.0.
    var backgroundImageBrightness: CGFloat {
        didSet { defaults.set(backgroundImageBrightness, forKey: Key.backgroundImageBrightness); notifyChange() }
    }

    /// Backdrop blur intensity (0.0 = off, 1.0 = full vibrancy). Range 0.0–1.0.
    var backdropBlurAmount: CGFloat {
        didSet { defaults.set(backdropBlurAmount, forKey: Key.backdropBlurAmount); notifyChange() }
    }

    /// Global hotkey keyCode (hardware key). Default: 50 = backtick/tilde key.
    var hotkeyKeyCode: UInt16 {
        didSet { defaults.set(Int(hotkeyKeyCode), forKey: Key.hotkeyKeyCode); notifyChange() }
    }

    /// Global hotkey modifier flags (raw value). Default: control.
    var hotkeyModifiers: UInt {
        didSet { defaults.set(hotkeyModifiers, forKey: Key.hotkeyModifiers); notifyChange() }
    }

    /// Persisted window height in points. 0 means "use default ratio".
    var windowHeight: CGFloat {
        didSet { defaults.set(windowHeight, forKey: Key.windowHeight) }
    }

    /// Default fraction of screen height the terminal occupies (0.2–0.9). Default: 0.4.
    var defaultHeightRatio: CGFloat {
        didSet { defaults.set(defaultHeightRatio, forKey: Key.defaultHeightRatio); notifyChange() }
    }

    /// Tab bar position: "top" or "bottom". Default: "top".
    var tabBarPosition: String {
        didSet { defaults.set(tabBarPosition, forKey: Key.tabBarPosition); notifyChange() }
    }

    var tabBarOnBottom: Bool { tabBarPosition == "bottom" }

    /// Human-readable description of the current hotkey.
    var hotkeyDescription: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: hotkeyModifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    /// Convert a keyCode to a displayable string.
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        // Map common special keys
        switch keyCode {
        case 50: return "`"
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            // Use Carbon's key code translation for printable characters
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "Key\(keyCode)"
            }
            let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self) as Data
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length: Int = 0
            layoutData.withUnsafeBytes { rawBuf in
                guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
                UCKeyTranslate(
                    ptr,
                    keyCode,
                    UInt16(kUCKeyActionDisplay),
                    0, // no modifiers for display
                    UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )
            }
            if length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    // MARK: - Computed

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var backgroundImage: NSImage? {
        guard let path = backgroundImagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    // MARK: - Init

    private init() {
        fontName = defaults.string(forKey: Key.fontName) ?? "Menlo"
        fontSize = defaults.object(forKey: Key.fontSize) != nil
            ? CGFloat(defaults.double(forKey: Key.fontSize))
            : 13
        foregroundColor = Settings.loadColor(forKey: Key.foregroundColor)
            ?? NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        backgroundColor = Settings.loadColor(forKey: Key.backgroundColor)
            ?? NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        windowTransparency = CGFloat(defaults.double(forKey: Key.windowTransparency))
        backgroundImagePath = defaults.string(forKey: Key.backgroundImagePath)
        backgroundImageOpacity = defaults.object(forKey: Key.backgroundImageOpacity) != nil
            ? CGFloat(defaults.double(forKey: Key.backgroundImageOpacity))
            : 0.3
        backgroundImageBrightness = defaults.object(forKey: Key.backgroundImageBrightness) != nil
            ? CGFloat(defaults.double(forKey: Key.backgroundImageBrightness))
            : 1.0
        backdropBlurAmount = CGFloat(defaults.double(forKey: Key.backdropBlurAmount))
        hotkeyKeyCode = defaults.object(forKey: Key.hotkeyKeyCode) != nil
            ? UInt16(defaults.integer(forKey: Key.hotkeyKeyCode))
            : 50 // backtick
        hotkeyModifiers = defaults.object(forKey: Key.hotkeyModifiers) != nil
            ? UInt(defaults.integer(forKey: Key.hotkeyModifiers))
            : NSEvent.ModifierFlags.control.rawValue
        windowHeight = CGFloat(defaults.double(forKey: Key.windowHeight))
        defaultHeightRatio = defaults.object(forKey: Key.defaultHeightRatio) != nil
            ? CGFloat(defaults.double(forKey: Key.defaultHeightRatio))
            : 0.4
        tabBarPosition = defaults.string(forKey: Key.tabBarPosition) ?? "top"
    }

    // MARK: - Color persistence

    private func saveColor(_ color: NSColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Settings.didChangeNotification, object: self)
    }
}
