// Desktop Icons – show/hide macOS desktop icons from the menu bar
// Copyright (C) 2026 Andrea Leganza
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
 

import Cocoa
import Carbon.HIToolbox

// MARK: - Configuration

/// If true, desktop icons are restored when the app quits.
let restoreIconsOnQuit = true

// MARK: - Shortcut model

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_H),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⌃⌥⌘H"
    )

    private static let storeKey = "globalShortcut"

    static func load() -> Shortcut? {
        guard UserDefaults.standard.object(forKey: storeKey) != nil else { return .default }
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return nil } // removed
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    static func save(_ s: Shortcut?) {
        if let s, let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: storeKey)
        } else {
            UserDefaults.standard.set(Data(), forKey: storeKey) // marker for "no shortcut"
        }
    }
}

// MARK: - Global hotkey (Carbon: no Accessibility permission required)

final class HotKeyManager {
    static let shared = HotKeyManager()
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ shortcut: Shortcut?) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        installHandlerIfNeeded()
        guard let shortcut else { return }
        let id = EventHotKeyID(signature: OSType(0x44495431), id: 1) // 'DIT1'
        RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

// MARK: - Desktop icon control

enum DesktopIcons {
    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// true if icons are currently hidden
    static func areHidden() -> Bool {
        let r = run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        guard r.status == 0 else { return false } // missing key = icons visible
        return r.output == "0" || r.output.lowercased() == "false"
    }

    static func setHidden(_ hidden: Bool) {
        run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        run("/usr/bin/killall", ["Finder"]) // Finder relaunches automatically
    }
}

// MARK: - Menu bar icon: eye over a file

func makeStatusIcon(hidden: Bool) -> NSImage {
    let size = NSSize(width: 22, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        // File
        let docCfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let doc = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(docCfg) {
            let s = doc.size
            doc.draw(in: NSRect(x: (rect.width - s.width) / 2,
                                y: (rect.height - s.height) / 2,
                                width: s.width, height: s.height))
        }
        // Eye (slashed when icons are hidden)
        let eyeCfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        let eyeName = hidden ? "eye.slash" : "eye"
        if let eye = NSImage(systemSymbolName: eyeName, accessibilityDescription: nil)?
            .withSymbolConfiguration(eyeCfg) {
            let s = eye.size
            let eyeRect = NSRect(x: (rect.width - s.width) / 2,
                                 y: (rect.height - s.height) / 2 - 1,
                                 width: s.width, height: s.height)
            // Knock out the area around the eye to separate it from the file
            if let ctx = NSGraphicsContext.current {
                ctx.saveGraphicsState()
                ctx.compositingOperation = .clear
                NSBezierPath(roundedRect: eyeRect.insetBy(dx: -1.5, dy: -1.5),
                             xRadius: 3, yRadius: 3).fill()
                ctx.restoreGraphicsState()
            }
            eye.draw(in: eyeRect)
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Shortcut recorder window

final class ShortcutWindowController: NSWindowController, NSWindowDelegate {
    var onChange: ((Shortcut?) -> Void)?
    private var shortcut: Shortcut?
    private let recordButton = NSButton()
    private var monitor: Any?
    private var recording = false

    init(shortcut: Shortcut?) {
        self.shortcut = shortcut
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 170),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Keyboard Shortcut"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        buildUI()
        refreshButton()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildUI() {
        let title = NSTextField(labelWithString: "Show / hide desktop icons")
        title.font = .boldSystemFont(ofSize: 13)

        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let hint = NSTextField(wrappingLabelWithString:
            "Click the button and press the new key combination (at least one modifier is required: ⌘ ⌥ ⌃ ⇧). Press Esc to cancel.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let reset = NSButton(title: "Restore Default", target: self, action: #selector(resetDefault))
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeShortcut))
        let buttons = NSStackView(views: [reset, remove])
        buttons.spacing = 8

        let stack = NSStackView(views: [title, recordButton, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = window!.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func refreshButton() {
        recordButton.title = recording ? "Press the shortcut…" : (shortcut?.display ?? "None – click to set")
    }

    func show() {
        refreshButton()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    // MARK: actions

    @objc private func toggleRecording() { recording ? stopRecording() : startRecording() }

    @objc private func resetDefault() { apply(.default) }

    @objc private func removeShortcut() { apply(nil) }

    private func apply(_ s: Shortcut?) {
        stopRecording()
        shortcut = s
        refreshButton()
        onChange?(s)
    }

    private func startRecording() {
        recording = true
        refreshButton()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil // swallow the event
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        refreshButton()
    }

    func windowWillClose(_ notification: Notification) { stopRecording() }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option)  { carbon |= UInt32(optionKey);  symbols += "⌥" }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey);   symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey);     symbols += "⌘" }

        guard carbon != 0 else { NSSound.beep(); return }

        let new = Shortcut(keyCode: UInt32(event.keyCode),
                           carbonModifiers: carbon,
                           display: symbols + Self.keyName(for: event))
        apply(new)
    }

    private static func keyName(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        if let name = special[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let shortcutItem = NSMenuItem()
    private var shortcut: Shortcut? = Shortcut.load()
    private var shortcutWindow: ShortcutWindowController?
    private var hidden = false
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        toggleItem.target = self
        toggleItem.action = #selector(toggleIcons)

        shortcutItem.target = self
        shortcutItem.action = #selector(openShortcutWindow)

        let quitItem = NSMenuItem(title: "Quit App", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self

        menu.delegate = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(shortcutItem)
        menu.addItem(quitItem)
        statusItem.menu = menu

        HotKeyManager.shared.onTrigger = { [weak self] in self?.toggleIcons() }
        HotKeyManager.shared.register(shortcut)

        refreshState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if restoreIconsOnQuit && DesktopIcons.areHidden() {
            DesktopIcons.setHidden(false)
        }
    }

    // MARK: state / UI

    func menuWillOpen(_ menu: NSMenu) { refreshState() }

    private func refreshState() {
        hidden = DesktopIcons.areHidden()
        updateUI()
    }

    private func updateUI() {
        statusItem.button?.image = makeStatusIcon(hidden: hidden)
        toggleItem.title = hidden ? "Show All Desktop Icons" : "Hide All Desktop Icons"
        toggleItem.isEnabled = !busy
        shortcutItem.title = "Set Shortcut…" + (shortcut.map { "  (\($0.display))" } ?? "")
    }

    // MARK: actions

    @objc private func toggleIcons() {
        guard !busy else { return }
        busy = true
        let target = !hidden
        updateUI()
        DispatchQueue.global(qos: .userInitiated).async {
            DesktopIcons.setHidden(target)
            DispatchQueue.main.async {
                self.hidden = target
                self.busy = false
                self.updateUI()
            }
        }
    }

    @objc private func openShortcutWindow() {
        if shortcutWindow == nil {
            let wc = ShortcutWindowController(shortcut: shortcut)
            wc.onChange = { [weak self] new in
                guard let self else { return }
                self.shortcut = new
                Shortcut.save(new)
                HotKeyManager.shared.register(new)
                self.updateUI()
            }
            shortcutWindow = wc
        }
        shortcutWindow?.show()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Launch

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
