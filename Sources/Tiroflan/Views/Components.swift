import SwiftUI

/// Petite étiquette en capitales, chasse fixe, espacée (« AGENDA · GOOGLE »).
struct MicroLabel: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.mono(10))
            .tracking(1.4)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Bouton en forme de pilule : contour, encre pleine ou discret.
struct CapsuleStyle: ButtonStyle {
    enum Kind { case outline, ink, ghost }
    var kind: Kind = .outline
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.geist(13, .medium))
            .lineLimit(1)
            .padding(.horizontal, kind == .ghost ? 0 : 14)
            .frame(height: height)
            .foregroundStyle(kind == .ink ? Color.white : kind == .ghost ? Theme.muted : Theme.ink)
            .background(Capsule().fill(kind == .ink ? Theme.ink : Color.clear))
            .overlay(Capsule().strokeBorder(kind == .outline ? Theme.control : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Interrupteur encre (42 × 24) de la maquette.
struct InkToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.ink : Theme.control)
                .frame(width: 42, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(Color.white).frame(width: 18, height: 18).padding(3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "activé" : "désactivé")
    }
}

/// Pastille d'état d'un objectif : « avance » en contour, « bloqué » en orange plein.
struct StatusTag: View {
    let status: ObjectiveStatus
    var streak: Int = 0

    private var text: String {
        switch status {
        case .avance: return "avance"
        case .termine: return "terminé"
        case .bloque: return streak >= 2 ? "bloqué · \(Fmt.ordinal(streak)) séance" : "bloqué"
        }
    }

    var body: some View {
        Text(text)
            .font(.mono(11))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(status == .bloque ? Theme.accent : Color.clear))
            .overlay(Capsule().strokeBorder(status == .bloque ? Color.clear : status == .termine ? Theme.control : Theme.ink,
                                            lineWidth: 1))
            .fixedSize()
    }
}

/// Choix du client, façon bouton radio.
struct ClientRadio: View {
    let name: String
    let selected: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.ink : Theme.faint, lineWidth: 1).frame(width: 12, height: 12)
                    if selected { Circle().fill(Theme.ink).frame(width: 6, height: 6) }
                }
                Text(name)
                    .font(.geist(13, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                    .lineLimit(1)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && !selected ? 0.4 : 1)
        .help(disabled && !selected ? "Arrête le chrono pour changer de client" : name)
    }
}

/// Bouton rond à icône (réglages, retour).
struct IconCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// En-tête des écrans secondaires : retour + titre.
struct BackHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconCircleButton(symbol: "chevron.left", label: "Retour", action: back)
            MicroLabel(text: title)
            Spacer()
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// Encadré blanc bordé, pour les champs et les bandeaux.
struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.fieldBorder, lineWidth: 1))
    }
}

extension View {
    func fieldBox() -> some View { modifier(FieldBox()) }
}

/// Triangle « lecture » du gros bouton rond.
struct PlayTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
