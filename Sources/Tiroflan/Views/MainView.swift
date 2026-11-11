import SwiftUI

/// Écran principal du panneau : client, chrono, totaux, agenda, grille d'activité.
struct MainView: View {
    @ObservedObject var store: Store
    @ObservedObject var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            banners
            TimerBlock(store: store)
            TotalsRow(store: store)
            WeekLine(store: store, calendar: calendar)
            agenda
            activity
            footer
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack {
            HStack(spacing: 16) {
                ForEach(store.clients.prefix(3)) { c in
                    ClientRadio(name: c.name, selected: c.id == store.currentClientID,
                                disabled: store.data.running != nil) {
                        store.selectClient(c.id)
                    }
                }
                Button("+ client") { store.route = .settings }
                    .buttonStyle(.plain)
                    .font(.geist(13))
                    .foregroundStyle(Theme.muted)
                    .frame(height: 30)
            }
            Spacer(minLength: 8)
            IconCircleButton(symbol: calendar.syncing ? "hourglass" : "arrow.clockwise",
                             label: calendar.syncing ? "Synchronisation avec Google…" : "Resynchroniser l'agenda Google") {
                calendar.resync()
            }
            IconCircleButton(symbol: "slider.horizontal.3", label: "Réglages") { store.route = .settings }
        }
    }

    // MARK: Bandeaux (séance à valider, absence)

    @ViewBuilder private var banners: some View {
        if let pending = store.pendingReviews.first {
            Button { store.beginReview(pending.id) } label: {
                HStack(spacing: 10) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text("Séance à valider · \(store.client(pending.clientID)?.name ?? "") \(Fmt.hm(pending.duration))")
                        .font(.geist(13, .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .fieldBox()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if let p = store.extensionProposal {
            VStack(alignment: .leading, spacing: 10) {
                Text("Il te manque \(Fmt.words(p.missing)) pour \(store.client(p.clientID)?.name ?? "") cette semaine.")
                    .font(.geist(13, .medium))
                    .foregroundStyle(Theme.ink)
                Text("Allonger « \(p.slot.title) » \(Fmt.dayShort(p.slot.start)), \(Fmt.time(p.slot.start)) → \(Fmt.time(p.newEnd)) ?")
                    .font(.geist(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Allonger") { store.acceptExtension() }.buttonStyle(CapsuleStyle(kind: .ink, height: 30))
                    Button("Non") { store.dismissExtension() }.buttonStyle(CapsuleStyle(kind: .outline, height: 30))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldBox()
        }
        if let away = store.idleAway {
            VStack(alignment: .leading, spacing: 10) {
                Text("Absent \(Fmt.words(away)) pendant la séance.")
                    .font(.geist(13, .medium))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Button("Retirer ce temps") { store.removeIdle() }.buttonStyle(CapsuleStyle(kind: .ink, height: 30))
                    Button("Garder") { store.keepIdle() }.buttonStyle(CapsuleStyle(kind: .outline, height: 30))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldBox()
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(text: "Agenda · aujourd'hui")
            if !calendar.authorized {
                HStack {
                    Text(calendar.notDetermined ? "Connecte ton agenda Google." : "Accès à l'agenda refusé.")
                        .font(.geist(13))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if calendar.notDetermined {
                        Button("Connecter") {
                            Task {
                                await calendar.requestAccess()
                                store.adoptDefaultCalendarIfNeeded()
                            }
                        }
                        .buttonStyle(CapsuleStyle(kind: .outline, height: 30))
                    } else {
                        Button("Réglages système") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(CapsuleStyle(kind: .outline, height: 30))
                    }
                }
                .padding(.vertical, 5)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    let items = visibleItems(at: ctx.date)
                    if items.isEmpty {
                        Text("Aucun rendez-vous à venir aujourd'hui.")
                            .font(.geist(13))
                            .foregroundStyle(Theme.faint)
                            .padding(.vertical, 5)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                AgendaRow(store: store, item: item, now: ctx.date)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Les deux derniers RDV passés au plus, puis les prochains, quatre lignes en tout.
    private func visibleItems(at now: Date) -> [AgendaItem] {
        let past = calendar.todayEvents.filter { $0.end <= now }.suffix(1)
        let rest = calendar.todayEvents.filter { $0.end > now }
        return Array((Array(past) + rest).prefix(4))
    }

    // MARK: Activité

    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel(text: "Activité · 21 semaines")
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                let h = store.heatmap(at: ctx.date)
                HeatmapView(columns: h.columns, months: h.months)
            }
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack {
            Button("+ Ajouter une séance") { store.route = .edit(nil) }
                .buttonStyle(CapsuleStyle(kind: .outline))
            Spacer()
            Button("Historique →") { store.route = .history }
                .buttonStyle(CapsuleStyle(kind: .ghost))
        }
    }
}

/// Chrono : grande durée en chasse fixe et gros bouton rond (orange quand ça tourne).
struct TimerBlock: View {
    @ObservedObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let running = store.data.running
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle().fill(running != nil ? Theme.accent : Theme.ghost).frame(width: 6, height: 6)
                        MicroLabel(text: running.map { "En cours · depuis \(Fmt.time($0.start))" } ?? "Prêt · \(store.currentClientName)")
                    }
                    Text(running != nil ? Fmt.hms(store.elapsedRunning(at: ctx.date)) : "0:00:00")
                        .font(.mono(54))
                        .tracking(-3.2)
                        .monospacedDigit()
                        .foregroundStyle(running != nil ? Theme.ink : Theme.ghost)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 12)
                Button { store.toggleTimer() } label: {
                    ZStack {
                        Circle()
                            .fill(running != nil ? Theme.accent : Theme.ink)
                            .frame(width: 64, height: 64)
                            .shadow(color: (running != nil ? Theme.accent : Theme.ink).opacity(0.3), radius: 8, y: 5)
                        if running != nil {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white).frame(width: 18, height: 18)
                        } else {
                            PlayTriangle().fill(Color.white).frame(width: 17, height: 19).offset(x: 2)
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(running != nil ? "Arrêter le chrono" : "Lancer le chrono")
                .help(running != nil ? "Arrêter le chrono" : "Lancer le chrono \(store.currentClientName)")
            }
        }
    }
}

/// Totaux du jour, de la semaine et du mois, séparés par des filets.
struct TotalsRow: View {
    @ObservedObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            HStack(spacing: 0) {
                cell("Auj.", Fmt.hm(store.total(.day, at: ctx.date)), divider: false)
                cell("Semaine", Fmt.hm(store.total(.weekOfYear, at: ctx.date)), divider: true)
                cell("Mois", Fmt.hm(store.total(.month, at: ctx.date)), divider: true)
            }
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private func cell(_ label: String, _ value: String, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MicroLabel(text: label)
            Text(value).font(.mono(20)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 10)
        .padding(.leading, divider ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if divider { Rectangle().fill(Theme.hairline).frame(width: 1) }
        }
    }
}

/// Décompte de la semaine du client sélectionné, s'il a un objectif d'heures.
struct WeekLine: View {
    @ObservedObject var store: Store
    /// Observé pour recalculer dès que l'agenda change (resynchro, créneau supprimé dans Google).
    @ObservedObject var calendar: CalendarService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            if let b = store.weekBalance(for: store.currentClientID, at: ctx.date) {
                HStack(spacing: 6) {
                    Text("\(store.currentClientName) · \(Fmt.words(b.done)) / \(Fmt.words(b.target))")
                        .foregroundStyle(Theme.ink)
                    Text("· \(Fmt.words(b.planned)) planifiées").foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    // Écart signé : « +x en trop » si on a planifié plus que l'objectif, « -y à caser » sinon.
                    Text(b.gap >= 60 ? "+\(Fmt.words(b.gap)) en trop"
                         : b.gap <= -60 ? "-\(Fmt.words(-b.gap)) à caser" : "semaine pile")
                        .foregroundStyle(b.gap <= -60 ? Theme.accent : Theme.muted)
                }
                .font(.geist(12))
                .lineLimit(1)
                .padding(.top, -8)
            }
        }
    }
}

/// Une ligne d'agenda : heure, titre, et action (lancer, armer le chrono, ou « fait »).
struct AgendaRow: View {
    @ObservedObject var store: Store
    let item: AgendaItem
    let now: Date

    var body: some View {
        let past = item.end <= now
        let ongoing = item.start <= now && item.end > now
        let soon = item.start > now && item.start.timeIntervalSince(now) <= 600
        let armed = store.armedEventIDs.contains(item.id)

        HStack(spacing: 14) {
            Text(Fmt.time(item.start))
                .font(.mono(12))
                .foregroundStyle(past ? Theme.faint : Theme.ink)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.geist(13, past ? .regular : .medium))
                    .strikethrough(past, color: Theme.faint)
                    .foregroundStyle(past ? Theme.faint : Theme.ink)
                    .lineLimit(1)
                if !past {
                    Text(ongoing ? "en cours" : "dans " + Fmt.words(item.start.timeIntervalSince(now)))
                        .font(.geist(12))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 6)
            if past {
                Text("fait").font(.mono(11)).foregroundStyle(Theme.faint)
            } else if store.data.running == nil && (ongoing || soon) {
                Button("Lancer") { store.start(clientID: store.clientFor(item)) }
                    .buttonStyle(CapsuleStyle(kind: .ink, height: 30))
            } else if !ongoing {
                Button(armed ? "Armé · \(Fmt.time(item.start))" : "Chrono à \(Fmt.time(item.start))") {
                    store.toggleArm(item.id)
                }
                .buttonStyle(CapsuleStyle(kind: armed ? .ink : .outline, height: 30))
                .help(armed ? "Le chrono démarrera tout seul" : "Démarrer le chrono automatiquement à l'heure du RDV")
            }
        }
        .padding(.vertical, 5)
    }
}
