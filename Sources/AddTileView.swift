import AppKit

final class AddTileView: NSView {
    var onTap: (() -> Void)?

    private var color: NSColor = PanelAppearance.secondaryText
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
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

        if isHovering {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }

        let box = CGRect(x: (bounds.width - 40) / 2, y: 3, width: 40, height: 40)
        let path = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        path.lineWidth = 1
        path.setLineDash([3, 3], count: 2, phase: 0)
        NSColor.separatorColor.withAlphaComponent(isHovering ? 0.85 : 0.58).setStroke()
        path.stroke()

        let plusColor = color.withAlphaComponent(isHovering ? 0.78 : 0.58)
        plusColor.setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.4
        plus.move(to: CGPoint(x: box.midX - 6, y: box.midY))
        plus.line(to: CGPoint(x: box.midX + 6, y: box.midY))
        plus.move(to: CGPoint(x: box.midX, y: box.midY - 6))
        plus.line(to: CGPoint(x: box.midX, y: box.midY + 6))
        plus.stroke()

        let text = "添加" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: plusColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: 47),
            withAttributes: attributes
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onTap?()
    }
}
