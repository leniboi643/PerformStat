import AppKit

/// A transparent, borderless, non-activating window pinned to the desktop layer:
/// wallpaper → **performstat** → desktop icons → normal windows.
final class DesktopOverlayWindow: NSWindow {
    /// kCGDesktopWindowLevel = kCGMinimumWindowLevel + 20 = INT32_MIN + 5 + 20.
    /// Wallpaper level: above the wallpaper image, below desktop icons and all normal windows.
    static let desktopLevel = NSWindow.Level(rawValue: Int(Int32.min) + 25)

    /// Re-assert desktop-level z-order; call after space changes or if something pushes us down.
    func assertDesktopLevel() {
        if level != Self.desktopLevel { level = Self.desktopLevel }
    }

    init(screen: NSScreen) {
        let frame = NSRect(origin: .zero, size: NSSize(width: 900, height: 600))
        super.init(contentRect: frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        level = Self.desktopLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        sharingType = .none
        animationBehavior = .none

        // never participate in app switching, Exposé, or screenshots beyond the desktop layer
        setAccessibilityHidden(true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func positionIn(_ screen: NSScreen, settings: SettingsModel) {
        let visible = screen.visibleFrame
        let size = frame.size

        // macOS coordinates: origin at bottom-left of the screen.
        func xFor(_ preset: PositionPreset) -> CGFloat {
            switch preset {
            case .topLeft, .middleLeft, .bottomLeft: return visible.minX
            case .topCenter, .bottomCenter: return visible.midX - size.width / 2
            case .topRight, .middleRight, .bottomRight: return visible.maxX - size.width
            case .custom: return visible.minX + CGFloat(settings.customX)
            }
        }
        func yFor(_ preset: PositionPreset) -> CGFloat {
            switch preset {
            case .topLeft, .topCenter, .topRight: return visible.maxY - size.height
            case .middleLeft, .middleRight: return visible.midY - size.height / 2
            case .bottomLeft, .bottomCenter, .bottomRight: return visible.minY
            case .custom: return visible.maxY - size.height - CGFloat(settings.customY)
            }
        }
        let preset = settings.position
        setFrameOrigin(NSPoint(x: xFor(preset), y: yFor(preset)))
    }
}
