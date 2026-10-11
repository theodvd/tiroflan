import AppKit

/// Petit flan de la barre des menus, dessiné en vectoriel (net sur tous les écrans).
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 16)

    /// Au repos : image « modèle », macOS la colore selon la barre (claire ou sombre).
    static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            draw(outline: .black, caramel: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Chrono en cours : caramel orange, contour de la couleur du texte de la barre.
    static func running(accent: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            draw(outline: .labelColor, caramel: accent)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Corps en trapèze (contour) et nappe de caramel avec deux coulures (plein).
    static func draw(outline: NSColor, caramel: NSColor) {
        let top: CGFloat = 3, bottom: CGFloat = 13.5
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 5, y: top))
        body.line(to: NSPoint(x: 13, y: top))
        body.line(to: NSPoint(x: 15.5, y: bottom))
        body.line(to: NSPoint(x: 2.5, y: bottom))
        body.close()
        body.lineWidth = 1.5
        body.lineJoinStyle = .round

        let nappe = NSBezierPath()
        nappe.move(to: NSPoint(x: 5, y: top))
        nappe.line(to: NSPoint(x: 13, y: top))
        nappe.line(to: NSPoint(x: 13.75, y: 6.2))
        nappe.curve(to: NSPoint(x: 11.4, y: 9.4), controlPoint1: NSPoint(x: 12.4, y: 6.2), controlPoint2: NSPoint(x: 12.3, y: 9.4))
        nappe.curve(to: NSPoint(x: 10.2, y: 6.6), controlPoint1: NSPoint(x: 10.5, y: 9.4), controlPoint2: NSPoint(x: 10.8, y: 6.6))
        nappe.line(to: NSPoint(x: 7.8, y: 6.6))
        nappe.curve(to: NSPoint(x: 6.6, y: 8.7), controlPoint1: NSPoint(x: 7.2, y: 6.6), controlPoint2: NSPoint(x: 7.4, y: 8.7))
        nappe.curve(to: NSPoint(x: 5.5, y: 6.3), controlPoint1: NSPoint(x: 5.8, y: 8.7), controlPoint2: NSPoint(x: 6.0, y: 6.3))
        nappe.line(to: NSPoint(x: 4.25, y: 6.2))
        nappe.close()

        caramel.setFill()
        nappe.fill()
        outline.setStroke()
        body.stroke()
    }
}
