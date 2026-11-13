import AppKit

final class AddTileView: NSView {
    var onTap: (() -> Void)?

    var isCompactBanner = false {
        didSet {
            guard isCompactBanner != oldValue else { return }
            layer?.cornerRadius = isCompactBanner ? 12 : 14
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
        layer?.cornerRadius = 14
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

        let radius: CGFloat = 14
        let cardRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        if isPressed {
            PanelAppearance.itemPressed.setFill()
            cardPath.fill()
        } else if isHovering {
            PanelAppearance.itemHover.setFill()
            cardPath.fill()
            PanelAppearance.accentBorder.setStroke()
            cardPath.lineWidth = 0.75
            cardPath.stroke()
        } else {
            PanelAppearance.controlFill.setFill()
            cardPath.fill()
        }

        let iconSize = min(PanelAppearance.Grid.iconSize, max(1, bounds.width - 8))
        let box = CGRect(x: (bounds.width - iconSize) / 2, y: 9, width: iconSize, height: iconSize)
        let path = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        (isHovering ? PanelAppearance.accentSoftFill : PanelAppearance.controlFill).setFill()
        path.fill()
        path.lineWidth = 1
        path.setLineDash([4, 3.5], count: 2, phase: 0)
        (isHovering ? PanelAppearance.accent.withAlphaComponent(0.75) : PanelAppearance.accentBorder).setStroke()
        path.stroke()

        let plusColor = isHovering ? PanelAppearance.accent : PanelAppearance.accent.withAlphaComponent(0.85)
        plusColor.setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.75
        plus.lineCapStyle = .round
        plus.move(to: CGPoint(x: box.midX - 5.5, y: box.midY))
        plus.line(to: CGPoint(x: box.midX + 5.5, y: box.midY))
        plus.move(to: CGPoint(x: box.midX, y: box.midY - 5.5))
        plus.line(to: CGPoint(x: box.midX, y: box.midY + 5.5))
        plus.stroke()

        let text = "添加" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PanelAppearance.Typography.fileName,
            .foregroundColor: isHovering ? PanelAppearance.primaryText : PanelAppearance.secondaryText
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: box.maxY + 6),
            withAttributes: attributes
        )
    }

    private func drawCompactBanner() {
        let insetRect = bounds.insetBy(dx: 1, dy: 1)
        let banner = NSBezierPath(roundedRect: insetRect, xRadius: 12, yRadius: 12)
        if isPressed {
            PanelAppearance.itemPressed.setFill()
        } else if isHovering {
            PanelAppearance.itemHover.setFill()
        } else {
            PanelAppearance.cardFill.setFill()
        }
        banner.fill()

        banner.lineWidth = isHovering ? 1.0 : 0.75
        banner.setLineDash([4, 3.5], count: 2, phase: 0)
        (isHovering ? PanelAppearance.accent.withAlphaComponent(0.75) : PanelAppearance.accentBorder).setStroke()
        banner.stroke()

        let tint = isHovering ? PanelAppearance.primaryText : PanelAppearance.secondaryText
        let labelText = "添加或拖入文件" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PanelAppearance.Typography.button,
            .foregroundColor: tint
        ]
        let textSize = labelText.size(withAttributes: attributes)
        let badgeSize: CGFloat = 18
        let gap: CGFloat = 7
        let totalWidth = badgeSize + gap + textSize.width
        let startX = (bounds.width - totalWidth) / 2
        let midY = bounds.height / 2

        let badgeRect = CGRect(x: startX, y: midY - badgeSize / 2, width: badgeSize, height: badgeSize)
        PanelAppearance.accentSoftFill.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        PanelAppearance.accent.setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.6
        plus.lineCapStyle = .round
        plus.move(to: CGPoint(x: badgeRect.midX - 4, y: badgeRect.midY))
        plus.line(to: CGPoint(x: badgeRect.midX + 4, y: badgeRect.midY))
        plus.move(to: CGPoint(x: badgeRect.midX, y: badgeRect.midY - 4))
        plus.line(to: CGPoint(x: badgeRect.midX, y: badgeRect.midY + 4))
        plus.stroke()

        labelText.draw(
            at: CGPoint(x: badgeRect.maxX + gap, y: (bounds.height - textSize.height) / 2),
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
