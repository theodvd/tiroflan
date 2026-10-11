import SwiftUI

struct PanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Cadre du panneau (carte claire, coins arrondis) et aiguillage entre les écrans.
struct PanelRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var calendar: CalendarService
    let onSize: (CGSize) -> Void

    var body: some View {
        content
            .padding(18)
            .frame(width: 360, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light)
            .background(GeometryReader { g in Color.clear.preference(key: PanelSizeKey.self, value: g.size) })
            .onPreferenceChange(PanelSizeKey.self, perform: onSize)
    }

    @ViewBuilder private var content: some View {
        switch store.route {
        case .main:
            MainView(store: store, calendar: calendar)
        case .review(let id):
            ReviewView(store: store, sessionID: id)
        case .history:
            HistoryView(store: store)
        case .edit(let id):
            EditView(store: store, sessionID: id).id(id)
        case .settings:
            SettingsView(store: store, calendar: calendar)
        }
    }
}
