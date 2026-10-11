import SwiftUI

/// Historique : séances par jour, et suivi des objectifs (ce qui avance, ce qui bloque).
struct HistoryView: View {
    @ObservedObject var store: Store
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(title: "Historique") { store.route = .main }
            HStack(spacing: 18) {
                tabButton("Séances", index: 0)
                tabButton("Objectifs", index: 1)
                Spacer()
                if tab == 0 {
                    Button("+ Ajouter") { store.route = .edit(nil) }.buttonStyle(CapsuleStyle(kind: .outline, height: 30))
                }
            }
            ScrollView {
                if tab == 0 { sessions } else { objectives }
            }
            .frame(height: 440)
        }
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.geist(13, tab == index ? .semibold : .medium))
                    .foregroundStyle(tab == index ? Theme.ink : Theme.muted)
                Rectangle().fill(tab == index ? Theme.ink : Color.clear).frame(height: 1.5)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Séances

    private var groupedDays: [(day: Date, sessions: [Session])] {
        let cal = Calendar.fr
        let groups = Dictionary(grouping: store.data.sessions) { cal.startOfDay(for: $0.start) }
        return groups.keys.sorted(by: >).prefix(60).map { day in
            (day, groups[day, default: []].sorted { $0.start > $1.start })
        }
    }

    @ViewBuilder private var sessions: some View {
        if store.data.sessions.isEmpty {
            Text("Aucune séance pour l'instant. Lance le chrono ou ajoute une séance.")
                .font(.geist(13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groupedDays, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            MicroLabel(text: Fmt.dayShort(group.day))
                            Spacer()
                            Text(Fmt.hm(group.sessions.reduce(0) { $0 + $1.duration }))
                                .font(.mono(11))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.bottom, 4)
                        ForEach(group.sessions) { s in
                            SessionRow(store: store, session: s)
                        }
                    }
                }
            }
        }
    }

    // MARK: Objectifs

    @ViewBuilder private var objectives: some View {
        if store.data.objectives.isEmpty {
            Text("Les objectifs apparaîtront ici au fil des séances, déduits par Claude de tes conversations.")
                .font(.geist(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(store.clients) { c in
                    let list = store.data.objectives.filter { $0.clientID == c.id }.sorted(by: order)
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            MicroLabel(text: c.name)
                            ForEach(list, id: \.self) { o in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 10) {
                                        Text(o.title)
                                            .font(.geist(13, .medium))
                                            .foregroundStyle(o.status == .termine ? Theme.faint : Theme.ink)
                                            .lineLimit(1)
                                        Spacer(minLength: 6)
                                        StatusTag(status: o.status, streak: o.blockedStreak)
                                    }
                                    Text((o.detail.isEmpty ? "" : o.detail + " · ") + "vu le " + Fmt.dayShort(o.lastSeen))
                                        .font(.geist(12))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Les blocages d'abord (les plus anciens en tête), puis ce qui avance, puis ce qui est terminé.
    private func order(_ a: ObjectiveRecord, _ b: ObjectiveRecord) -> Bool {
        func rank(_ s: ObjectiveStatus) -> Int { s == .bloque ? 0 : s == .avance ? 1 : 2 }
        if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
        if a.blockedStreak != b.blockedStreak { return a.blockedStreak > b.blockedStreak }
        return a.lastSeen > b.lastSeen
    }
}

/// Une séance dans l'historique ; clic pour la modifier.
struct SessionRow: View {
    @ObservedObject var store: Store
    let session: Session

    var body: some View {
        Button {
            if session.reviewed { store.route = .edit(session.id) } else { store.beginReview(session.id) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text("\(Fmt.time(session.start))–\(Fmt.time(session.end))")
                        .font(.mono(12))
                        .foregroundStyle(Theme.muted)
                    Text(store.client(session.clientID)?.name ?? "?")
                        .font(.geist(13, .medium))
                        .foregroundStyle(Theme.ink)
                    if !session.reviewed {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6).help("À valider")
                    }
                    if session.imported {
                        Text("autre Mac").font(.mono(10)).foregroundStyle(Theme.muted).help("Notée sur ton autre Mac, reprise depuis l'agenda")
                    }
                    Spacer()
                    Text(Fmt.hm(session.duration)).font(.mono(12)).foregroundStyle(Theme.ink)
                }
                if let first = session.title.isEmpty ? session.note.split(separator: "\n").first.map(String.init) : session.title {
                    Text(first.trimmingCharacters(in: CharacterSet(charactersIn: "• ")))
                        .font(.geist(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
