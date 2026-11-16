import AppKit

/// Template version of the app icon for the status bar: an orange outline with a
/// leaf, a segmented wheel ring and a centre hub. Drawn in code so it stays crisp
/// at every backing scale and tints automatically for light/dark menu bars.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orange"
        return image
    }

    static func draw(in rect: NSRect) {
        let s = rect.width / 18
        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Fruit body, nudged down-left to leave room for the leaf.
        let center = NSPoint(x: rect.minX + 8.5 * s, y: rect.minY + 8.5 * s)
        let bodyRadius = 7.6 * s
        let body = NSBezierPath()
        body.appendArc(withCenter: center, radius: bodyRadius, startAngle: 0, endAngle: 360)
        body.lineWidth = 1.5 * s
        body.stroke()

        // Wheel ring: four arcs with gaps on the diagonals, like the icon's petals.
        let ringRadius = 4.3 * s
        for quadrant in 0..<4 {
            let mid = CGFloat(quadrant) * 90
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: ringRadius, startAngle: mid - 30, endAngle: mid + 30)
            arc.lineWidth = 1.3 * s
            arc.lineCapStyle = .round
            arc.stroke()
        }

        // Hub.
        let hubRadius = 1.4 * s
        NSBezierPath(ovalIn: NSRect(x: center.x - hubRadius, y: center.y - hubRadius,
                                    width: hubRadius * 2, height: hubRadius * 2)).fill()

        // Leaf at the top right, overlapping the rim.
        let leaf = NSBezierPath()
        let base = NSPoint(x: rect.minX + 11.2 * s, y: rect.minY + 15.4 * s)
        let tip = NSPoint(x: rect.minX + 17.4 * s, y: rect.minY + 17.6 * s)
        leaf.move(to: base)
        leaf.curve(to: tip,
                   controlPoint1: NSPoint(x: rect.minX + 12.6 * s, y: rect.minY + 18.2 * s),
                   controlPoint2: NSPoint(x: rect.minX + 15.6 * s, y: rect.minY + 18.4 * s))
        leaf.curve(to: base,
                   controlPoint1: NSPoint(x: rect.minX + 16.6 * s, y: rect.minY + 15.4 * s),
                   controlPoint2: NSPoint(x: rect.minX + 13.4 * s, y: rect.minY + 14.6 * s))
        leaf.close()
        leaf.fill()
    }
}
