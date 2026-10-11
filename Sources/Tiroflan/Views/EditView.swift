import SwiftUI

/// Ajout d'une séance oubliée, ou correction d'une séance existante.
struct EditView: View {
    @ObservedObject var store: Store
    let sessionID: UUID?

    @State private var clientID: UUID = UUID()
    @State private var day = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var title = ""
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BackHeader(title: sessionID == nil ? "Ajouter une séance" : mirrored ? "Séance d'un autre Mac" : "Modifier la séance") {
                store.route = .history
            }

            HStack(spacing: 16) {
                ForEach(store.clients) { c in
                    ClientRadio(name: c.name, selected: c.id == clientID) { clientID = c.id }
                }
            }
            .disabled(mirrored)

            VStack(alignment: .leading, spacing: 10) {
                row("Jour") {
                    DatePicker("Jour", selection: $day, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                row("Début") {
                    DatePicker("Début", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                row("Fin") {
                    DatePicker("Fin", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }
            .disabled(mirrored)

            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: "Durée")
                Spacer()
                Text(valid ? Fmt.hm(range.end.timeIntervalSince(range.start)) : "fin avant début")
                    .font(.mono(valid ? 24 : 13))
                    .tracking(valid ? -1 : 0)
                    .foregroundStyle(valid ? Theme.ink : Theme.accent)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(text: "Titre dans l'agenda")
                TextField("Titre de la séance", text: $title)
                    .textFieldStyle(.plain)
                    .font(.geist(14, .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .fieldBox()
                MicroLabel(text: "Ce que j'ai fait").padding(.top, 6)
                TextEditor(text: $note)
                    .font(.geist(13))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 96)
                    .fieldBox()
            }
            .disabled(mirrored)

            if mirrored {
                HStack(spacing: 10) {
                    Text("Notée sur ton autre Mac et reprise depuis l'agenda : elle se modifie là-bas.")
                        .font(.geist(12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Fermer") { store.route = .history }.buttonStyle(CapsuleStyle(kind: .outline, height: 44))
                }
            } else {
                editButtons
            }
        }
        .onAppear(perform: load)
    }

    /// Séance notée sur un autre Mac : lecture seule.
    private var mirrored: Bool {
        sessionID.flatMap { store.session($0) }?.imported ?? false
    }

    private var editButtons: some View {
        HStack(spacing: 10) {
            if let id = sessionID {
                Button(confirmDelete ? "Confirmer" : "Supprimer") {
                    if confirmDelete {
                        store.deleteSession(id)
                        store.route = .history
                    } else {
                        confirmDelete = true
                    }
                }
                .buttonStyle(CapsuleStyle(kind: .ghost, height: 44))
                .foregroundStyle(confirmDelete ? Theme.accent : Theme.muted)
            }
            Spacer()
            Button("Annuler") { store.route = .history }.buttonStyle(CapsuleStyle(kind: .outline, height: 44))
            Button("Enregistrer") {
                store.upsertSession(id: sessionID, clientID: clientID, start: range.start, end: range.end, title: title, note: note)
                store.route = .history
            }
            .buttonStyle(CapsuleStyle(kind: .ink, height: 44))
            .disabled(!valid)
            .opacity(valid ? 1 : 0.4)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            MicroLabel(text: label).frame(width: 60, alignment: .leading)
            content()
            Spacer()
        }
    }

    /// Début et fin complets, à partir du jour et des heures choisis.
    private var range: (start: Date, end: Date) {
        (combine(day, startTime), combine(day, endTime))
    }

    private var valid: Bool { range.end > range.start }

    private func combine(_ day: Date, _ time: Date) -> Date {
        let cal = Calendar.fr
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = sessionID, let s = store.session(id) {
            clientID = s.clientID
            day = s.start
            startTime = s.start
            endTime = s.end
            title = s.title
            note = s.note
        } else {
            clientID = store.currentClientID
            let now = Date()
            day = now
            endTime = now
            startTime = now.addingTimeInterval(-3600)
        }
    }
}
