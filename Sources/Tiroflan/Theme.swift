import AppKit
import CoreText
import SwiftUI

/// Palette de la direction « Instrument » : encre, gris froids, un seul orange vif.
enum Theme {
    static let panel = Color(hex: 0xF6F7F8)
    static let ink = Color(hex: 0x111214)
    static let muted = Color(hex: 0x5B6067)
    static let faint = Color(hex: 0x8A9098)
    static let ghost = Color(hex: 0xB9BDC3)
    static let hairline = Color(hex: 0xDCDFE3)
    static let border = Color(hex: 0xD2D5DA)
    static let control = Color(hex: 0xC4C8CD)
    static let fieldBorder = Color(hex: 0xD9DCE0)
    static let accent = Color(hex: 0xFF4F00)

    /// Niveaux de la grille d'activité, du vide (0 h) au plein (plus de 6 h).
    static let heat: [Color] = [
        Color(hex: 0xE2E4E7), Color(hex: 0xB8BABD), Color(hex: 0x8A8C8E), Color(hex: 0x545557), Color(hex: 0x111214),
    ]

    static let accentNS = NSColor(srgbRed: 1, green: 79 / 255, blue: 0, alpha: 1)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension Font {
    /// Geist, la police de l'interface.
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist", size: size).weight(weight)
    }

    /// Geist Mono, pour les chiffres et les petites étiquettes.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist Mono", size: size).weight(weight)
    }
}

enum Fonts {
    /// Enregistre les polices embarquées dans Tiroflan.app/Contents/Resources/Fonts.
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Version AppKit, pour le texte de la barre des menus.
    static func ns(_ family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

/// Formats d'affichage (heures, dates en français).
enum Fmt {
    static let fr = Locale(identifier: "fr_FR")

    /// 3:09 (heures:minutes).
    static func hm(_ t: TimeInterval) -> String {
        let minutes = Int(max(0, t) / 60)
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// 1:23:47 (heures:minutes:secondes).
    static func hms(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        return "\(s / 3600):" + String(format: "%02d:%02d", (s % 3600) / 60, s % 60)
    }

    /// « 1 h 52 » ou « 38 min ».
    static func words(_ t: TimeInterval) -> String {
        let minutes = Int(max(0, t) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let m = minutes % 60
        return m == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h " + String(format: "%02d", m)
    }

    /// « 268 h », arrondi à l'heure.
    static func hours(_ t: TimeInterval) -> String { "\(Int((t / 3600).rounded())) h" }

    static func time(_ d: Date) -> String { formatter("HH:mm").string(from: d) }
    /// « jeudi 28 janvier ».
    static func dayLong(_ d: Date) -> String { formatter("EEEE d MMMM").string(from: d) }
    /// « jeu. 28 janv. ».
    static func dayShort(_ d: Date) -> String { formatter("EEE d MMM").string(from: d) }
    /// « janv. ».
    static func month(_ d: Date) -> String { formatter("MMM").string(from: d) }

    /// 1re, 2e, 3e…
    static func ordinal(_ n: Int) -> String { n == 1 ? "1re" : "\(n)e" }

    private static var cache: [String: DateFormatter] = [:]
    private static func formatter(_ pattern: String) -> DateFormatter {
        if let f = cache[pattern] { return f }
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = pattern
        cache[pattern] = f
        return f
    }
}

extension Calendar {
    /// Calendrier français : semaines du lundi au dimanche.
    static var fr: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Fmt.fr
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
}
