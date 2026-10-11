import ServiceManagement
import SwiftUI

/// Réglages : clients, agenda, alertes, démarrage.
struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var calendar: CalendarService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(title: "Réglages") { store.route = .main }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    clients
                    agenda
                    alerts
                    startup
                }
                .padding(.bottom, 4)
            }
            .frame(height: 470)
            HStack {
                Text("Tiroflan 0.1").font(.mono(11)).foregroundStyle(Theme.faint)
                Spacer()
                Button("Quitter Tiroflan") { NSApp.terminate(nil) }.buttonStyle(CapsuleStyle(kind: .outline, height: 32))
            }
        }
    }

    // MARK: Clients

    private var clients: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "Clients")
            ForEach(store.clients) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Nom", text: Binding(get: { c.name }, set: { store.updateClient(c.id, name: $0) }))
                            .textFieldStyle(.plain)
                            .font(.geist(13, .medium))
                        if store.canRemoveClient(c.id) {
                            Button { store.removeClient(c.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                                    .frame(width: 24, height: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Supprimer \(c.name)")
                        }
                    }
                    TextField("Domaine e-mail des RDV (ex. tamtam.ai)",
                              text: Binding(get: { c.emailDomain }, set: { store.updateClient(c.id, domain: $0) }))
                        .textFieldStyle(.plain)
                        .font(.mono(11))
                        .foregroundStyle(Theme.muted)
                    HStack(spacing: 8) {
                        Text("Heures par semaine").font(.geist(12)).foregroundStyle(Theme.muted)
                        Spacer()
                        IconCircleButton(symbol: "minus", label: "Moins") { store.setWeeklyHours(c.id, (c.weeklyHours ?? 0) - 1) }
                        Text(c.weeklyHours.map { "\(Int($0)) h" } ?? "aucun").font(.mono(12)).foregroundStyle(Theme.ink).frame(width: 52)
                        IconCircleButton(symbol: "plus", label: "Plus") { store.setWeeklyHours(c.id, (c.weeklyHours ?? 0) + 1) }
                    }
                    if calendar.authorized {
                        HStack {
                            Text("Agenda").font(.geist(12)).foregroundStyle(Theme.muted)
                            Spacer()
                            Picker("Agenda de \(c.name)", selection: Binding(get: { c.calendarID ?? "" },
                                                                              set: { store.setClientCalendar(c.id, $0.isEmpty ? nil : $0) })) {
                                Text("Auto · \(calendar.calendarTitle(id: store.automaticCalendarID(for: c.id)) ?? "aucun")").tag("")
                                ForEach(calendar.writableCalendars, id: \.calendarIdentifier) { cal in
                                    Text(cal.title).tag(cal.calendarIdentifier)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190)
                        }
                    }
                }
                .padding(12)
                .fieldBox()
            }
            Button("+ Ajouter un client") { store.addClient() }.buttonStyle(CapsuleStyle(kind: .outline, height: 30))
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "Agenda")
            if !calendar.authorized {
                HStack {
                    Text("Agenda non connecté.").font(.geist(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Connecter") {
                        Task {
                            await calendar.requestAccess()
                            store.adoptDefaultCalendarIfNeeded()
                        }
                    }
                    .buttonStyle(CapsuleStyle(kind: .outline, height: 30))
                }
            } else {
                HStack {
                    Text("Agenda par défaut").font(.geist(13)).foregroundStyle(Theme.ink)
                    Spacer()
                    Picker("Agenda", selection: Binding(get: { store.settings.writeCalendarID ?? "" },
                                                        set: { store.setWriteCalendar($0.isEmpty ? nil : $0) })) {
                        Text("Auto · \(calendar.calendarTitle(id: store.defaultCalendarID) ?? "aucun")").tag("")
                        ForEach(calendar.writableCalendars, id: \.calendarIdentifier) { cal in
                            Text("\(cal.title) · \(cal.source.title)").tag(cal.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                HStack {
                    Text("Ajouter chaque séance par défaut").font(.geist(13)).foregroundStyle(Theme.ink)
                    Spacer()
                    InkToggle(isOn: Binding(get: { store.settings.writeToCalendar }, set: { store.setWriteToCalendar($0) }),
                              label: "Ajouter chaque séance à l'agenda")
                }
                if store.clients.contains(where: {
                    calendar.calendarID(named: $0.name) == nil && calendar.calendarID(forDomain: $0.emailDomain) == nil
                        && $0.calendarID == nil && $0.name != "Perso"
                }) {
                    Text("Astuce : un agenda Google qui porte le nom d'un client (ex. « Tamtam ») ou l'adresse de son domaine (ex. prenom@tamtam.ai, ajouté dans Comptes internet) reçoit automatiquement ses séances.")
                        .font(.geist(12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Alertes

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "Alertes")
            stepperRow("Absence détectée après", value: "\(store.settings.idleMinutes) min",
                       minus: { store.setIdleMinutes(store.settings.idleMinutes - 5) },
                       plus: { store.setIdleMinutes(store.settings.idleMinutes + 5) })
            stepperRow("Chrono long après", value: "\(store.settings.longRunHours) h",
                       minus: { store.setLongRunHours(store.settings.longRunHours - 1) },
                       plus: { store.setLongRunHours(store.settings.longRunHours + 1) })
        }
    }

    private func stepperRow(_ label: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.geist(13)).foregroundStyle(Theme.ink)
            Spacer()
            IconCircleButton(symbol: "minus", label: "Moins", action: minus)
            Text(value).font(.mono(13)).foregroundStyle(Theme.ink).frame(width: 52)
            IconCircleButton(symbol: "plus", label: "Plus", action: plus)
        }
    }

    // MARK: Démarrage

    private var startup: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "Démarrage")
            HStack {
                Text("Lancer Tiroflan à l'ouverture de session").font(.geist(13)).foregroundStyle(Theme.ink)
                Spacer()
                InkToggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }), label: "Lancer à l'ouverture de session")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Chemin de Claude Code (vide = automatique)").font(.geist(12)).foregroundStyle(Theme.muted)
                TextField(Summarizer.findClaude(override: nil)?.path ?? "introuvable",
                          text: Binding(get: { store.settings.claudePath ?? "" }, set: { store.setClaudePath($0) }))
                    .textFieldStyle(.plain)
                    .font(.mono(11))
                    .padding(10)
                    .fieldBox()
            }
        }
    }
}
