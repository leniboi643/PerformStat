import AppKit

/// Menu bar (status item) controller exposing every setting as a native menu.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = SettingsModel.shared
    var onVisibilityChange: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        super.init()
        if let button = statusItem.button {
            // supplied logo as a template image: adapts to menu bar light/dark mode
            if let icon = NSImage(named: "StatusIcon") ?? Bundle.main.image(forResource: "StatusIcon") {
                let sized = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    return true
                }
                sized.isTemplate = true
                button.image = sized
                button.image?.size = NSSize(width: 18, height: 18)
            } else {
                button.title = "▤"
            }
            button.toolTip = "PerformStat"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let visibleItem = NSMenuItem(title: (settings.isVisible ? "Hide" : "Show") + " PerformStat  (f3 / fn+f3)",
                                     action: #selector(toggleVisible), keyEquivalent: "")
        visibleItem.target = self
        menu.addItem(visibleItem)
        menu.addItem(.separator())

        menu.addItem(header("statistics"))
        let statDefs: [(String, StatFlags)] = [
            ("cpu usage", .cpu), ("gpu usage", .gpu), ("memory", .memory), ("swap", .swap),
            ("disk i/o", .disk), ("network", .network), ("uptime", .uptime),
            ("memory pressure", .pressure), ("thermal", .thermal), ("battery", .battery),
            ("system info", .system),
        ]
        for (label, flag) in statDefs {
            let item = NSMenuItem(title: (settings.enabledStats.contains(flag) ? "☑" : "☐") + " " + label,
                                  action: #selector(toggleStat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = flag
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(header("update interval"))
        for seconds in [0.25, 0.5, 1.0, 2.0, 5.0] {
            let title = seconds < 1 ? "\(Int(seconds * 1000)) ms" : "\(Int(seconds)) s"
            let item = NSMenuItem(title: (abs(settings.updateInterval - seconds) < 0.01 ? "● " : "○ ") + title,
                                  action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(header("text size"))
        for size in [10.0, 12.0, 13.0, 16.0, 20.0] {
            let item = NSMenuItem(title: (abs(settings.fontSize - size) < 0.01 ? "● " : "○ ") + "\(Int(size)) pt",
                                  action: #selector(setFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(header("opacity"))
        for opacity in [0.5, 0.7, 0.9, 1.0] {
            let item = NSMenuItem(title: (abs(settings.textOpacity - opacity) < 0.01 ? "● " : "○ ") + "\(Int(opacity * 100))%",
                                  action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opacity
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(header("line spacing"))
        for spacing in [0.0, 3.0, 6.0] {
            let item = NSMenuItem(title: (abs(settings.lineSpacing - spacing) < 0.01 ? "● " : "○ ") + (spacing == 0 ? "tight" : "\(Int(spacing)) pt"),
                                  action: #selector(setSpacing(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spacing
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(header("position"))
        for preset in PositionPreset.allCases where preset != .custom {
            let item = NSMenuItem(title: (settings.position == preset ? "● " : "○ ") + preset.label,
                                  action: #selector(setPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            menu.addItem(item)
        }
        let customItem = NSMenuItem(title: (settings.position == .custom ? "● " : "○ ") + "custom x/y…",
                                    action: #selector(promptCustomPosition), keyEquivalent: "")
        customItem.target = self
        menu.addItem(customItem)
        menu.addItem(.separator())

        menu.addItem(header("screen"))
        let mainItem = NSMenuItem(title: (settings.preferredScreen == "main" ? "● " : "○ ") + "main display",
                                  action: #selector(setScreenMain), keyEquivalent: "")
        mainItem.target = self
        menu.addItem(mainItem)
        for screen in NSScreen.screens.dropFirst() {
            let id = String(screen.localizedName.hashValue)
            let name = screen.localizedName.isEmpty ? "display \(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "?")" : screen.localizedName
            let item = NSMenuItem(title: (settings.preferredScreen == id ? "● " : "○ ") + name,
                                  action: #selector(setScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: (settings.launchAtLogin ? "☑" : "☐") + " launch at login",
                                   action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        let resetItem = NSMenuItem(title: "reset settings", action: #selector(resetSettings), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PerformStat", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        item.attributedTitle = NSAttributedString(string: text.uppercased(), attributes: attr)
        return item
    }

    // MARK: actions

    @objc private func toggleVisible() {
        settings.isVisible.toggle()
        onVisibilityChange?()
    }

    @objc private func toggleStat(_ sender: NSMenuItem) {
        guard let flag = sender.representedObject as? StatFlags else { return }
        settings.enabledStats = settings.enabledStats.symmetricDifference(flag)
        onSettingsChange?()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        settings.updateInterval = v
        onSettingsChange?()
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        settings.fontSize = v
        onSettingsChange?()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        settings.textOpacity = v
        onSettingsChange?()
    }

    @objc private func setSpacing(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        settings.lineSpacing = v
        onSettingsChange?()
    }

    @objc private func setPosition(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? PositionPreset else { return }
        settings.position = p
        onSettingsChange?()
    }

    @objc private func promptCustomPosition() {
        let alert = NSAlert()
        alert.messageText = "custom position"
        alert.informativeText = "offset from the top-left corner of the chosen display, in points."
        alert.addButton(withTitle: "apply")
        alert.addButton(withTitle: "cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        let xField = NSTextField(string: String(format: "%.0f", settings.customX))
        let yField = NSTextField(string: String(format: "%.0f", settings.customY))
        xField.placeholderString = "x"
        yField.placeholderString = "y"
        stack.addArrangedSubview(NSView.labeled("x", xField))
        stack.addArrangedSubview(NSView.labeled("y", yField))
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        alert.accessoryView = stack

        if alert.runModal() == .alertFirstButtonReturn {
            settings.customX = xField.doubleValue
            settings.customY = yField.doubleValue
            settings.position = .custom
            onSettingsChange?()
        }
    }

    @objc private func setScreenMain() {
        settings.preferredScreen = "main"
        onSettingsChange?()
    }

    @objc private func setScreen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.preferredScreen = id
        onSettingsChange?()
    }

    @objc private func toggleLogin() {
        settings.launchAtLogin.toggle()
    }

    @objc private func resetSettings() {
        settings.reset()
        onSettingsChange?()
        onVisibilityChange?()
    }

    @objc private func quit() {
        onQuit?()
    }
}

extension NSView {
    static func labeled(_ label: String, _ field: NSTextField) -> NSView {
        let stack = NSStackView(views: [NSTextField(labelWithString: label), field])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }
}
