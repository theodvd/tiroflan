import SwiftUI

/// Écran « Séance terminée » : résumé suggéré par Claude, objectifs repérés, agenda.
struct ReviewView: View {
    @ObservedObject var store: Store
    let sessionID: UUID

    var body: some View {
        if let s = store.session(sessionID), let d = store.draft {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(text: "Séance terminée")
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.hm(s.duration)).font(.mono(40)).tracking(-2).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(Fmt.time(s.start)) → \(Fmt.time(s.end))").font(.mono(12)).foregroundStyle(Theme.muted)
                    }
                    Text("\(store.client(s.clientID)?.name ?? "") · \(Fmt.dayLong(s.start))")
                        .font(.geist(13))
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel(text: "Titre dans l'agenda")
                    TextField(d.loading ? "Claude propose un titre…" : "Titre de la séance", text: $store.draftTitle)
                        .textFieldStyle(.plain)
                        .font(.geist(14, .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .fieldBox()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        MicroLabel(text: "Ce que j'ai fait")
                        Spacer()
                        Button("Régénérer") { store.generateSummary(for: sessionID) }
                            .buttonStyle(CapsuleStyle(kind: .outline, height: 28))
                            .disabled(d.loading)
                            .opacity(d.loading ? 0.4 : 1)
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $store.draftText)
                            .font(.geist(13))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.ink)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                        if d.loading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Je relis tes sessions Claude Code…").font(.geist(13)).foregroundStyle(Theme.muted)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Color.white)
                        }
                    }
                    .frame(height: 132)
                    .fieldBox()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(caption(d))
                        .font(.geist(12))
                        .foregroundStyle(d.error != nil ? Theme.ink : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !d.objectives.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel(text: "Objectifs repérés par Claude")
                        ForEach(d.objectives, id: \.self) { o in
                            HStack(alignment: .center, spacing: 10) {
                                Text(o.title).font(.geist(13)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer(minLength: 6)
                                StatusTag(status: o.status, streak: store.prospectiveStreak(o, clientID: s.clientID))
                            }
                            .help(o.detail)
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.calendarTitle(for: s.clientID).map { "Agenda « \($0) »" } ?? "Agenda")
                            .font(.geist(13, .medium))
                            .foregroundStyle(Theme.ink)
                        Text(store.calendarTitle(for: s.clientID) == nil ? "Choisis un agenda dans les réglages" : "Google Agenda")
                            .font(.geist(12))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    InkToggle(isOn: $store.draftAddToCalendar, label: "Ajouter la séance à l'agenda")
                        .disabled(store.calendarTitle(for: s.clientID) == nil && s.calendarEventID == nil)
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { Hairline() }

                HStack(spacing: 10) {
                    Button { store.skipReview() } label: { Text("Ignorer").frame(maxWidth: .infinity) }
                        .buttonStyle(CapsuleStyle(kind: .outline, height: 44))
                        .frame(width: 104)
                    Button { store.saveReview() } label: { Text("Enregistrer la séance").frame(maxWidth: .infinity) }
                        .buttonStyle(CapsuleStyle(kind: .ink, height: 44))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cette séance n'existe plus.").font(.geist(13)).foregroundStyle(Theme.muted)
                Button("Retour") { store.route = .main }.buttonStyle(CapsuleStyle())
            }
        }
    }

    private func caption(_ d: ReviewDraft) -> String {
        if let error = d.error { return error }
        if d.loading { return "Je relis les échanges de ce créneau, ça prend quelques secondes." }
        if d.sourceCount > 0 {
            let sessions = d.sourceCount > 1 ? "\(d.sourceCount) sessions" : "1 session"
            let range = d.sourceRange.isEmpty ? "" : " (\(d.sourceRange))"
            return "Suggéré d'après \(sessions) Claude Code\(range). Corrige-le avant d'enregistrer."
        }
        return "Écris ce que tu as fait."
    }
}
