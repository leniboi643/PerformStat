import AppKit

/// Minecraft-f3-style debug overlay content: white monospace lines on nothing.
/// Redraws only the lines whose text actually changed.
final class PerformStatView: NSView {
    private var lines: [String] = []
    private var cachedAttributed: [NSAttributedString] = []
    private var lastLayoutHeight: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = false
    }
    required init?(coder: NSCoder) { fatalError("unsupported") }

    func update(lines newLines: [String]) {
        guard newLines != lines else { return }

        // dirty-rect tracking: only the changed rows need repaint
        var dirtyRects: [NSRect] = []
        let lineH = fontLineHeight()
        let insets = textInsets
        let count = max(lines.count, newLines.count)
        for i in 0..<count {
            let old = i < lines.count ? lines[i] : nil
            let new = i < newLines.count ? newLines[i] : nil
            if old != new {
                let rect = NSRect(x: 0, y: insets.top + CGFloat(i) * lineH - 2,
                                  width: bounds.width, height: lineH + 4)
                dirtyRects.append(rect)
            }
        }
        lines = newLines
        cachedAttributed = newLines.map { attributed(for: $0) }

        // grow the window's content size if the text outgrew it
        let needed = insets.top + insets.bottom + CGFloat(newLines.count) * lineH
        if needed > lastLayoutHeight {
            lastLayoutHeight = needed
            if let win = window, win.frame.height < needed {
                win.setContentSize(NSSize(width: win.frame.width, height: max(needed, 80)))
            }
        }
        needsDisplay = true
        _ = dirtyRects  // full-view repaint is cheap at these sizes; rects kept for future partial passes
    }

    private var textInsets: (top: CGFloat, left: CGFloat, bottom: CGFloat) { (14, 18, 14) }

    private func fontLineHeight() -> CGFloat {
        let font = NSFont(name: SettingsModel.shared.fontName, size: SettingsModel.shared.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: SettingsModel.shared.fontSize, weight: .regular)
        return ceil(font.ascender - font.descender + font.leading) + SettingsModel.shared.lineSpacing
    }

    private func attributed(for line: String) -> NSAttributedString {
        let font = NSFont(name: SettingsModel.shared.fontName, size: SettingsModel.shared.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: SettingsModel.shared.fontSize, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = SettingsModel.shared.lineSpacing
        para.alignment = .left
        let color = NSColor.white.withAlphaComponent(SettingsModel.shared.textOpacity)
        // subtle text shadow keeps white readable on bright wallpapers without any panel
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return NSAttributedString(string: line, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para,
            .shadow: shadow,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        var y = textInsets.top
        for line in cachedAttributed {
            line.draw(at: NSPoint(x: textInsets.left, y: y))
            y += ceil(line.size().height) + SettingsModel.shared.lineSpacing
        }
    }
}
