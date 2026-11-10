import AppKit

extension NSColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)

        let r, g, b, a: CGFloat
        switch value.count {
        case 8:
            r = CGFloat((number >> 24) & 0xFF) / 255
            g = CGFloat((number >> 16) & 0xFF) / 255
            b = CGFloat((number >> 8) & 0xFF) / 255
            a = CGFloat(number & 0xFF) / 255
        default:
            r = CGFloat((number >> 16) & 0xFF) / 255
            g = CGFloat((number >> 8) & 0xFF) / 255
            b = CGFloat(number & 0xFF) / 255
            a = 1
        }

        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#1C1C1E" }
        let r = Int(round(color.redComponent * 255))
        let g = Int(round(color.greenComponent * 255))
        let b = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var perceivedLuminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}
