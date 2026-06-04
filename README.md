# QuakeTerm

A Quake-style dropdown terminal for macOS. QuakeTerm lives in your menu bar and slides down from the top of the screen with a single keypress — fast, minimal, and always one shortcut away.

Built with Swift, AppKit, and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

---

## Features

### Dropdown Terminal
- Slides down from the top of the screen with a smooth animation
- Stays above all other windows and across all Spaces/Desktops
- Borderless, floating panel that gets out of the way when dismissed
- Resizable by dragging the bottom handle — height is remembered between sessions

### Tabs & Split Panes
- Multiple tabs, each with its own shell session
- Vertical split panes within each tab
- Focus navigation between panes with keyboard shortcuts
- Tab titles update automatically from the shell (via OSC escape sequences)

### Appearance
- Customizable font, text color, and background color
- Window transparency with adjustable opacity
- Gaussian backdrop blur (content behind the terminal shows through softly)
- Background image support with independent opacity and brightness controls
- Background image spans the full tab area — splitting panes doesn't split the image

### System Integration
- Lives in the menu bar (no Dock icon)
- Global hotkey works from any application — no Accessibility permissions required
- Configurable hotkey (default: `Ctrl + Backtick`)
- Optional Launch at Login
- Drag and drop files onto the terminal to insert their shell-escaped paths
- Copy, paste, and select all via standard shortcuts

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **Ctrl + `** | Toggle terminal (global, configurable) |
| **Cmd + T** | New tab |
| **Cmd + W** | Close pane (or tab if it's the last pane) |
| **Cmd + D** | Split pane vertically |
| **Cmd + Shift + ]** | Next tab |
| **Cmd + Shift + [** | Previous tab |
| **Opt + Right Arrow** | Focus next pane |
| **Opt + Left Arrow** | Focus previous pane |
| **Cmd + C** | Copy |
| **Cmd + V** | Paste |
| **Cmd + A** | Select all |
| **Cmd + ,** | Settings |
| **Cmd + Q** | Quit |

---

## Settings

Open settings with **Cmd + ,** or from the menu bar icon.

| Setting | Description |
|---|---|
| **Hotkey** | Click to record a new global shortcut |
| **Launch at Login** | Start QuakeTerm automatically when you log in |
| **Font** | Terminal font face and size |
| **Text Color** | Foreground color for terminal text |
| **Background Color** | Terminal background color |
| **Transparency** | How much the desktop shows through (0–80%) |
| **Backdrop Blur** | Gaussian blur of content behind the window (0–100%) |
| **Background Image** | Optional image displayed behind the terminal |
| **Image Opacity** | How visible the background image is (0–100%) |
| **Image Brightness** | Darken the background image (0–100%) |

All settings are applied live and persist across launches.

---

## Building

Requires **Xcode 15+** and **macOS 14+**.

1. Open `quaketerm.xcodeproj` in Xcode
2. Press **Cmd + R** to build and run

The app runs as a menu bar agent — look for the icon in your menu bar, not the Dock.

---

## How It Works

- **Global hotkey** uses Carbon `RegisterEventHotKey` — captures only the configured key combo with zero privacy implications (no Accessibility permission, no keystroke monitoring)
- **Window** is a borderless `NSPanel` at floating level, visible on all Spaces
- **Animation** uses `NSViewAnimation` with the window sliding between an off-screen and on-screen frame
- **Backdrop blur** uses the private `CGSSetWindowBackgroundBlurRadius` API
- **Terminal** is powered by SwiftTerm's `LocalProcessTerminalView`, running `/bin/zsh -l`
- **Split panes** are managed as a recursive tree of `NSSplitView` instances

---

## License

MIT
