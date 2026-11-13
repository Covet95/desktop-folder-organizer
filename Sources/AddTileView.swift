import AppKit

final class AddTileView: NSView {
    var onTap: (() -> Void)?

    var isCompactBanner = false {
        didSet {
            guard isCompactBanner != oldValue else { return }
            layer?.cornerRadius = isCompactBanner ? 11 : 12
            needsDisplay = true
        }
    }

    private var color: NSColor = PanelAppearance.secondaryText
    private var isHovering = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        toolTip = "添加文件或文件夹（会移动原文件）"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setColor(_ color: NSColor) {
        self.color = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isCompactBanner {
            drawCompactBanner()
            return
        }

        let radius: CGFloat = 12
        if isPressed {
            PanelAppearance.itemPressed.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        } else if isHovering {
            PanelAppearance.itemHover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }

        let iconSize = min(PanelAppearance.Grid.iconSize, max(1, bounds.width - 8))
        let box = CGRect(x: (bounds.width - iconSize) / 2, y: 7, width: iconSize, height: iconSize)
        let path = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        NSColor.quaternaryLabelColor.withAlphaComponent(isHovering ? 0.14 : 0.07).setFill()
        path.fill()
        path.lineWidth = 1
        path.setLineDash([4, 3.5], count: 2, phase: 0)
        (isHovering ? NSColor.controlAccentColor.withAlphaComponent(0.75) : NSColor.separatorColor.withAlphaComponent(0.36)).setStroke()
        path.stroke()

        let accent = isHovering ? NSColor.controlAccentColor : color.withAlphaComponent(0.82)
        accent.setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.6
        plus.lineCapStyle = .round
        plus.move(to: CGPoint(x: box.midX - 5.5, y: box.midY))
        plus.line(to: CGPoint(x: box.midX + 5.5, y: box.midY))
        plus.move(to: CGPoint(x: box.midX, y: box.midY - 5.5))
        plus.line(to: CGPoint(x: box.midX, y: box.midY + 5.5))
        plus.stroke()

        let text = "添加" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PanelAppearance.Typography.fileName,
            .foregroundColor: color.withAlphaComponent(isHovering ? 1.0 : 0.78)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: 55),
            withAttributes: attributes
        )
    }

    private func drawCompactBanner() {
        let insetRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let banner = NSBezierPath(roundedRect: insetRect, xRadius: 11, yRadius: 11)
        if isPressed {
            PanelAppearance.itemPressed.setFill()
        } else if isHovering {
            PanelAppearance.itemHover.setFill()
        } else {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.06).setFill()
        }
        banner.fill()

        banner.lineWidth = 1
        banner.setLineDash([4, 3.5], count: 2, phase: 0)
        (isHovering ? NSColor.controlAccentColor.withAlphaComponent(0.72) : NSColor.separatorColor.withAlphaComponent(0.34)).setStroke()
        banner.stroke()

        let tint = isHovering ? NSColor.controlAccentColor : color.withAlphaComponent(0.82)
        let labelText = "添加或拖入文件" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PanelAppearance.Typography.button,
            .foregroundColor: tint
        ]
        let textSize = labelText.size(withAttributes: attributes)
        let gap: CGFloat = 6
        let plusSpan: CGFloat = 9
        let totalWidth = plusSpan + gap + textSize.width
        let startX = (bounds.width - totalWidth) / 2
        let midY = bounds.height / 2

        tint.setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.5
        plus.lineCapStyle = .round
        plus.move(to: CGPoint(x: startX, y: midY))
        plus.line(to: CGPoint(x: startX + plusSpan, y: midY))
        plus.move(to: CGPoint(x: startX + plusSpan / 2, y: midY - plusSpan / 2))
        plus.line(to: CGPoint(x: startX + plusSpan / 2, y: midY + plusSpan / 2))
        plus.stroke()

        labelText.draw(
            at: CGPoint(x: startX + plusSpan + gap, y: (bounds.height - textSize.height) / 2),
            withAttributes: attributes
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installHoverTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onTap?()
    }
}
