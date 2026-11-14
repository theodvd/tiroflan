import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Écran affiché dans le panneau.
enum Route: Equatable {
    case main
    case review(UUID)
    case history
    case edit(UUID?)
    case settings
}

/// Brouillon de l'écran « Séance terminée ».
struct ReviewDraft {
    var sessionID: UUID
    var loading = true
    var title = ""
    var text = ""
    var objectives: [ObjectiveMention] = []
    var sourceCount = 0
    var sourceRange = ""
    var error: String?
    var addToCalendar = true
}

/// Une case de la grille d'activité.
struct HeatCell: Identifiable {
    let id: Date
    let level: Int
    let isToday: Bool
    let isFuture: Bool
    let label: String
}

/// État central de l'app : données, chrono, alertes, liens avec l'agenda et Claude.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var data: AppData
    @Published var route: Route = .main
    @Published var draft: ReviewDraft?
    /// Absences détectées pendant le chrono (début et fin exacts, triées), en attente de décision :
    /// retirer (la séance est coupée à ces endroits) ou garder.
    @Published private(set) var absences: [DateInterval] = []
    @Published private(set) var armedEventIDs: Set<String> = []
    /// Proposition d'allonger un créneau planifié, après une séance plus courte que prévu.
    @Published private(set) var extensionProposal: ExtensionProposal?

    let calendar: CalendarService
    var notifier: Notifier?
    /// Appelé à chaque changement visible dans la barre des menus.
    var onChange: (() -> Void)?
    /// Demande d'ouverture du panneau (clic sur une notification).
    var onRequestPanel: (() -> Void)?

    private let summarizer = Summarizer()
    private let fileURL = supportDir.appendingPathComponent("data.json")
    private var backedUp = false
    private var idleSince: Date?
    private var waitingForInput = false
    private var longRunNotified = false
    private var notifiedEventIDs: Set<String> = []
    private var tickCount = 0
    /// Séances enregistrées avant la fin du résumé : il leur sera appliqué à son arrivée.
    private var applyWhenReady: Set<UUID> = []
    /// Séances dont le résumé est en cours de rédaction en arrière-plan (ajout manuel).
    private var autoSummarizing: Set<UUID> = []
    /// Séances de ce Mac dont l'événement est introuvable, avec le nombre de relectures d'affilée.
    private var missingPasses: [UUID: Int] = [:]
    /// Alerte « séances introuvables » déjà envoyée pour la panne en cours.
    private var missingAlerted = false

    init(calendar: CalendarService) {
        self.calendar = calendar
        let fm = FileManager.default
        if let raw = try? Data(contentsOf: fileURL), let decoded = try? Store.decoder.decode(AppData.self, from: raw) {
            data = decoded
        } else {
            if fm.fileExists(atPath: fileURL.path) {
                // Fichier illisible : on le met de côté plutôt que de l'écraser.
                let aside = supportDir.appendingPathComponent("data-illisible-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.moveItem(at: fileURL, to: aside)
            }
            data = AppData.initial()
        }
        calendar.excludedEventIDs = Set(data.sessions.compactMap(\.calendarEventID))
        checkSleepGap()
        syncFromCalendar()
    }

    // MARK: - Lecture

    var clients: [Client] { data.clients }
    var settings: Preferences { data.settings }
    func client(_ id: UUID) -> Client? { data.clients.first { $0.id == id } }
    func session(_ id: UUID) -> Session? { data.sessions.first { $0.id == id } }

    /// Client du chrono en cours, sinon client sélectionné.
    var currentClientID: UUID {
        data.running?.clientID ?? data.selectedClientID ?? data.clients.first?.id ?? UUID()
    }

    var currentClientName: String { client(currentClientID)?.name ?? "" }

    var pendingReviews: [Session] {
        data.sessions.filter { !$0.reviewed }.sorted { $0.end > $1.end }
    }

    /// Durée totale des absences en attente de décision ; nil s'il n'y en a pas.
    var idleAway: TimeInterval? {
        absences.isEmpty ? nil : absences.reduce(0) { $0 + $1.duration }
    }

    /// Horaires de l'absence en attente (« 21:04 → 08:50 ») quand il n'y en a qu'une.
    var absenceRange: String? {
        guard absences.count == 1, let a = absences.first else { return nil }
        return "\(Fmt.time(a.start)) → \(Fmt.time(a.end))"
    }

    func elapsedRunning(at date: Date) -> TimeInterval {
        guard let r = data.running else { return 0 }
        return max(0, date.timeIntervalSince(r.start) - r.excludedSeconds)
    }

    /// Total des séances commencées dans l'intervalle, chrono en cours compris.
    private func total(in interval: DateInterval, at date: Date) -> TimeInterval {
        var t = data.sessions.filter { interval.contains($0.start) }.reduce(0) { $0 + $1.duration }
        if let r = data.running, interval.contains(r.start) { t += elapsedRunning(at: date) }
        return t
    }

    func total(_ component: Calendar.Component, at date: Date) -> TimeInterval {
        guard let interval = Calendar.fr.dateInterval(of: component, for: date) else { return 0 }
        return total(in: interval, at: date)
    }

    /// Agenda où écrire les séances d'un client : celui choisi pour lui, sinon l'agenda qui porte son nom
    /// (ex. « Tamtam » en bleu nuit), sinon celui de son domaine (ex. theo.david@tamtam.ai),
    /// sinon l'agenda par défaut des réglages, sinon celui de macOS.
    func calendarID(for clientID: UUID) -> String? {
        client(clientID)?.calendarID ?? automaticCalendarID(for: clientID)
    }

    /// Choix automatique, quand aucun agenda n'est imposé pour ce client.
    func automaticCalendarID(for clientID: UUID) -> String? {
        let fallback = data.settings.writeCalendarID ?? defaultCalendarID
        guard let c = client(clientID) else { return fallback }
        return calendar.calendarID(named: c.name) ?? calendar.calendarID(forDomain: c.emailDomain) ?? fallback
    }

    /// Agenda par défaut quand aucun n'est choisi dans les réglages : le compte principal, hors comptes clients.
    /// Jamais l'agenda d'un client, même si macOS le propose (ex. sur le Mac pro, où seul tamtam.ai est branché).
    var defaultCalendarID: String? {
        let domains = data.clients.map(\.emailDomain)
        if let id = calendar.primaryAccountCalendarID(excludingDomains: domains) { return id }
        guard let id = calendar.systemDefaultCalendarID, !calendar.isCalendar(id, onDomains: domains) else { return nil }
        return id
    }

    func calendarTitle(for clientID: UUID) -> String? {
        calendar.calendarTitle(id: calendarID(for: clientID))
    }

    // MARK: - Grille d'activité

    /// Grille façon GitHub : `weeks` colonnes (lundi en haut), niveaux 0 à 4 selon les heures du jour.
    func heatmap(weeks n: Int = 21, at date: Date) -> (columns: [[HeatCell]], months: [String], total: TimeInterval) {
        let cal = Calendar.fr
        let today = cal.startOfDay(for: date)
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let first = cal.date(byAdding: .weekOfYear, value: -(n - 1), to: weekStart)
        else { return ([], [], 0) }

        var perDay: [Date: TimeInterval] = [:]
        for s in data.sessions where s.start >= first {
            perDay[cal.startOfDay(for: s.start), default: 0] += s.duration
        }
        if let r = data.running, r.start >= first {
            perDay[cal.startOfDay(for: r.start), default: 0] += elapsedRunning(at: date)
        }

        var columns: [[HeatCell]] = []
        var months: [String] = []
        var lastMonth = -1
        var sum: TimeInterval = 0
        for w in 0..<n {
            guard let monday = cal.date(byAdding: .day, value: w * 7, to: first) else { continue }
            let month = cal.component(.month, from: monday)
            months.append(month != lastMonth ? Fmt.month(monday) : "")
            lastMonth = month
            var column: [HeatCell] = []
            for d in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: d, to: monday) else { continue }
                let seconds = perDay[day] ?? 0
                sum += seconds
                let hours = seconds / 3600
                let level = seconds < 60 ? 0 : hours <= 2 ? 1 : hours <= 4 ? 2 : hours <= 6 ? 3 : 4
                let future = day > today
                column.append(HeatCell(id: day, level: level, isToday: day == today, isFuture: future,
                                       label: Fmt.dayShort(day) + (future ? "" : " · " + Fmt.words(seconds))))
            }
            columns.append(column)
        }
        return (columns, months, sum)
    }

    // MARK: - Chrono

    func selectClient(_ id: UUID) {
        guard data.running == nil else { return }
        data.selectedClientID = id
        commit()
    }

    func toggleTimer() {
        if data.running != nil { stop() } else { start(clientID: currentClientID) }
    }

    func start(clientID: UUID) {
        guard data.running == nil else { return }
        data.running = RunningTimer(clientID: clientID, start: Date())
        data.selectedClientID = clientID
        longRunNotified = false
        idleSince = nil
        absences = []
        waitingForInput = false
        commit()
    }

    /// Arrête le chrono, enregistre la séance tout de suite (l'heure fait foi), puis ouvre le résumé.
    /// Une absence restée sans réponse est gardée : ce temps reste compté (choix de Théo, 14/11/2026).
    func stop() {
        guard let r = data.running else { return }
        data.running = nil
        absences = []
        idleSince = nil
        longRunNotified = false
        // Moins d'une minute : clic par erreur. Moins de 5 min au retour d'une absence retirée : juste
        // le temps d'arrêter le chrono. Dans les deux cas, rien n'est noté.
        let minimum: TimeInterval = r.resumedAfterAbsence ? 300 : 60
        guard let recorded = recordSession(clientID: r.clientID, start: r.start,
                                           end: Date().addingTimeInterval(-r.excludedSeconds), minimum: minimum) else {
            commit()
            return
        }
        beginReview(recorded.session.id)
        proposeExtension(for: r.clientID, shortfall: recorded.planned - recorded.session.duration)
    }

    /// Enregistre une séance terminée : son événement d'agenda, dont le bloc donne la durée, et les créneaux
    /// planifiés qu'elle remplace. Renvoie la séance et la durée planifiée qu'elle couvrait, ou nil si elle
    /// dure moins que `minimum` (rien n'est alors enregistré).
    @discardableResult
    private func recordSession(clientID: UUID, start: Date, end: Date,
                               minimum: TimeInterval) -> (session: Session, planned: TimeInterval)? {
        guard end.timeIntervalSince(start) >= minimum else { return nil }
        var s = Session(clientID: clientID, start: start, end: end)
        if data.settings.writeToCalendar, let calID = calendarID(for: clientID), let c = client(clientID) {
            s.calendarEventID = calendar.createEvent(title: eventTitle(s, c), start: s.start, end: s.end,
                                                     notes: eventNotes(s), calendarID: calID)
        }
        let planned = replacePlannedSlots(for: s)
        data.sessions.append(s)
        commit()
        return (s, planned)
    }

    func startFromEvent(_ eventID: String) {
        guard let item = calendar.todayEvents.first(where: { $0.id == eventID }) else {
            toggleTimer()
            return
        }
        start(clientID: clientFor(item))
    }

    func toggleArm(_ eventID: String) {
        if armedEventIDs.contains(eventID) { armedEventIDs.remove(eventID) } else { armedEventIDs.insert(eventID) }
    }

    /// Devine le client d'un RDV : domaine e-mail d'un participant, puis nom dans le titre.
    func clientFor(_ item: AgendaItem) -> UUID {
        for c in data.clients where !c.emailDomain.isEmpty {
            let domain = c.emailDomain.lowercased()
            if item.domains.contains(where: { $0 == domain || $0.hasSuffix("." + domain) }) { return c.id }
        }
        for c in data.clients where item.title.localizedCaseInsensitiveContains(c.name) { return c.id }
        return currentClientID
    }

    // MARK: - Absences

    /// « Retirer ce temps » : la séance est coupée à chaque absence, pour que l'agenda montre les vrais horaires.
    /// Le travail d'avant devient une séance avec son événement (bandeau « Séance à valider ») et le chrono
    /// repart au retour. Ex. chrono lancé à 09:00, absence de 12:00 à 13:30 : 09:00-12:00 est noté, le chrono
    /// continue depuis 13:30.
    func removeIdle() {
        guard let r = data.running, !absences.isEmpty else {
            absences = []
            onChange?()
            return
        }
        var segmentStart = r.start
        var legacy = r.excludedSeconds  // ancien temps retiré (0 sur les nouveaux chronos) : ôté du premier bloc
        for a in absences where a.end > segmentStart {
            let cut = max(a.start, segmentStart)
            recordSession(clientID: r.clientID, start: segmentStart, end: cut.addingTimeInterval(-legacy), minimum: 60)
            legacy = 0
            segmentStart = a.end
        }
        data.running?.start = segmentStart
        data.running?.excludedSeconds = 0
        data.running?.resumedAfterAbsence = true
        absences = []
        longRunNotified = false
        commit()
    }

    func keepIdle() {
        absences = []
        onChange?()
    }

    /// Note une absence (début et fin exacts) pendant le chrono et demande s'il faut la retirer.
    private func registerAway(from start: Date, to end: Date) {
        guard let r = data.running else { return }
        let from = max(start, r.start)
        guard end.timeIntervalSince(from) >= 60 else { return }
        absences = Store.merged(absences + [DateInterval(start: from, end: end)])
        notifier?.post(id: "idle", title: "Absent \(Fmt.words(idleAway ?? 0)) pendant le chrono",
                       body: "Retirer ce temps de la séance \(currentClientName) ?", category: Notifier.idleCategory)
    }

    /// Absences triées ; celles qui se chevauchent ou se touchent sont fusionnées.
    private static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for i in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, i.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                result.append(i)
            }
        }
        return result
    }

    /// Mac éteint ou en veille pendant le chrono : l'écart depuis le dernier signe de vie devient une absence.
    /// Si Théo était déjà inactif avant la veille, l'absence commence à sa dernière action.
    private func checkSleepGap() {
        guard let r = data.running else { return }
        let now = Date()
        if now.timeIntervalSince(r.lastSeen) > 300 {
            registerAway(from: min(idleSince ?? r.lastSeen, r.lastSeen), to: now)
            waitingForInput = true
            idleSince = nil
        }
        data.running?.lastSeen = now
    }

    /// Secondes depuis la dernière action au clavier ou à la souris.
    private func secondsSinceInput() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // MARK: - Battement (toutes les 15 s)

    func tick() {
        tickCount += 1
        let now = Date()

        if let r = data.running {
            if now.timeIntervalSince(r.lastSeen) > 300 {
                checkSleepGap()
            } else {
                let idle = secondsSinceInput()
                if waitingForInput {
                    if idle < 30 { waitingForInput = false }
                } else if let since = idleSince {
                    if idle < 30 {
                        // Retour au clavier : l'absence va de la dernière action avant de partir à la première au retour.
                        registerAway(from: since, to: now.addingTimeInterval(-idle))
                        idleSince = nil
                    }
                } else if idle >= Double(data.settings.idleMinutes * 60) {
                    idleSince = now.addingTimeInterval(-idle)
                }
                data.running?.lastSeen = now
            }
            if !longRunNotified, elapsedRunning(at: now) >= Double(data.settings.longRunHours * 3600) {
                longRunNotified = true
                notifier?.post(id: "long-run", title: "Le chrono \(currentClientName) tourne depuis \(data.settings.longRunHours) h",
                               body: "Toujours dessus ? Sinon, arrête-le.", category: Notifier.longRunCategory)
            }
            if tickCount % 4 == 0 { save() }
        }

        if tickCount % 4 == 0 {
            calendar.reload()
            syncFromCalendar()
        }
        checkEvents(now)
        onChange?()
    }

    /// Un RDV commence : chrono lancé s'il était armé, sinon proposition par notification.
    private func checkEvents(_ now: Date) {
        for item in calendar.todayEvents where !notifiedEventIDs.contains(item.id) {
            let delta = item.start.timeIntervalSince(now)
            guard delta <= 30, delta >= -120 else { continue }
            notifiedEventIDs.insert(item.id)
            let clientID = clientFor(item)
            let name = client(clientID)?.name ?? ""
            if armedEventIDs.contains(item.id) {
                if data.running == nil {
                    start(clientID: clientID)
                    notifier?.post(id: "armed-\(item.id)", title: "Chrono \(name) lancé", body: item.title)
                }
            } else if data.running == nil {
                notifier?.post(id: "event-\(item.id)", title: item.title, body: "Ça commence. Lancer le chrono \(name) ?",
                               category: Notifier.eventCategory, userInfo: ["eventID": item.id])
            }
        }
    }

    // MARK: - Fin de séance

    func beginReview(_ id: UUID) {
        guard let s = session(id) else { return }
        let canWrite = calendarID(for: s.clientID) != nil
        draft = ReviewDraft(sessionID: id, addToCalendar: s.calendarEventID != nil || (canWrite && data.settings.writeToCalendar))
        route = .review(id)
        generateSummary(for: id)
    }

    func generateSummary(for id: UUID) {
        guard let s = session(id), let c = client(s.clientID) else { return }
        draft?.loading = true
        draft?.error = nil
        let previous = previousObjectives(for: c.id)
        let claudePath = data.settings.claudePath
        Task {
            let result = await summarizer.summarize(start: s.start, end: s.end, clientName: c.name,
                                                    previous: previous, claudePath: claudePath)
            guard draft?.sessionID == id else {
                // Séance enregistrée pendant que Claude rédigeait : le résumé n'est pas perdu.
                if applyWhenReady.remove(id) != nil, case .success(let r) = result { applySummary(r, to: id) }
                return
            }
            switch result {
            case .success(let r):
                draft?.title = r.title
                draft?.text = r.text
                draft?.objectives = r.objectives
                draft?.sourceCount = r.sourceCount
                if let a = r.firstAt, let b = r.lastAt { draft?.sourceRange = "\(Fmt.time(a)) → \(Fmt.time(b))" }
            case .failure(let f):
                draft?.error = f.message
            }
            draft?.loading = false
        }
    }

    /// Objectifs encore ouverts d'un client, transmis à Claude pour garder les mêmes titres.
    private func previousObjectives(for clientID: UUID) -> [PreviousObjective] {
        data.objectives
            .filter { $0.clientID == clientID && $0.status != .termine }
            .map { PreviousObjective(title: $0.title, status: $0.status, streak: $0.blockedStreak) }
    }

    /// Résumé d'une séance passée rédigé en arrière-plan, sans écran de validation (séance ajoutée à la main).
    /// Sans conversation Claude Code sur le créneau, la séance reste telle quelle.
    private func autoSummarize(_ id: UUID) {
        guard let s = session(id), let c = client(s.clientID), !s.imported, s.note.isEmpty, s.end <= Date(),
              !autoSummarizing.contains(id) else { return }
        autoSummarizing.insert(id)
        let previous = previousObjectives(for: c.id)
        let claudePath = data.settings.claudePath
        Task {
            let result = await summarizer.summarize(start: s.start, end: s.end, clientName: c.name,
                                                    previous: previous, claudePath: claudePath)
            autoSummarizing.remove(id)
            if case .success(let r) = result { applySummary(r, to: id) }
        }
    }

    /// Écrit un résumé dans une séance déjà enregistrée, sans écraser ce que Théo a écrit lui-même.
    private func applySummary(_ r: SummaryResult, to id: UUID) {
        guard let i = data.sessions.firstIndex(where: { $0.id == id }), !data.sessions[i].imported,
              data.sessions[i].note.isEmpty, !r.text.isEmpty else { return }
        var s = data.sessions[i]
        if s.title.isEmpty { s.title = r.title }
        s.note = r.text
        s.objectives = r.objectives
        s.claudeSessionCount = r.sourceCount
        for o in r.objectives { updateRecord(o, clientID: s.clientID, at: s.end) }
        syncCalendar(&s, wanted: s.calendarEventID != nil)
        data.sessions[i] = s
        commit()
    }

    var draftTitle: String {
        get { draft?.title ?? "" }
        set { draft?.title = newValue }
    }

    var draftText: String {
        get { draft?.text ?? "" }
        set { draft?.text = newValue }
    }

    var draftAddToCalendar: Bool {
        get { draft?.addToCalendar ?? false }
        set { draft?.addToCalendar = newValue }
    }

    /// Nombre de séances bloquées d'affilée si l'on enregistre ce brouillon.
    func prospectiveStreak(_ o: ObjectiveMention, clientID: UUID) -> Int {
        guard o.status == .bloque else { return 0 }
        let previous = record(o.title, clientID: clientID)?.blockedStreak ?? 0
        return previous + 1
    }

    func saveReview() { finishReview(keepNote: true) }
    func skipReview() { finishReview(keepNote: false) }

    private func finishReview(keepNote: Bool) {
        guard let d = draft, let index = data.sessions.firstIndex(where: { $0.id == d.sessionID }) else {
            draft = nil
            route = .main
            return
        }
        var s = data.sessions[index]
        if keepNote {
            s.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
            s.note = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
            s.objectives = d.objectives
            s.claudeSessionCount = d.sourceCount
            for o in d.objectives { updateRecord(o, clientID: s.clientID, at: s.end) }
        }
        s.reviewed = true
        if keepNote && d.loading { applyWhenReady.insert(s.id) }
        syncCalendar(&s, wanted: d.addToCalendar)
        data.sessions[index] = s
        draft = nil
        route = .main
        commit()
    }

    private func record(_ title: String, clientID: UUID) -> ObjectiveRecord? {
        data.objectives.first { $0.clientID == clientID && $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    private func updateRecord(_ o: ObjectiveMention, clientID: UUID, at date: Date) {
        if let i = data.objectives.firstIndex(where: {
            $0.clientID == clientID && $0.title.localizedCaseInsensitiveCompare(o.title) == .orderedSame
        }) {
            guard data.objectives[i].lastSeen <= date else { return }
            data.objectives[i].status = o.status
            data.objectives[i].detail = o.detail
            data.objectives[i].blockedStreak = o.status == .bloque ? data.objectives[i].blockedStreak + 1 : 0
            data.objectives[i].lastSeen = date
        } else {
            data.objectives.append(ObjectiveRecord(title: o.title, clientID: clientID, status: o.status, detail: o.detail,
                                                   blockedStreak: o.status == .bloque ? 1 : 0, lastSeen: date))
        }
    }

    // MARK: - Agenda

    /// Met l'événement de la séance en accord avec le choix (présent ou non, titre et notes à jour).
    private func syncCalendar(_ s: inout Session, wanted: Bool) {
        guard let c = client(s.clientID) else { return }
        if wanted {
            if let id = s.calendarEventID {
                calendar.updateEvent(id: id, title: eventTitle(s, c), start: s.start, end: s.end, notes: eventNotes(s))
            } else if let calID = calendarID(for: s.clientID) {
                s.calendarEventID = calendar.createEvent(title: eventTitle(s, c), start: s.start, end: s.end,
                                                         notes: eventNotes(s), calendarID: calID)
            }
        } else if let id = s.calendarEventID {
            calendar.deleteEvent(id: id)
            s.calendarEventID = nil
        }
    }

    /// Titre de l'événement : le titre de la séance ; à défaut, le nom du client.
    private func eventTitle(_ s: Session, _ c: Client) -> String {
        let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "\(c.name) · séance" : title
    }

    private func eventNotes(_ s: Session) -> String {
        var parts: [String] = []
        if !s.note.isEmpty { parts.append(s.note) }
        if !s.objectives.isEmpty {
            parts.append("Objectifs :\n" + s.objectives.map { "- \($0.title) (\($0.status.label))" }.joined(separator: "\n"))
        }
        parts.append("\(client(s.clientID)?.name ?? "") · \(Fmt.words(s.duration)) · \(CalendarService.marker)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Synchronisation entre Mac (par l'agenda)

    /// Nombre de jours relus en arrière dans l'agenda.
    private static let syncWindowDays = 180

    /// L'agenda fait foi (choix de Théo, 14/11/2026). Relu chaque minute :
    /// - séances de ce Mac : elles suivent leur événement (déplacé, raccourci, allongé, renommé, supprimé),
    ///   voir `followOwnEvents` ;
    /// - séances d'un autre Mac : tout événement « noté avec Tiroflan » d'un agenda client que ce Mac ne
    ///   connaît pas devient une séance miroir, qui suit son événement elle aussi.
    func syncFromCalendar() {
        let now = Date()
        guard let from = Calendar.fr.date(byAdding: .day, value: -Store.syncWindowDays, to: now),
              let to = Calendar.fr.date(byAdding: .day, value: 1, to: now) else { return }
        let calendarIDs = Set(data.clients.compactMap { calendarID(for: $0.id) })
        guard let events = calendar.loggedEvents(in: calendarIDs, from: from, to: to) else { return }

        var changed = false
        var seen: Set<String> = []
        for e in events {
            seen.insert(e.id)
            let parsed = Store.parseNotes(e.notes)
            guard let clientID = clientForLogged(e, name: parsed.clientName) else { continue }

            if let i = data.sessions.firstIndex(where: { $0.calendarEventID == e.id }) {
                // Déjà connue : un miroir se met à jour ici, une séance de ce Mac dans `followOwnEvents`.
                guard data.sessions[i].imported else { continue }
                let mirror = mirrorSession(e, parsed, clientID: clientID, keeping: data.sessions[i])
                if mirror != data.sessions[i] {
                    data.sessions[i] = mirror
                    changed = true
                }
            } else if let i = data.sessions.firstIndex(where: {
                $0.clientID == clientID
                    && (abs($0.start.timeIntervalSince(e.start)) < 60 || abs($0.end.timeIntervalSince(e.end)) < 60)
                    && !($0.calendarEventID.map(calendar.eventExists(id:)) ?? false)
            }) {
                // Même client, même début ou même fin, et l'événement d'origine de la séance n'existe plus :
                // c'est le même bloc dont l'identifiant a changé (compte retiré puis rajouté, bloc retouché).
                // On le rattache ; s'il a bougé, la séance suit juste après.
                data.sessions[i].calendarEventID = e.id
                missingPasses[data.sessions[i].id] = nil
                changed = true
            } else if let j = data.trash.firstIndex(where: { $0.calendarEventID == e.id }) {
                // Événement revenu après une disparition passagère (synchro Google) : la séance revient.
                data.sessions.append(data.trash.remove(at: j))
                changed = true
            } else {
                data.sessions.append(mirrorSession(e, parsed, clientID: clientID, keeping: nil))
                changed = true
            }
        }

        if followOwnEvents(from: from, to: to) { changed = true }
        if alignLegacyExclusions() { changed = true }

        // Miroir dont l'événement a disparu : la séance a été supprimée sur l'autre Mac.
        let before = data.sessions.count
        data.sessions.removeAll { s in
            guard s.imported, let id = s.calendarEventID, !seen.contains(id), s.start >= from, s.start <= to else { return false }
            return !calendar.eventExists(id: id)
        }
        if data.sessions.count != before { changed = true }
        if changed { commit() }
    }

    /// Séances notées sur ce Mac : leur événement fait foi.
    /// - Déplacé, raccourci ou allongé (d'une minute ou plus) : la séance prend ses horaires, et la ligne
    ///   « Tamtam · 2 h 36 · noté avec Tiroflan » de la description est remise à la durée du bloc.
    /// - Renommé : la séance prend son titre.
    /// - Supprimé : la séance part dans `trash` (plus comptée, gardée dans data.json). Garde-fous : l'agenda
    ///   du client doit être lisible, l'absence doit se confirmer à deux relectures d'affilée (une minute),
    ///   et plus de 3 disparitions d'un coup (compte débranché, synchro Google en cours) ne suppriment rien.
    private func followOwnEvents(from: Date, to: Date) -> Bool {
        guard calendar.authorized else { return false }
        var changed = false
        var stillMissing: [UUID: Int] = [:]
        var gone: [UUID] = []

        for i in data.sessions.indices {
            let s = data.sessions[i]
            guard !s.imported, let id = s.calendarEventID, s.start >= from, s.start <= to, let c = client(s.clientID) else { continue }
            guard let e = calendar.loggedEvent(id: id) else {
                // Introuvable : on ne conclut rien si l'agenda du client n'est pas lisible.
                guard let calID = calendarID(for: s.clientID), calendar.calendarExists(id: calID) else { continue }
                let passes = (missingPasses[s.id] ?? 0) + 1
                stillMissing[s.id] = passes
                if passes >= 2 { gone.append(s.id) }
                continue
            }

            var updated = s
            let moved = abs(e.start.timeIntervalSince(s.start)) >= 60 || abs(e.end.timeIntervalSince(s.end)) >= 60
            if moved {
                updated.start = e.start
                updated.end = e.end
                updated.excludedSeconds = 0
            }
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, title != eventTitle(s, c) { updated.title = title }
            if updated != s {
                data.sessions[i] = updated
                changed = true
            }
            // Ligne de durée (relue par l'autre Mac) : la durée du bloc, sauf ancienne séance pas encore alignée.
            if updated.excludedSeconds == 0, let notes = Store.replacingDuration(in: e.notes, with: Fmt.words(updated.duration)),
               notes != e.notes {
                calendar.setNotes(id: e.id, notes: notes)
            }
        }
        missingPasses = stillMissing

        guard !gone.isEmpty else {
            missingAlerted = false
            return changed
        }
        if gone.count > 3 {
            if !missingAlerted {
                missingAlerted = true
                notifier?.post(id: "missing-events", title: "\(gone.count) séances introuvables dans l'agenda",
                               body: "Rien n'est supprimé dans Tiroflan. Vérifie le compte Google dans Calendrier ; "
                                   + "si c'est voulu, supprime ces séances depuis l'historique.")
            }
            return changed
        }
        for id in gone {
            guard let i = data.sessions.firstIndex(where: { $0.id == id }) else { continue }
            let s = data.sessions.remove(at: i)
            data.trash.append(s)
            missingPasses[id] = nil
            NSLog("Tiroflan : événement supprimé dans l'agenda, séance \(s.id) (\(s.start) → \(s.end)) mise de côté")
        }
        return true
    }

    /// Anciennes séances (avant le 14/11/2026) dont du temps a été retiré sans toucher l'agenda : leur
    /// événement finit plus tôt d'autant, pour que l'agenda montre les heures comptées. L'absence n'étant
    /// pas datée, c'est la fin du bloc qui bouge. Une fois aligné, le temps retiré repasse à 0.
    /// Validé par Théo le 14/11/2026 (7 séances, 8 h 59 au total sur ce Mac).
    private func alignLegacyExclusions() -> Bool {
        var changed = false
        for i in data.sessions.indices {
            let s = data.sessions[i]
            guard !s.imported, s.excludedSeconds >= 1, let id = s.calendarEventID,
                  let e = calendar.loggedEvent(id: id),
                  abs(e.start.timeIntervalSince(s.start)) < 60, abs(e.end.timeIntervalSince(s.end)) < 60 else { continue }
            let newEnd = s.end.addingTimeInterval(-s.excludedSeconds)
            guard newEnd > s.start, calendar.setEnd(id: id, to: newEnd) else { continue }
            data.sessions[i].end = newEnd
            data.sessions[i].excludedSeconds = 0
            changed = true
            NSLog("Tiroflan : bloc \(id) raccourci de \(Int(s.excludedSeconds / 60)) min (temps retiré avant le 14/11)")
        }
        return changed
    }

    /// Remet `words` comme durée dans la ligne « Tamtam · 2 h 36 · noté avec Tiroflan » d'une description.
    /// Seule la durée change : le reste de la description, même retouché dans Google Agenda, est gardé.
    /// nil si la ligne est introuvable.
    static func replacingDuration(in notes: String, with words: String) -> String? {
        let marker = NSRegularExpression.escapedPattern(for: CalendarService.marker)
        guard let regex = try? NSRegularExpression(pattern: " · ([^·\\n<>]+?) · " + marker) else { return nil }
        let all = NSRange(notes.startIndex..., in: notes)
        guard let match = regex.matches(in: notes, range: all).last,
              let range = Range(match.range(at: 1), in: notes) else { return nil }
        var result = notes
        result.replaceSubrange(range, with: words)
        return result
    }

    /// Client d'un événement Tiroflan : le nom écrit dans sa dernière ligne, sinon l'agenda où il se trouve.
    private func clientForLogged(_ e: CalendarService.LoggedEvent, name: String?) -> UUID? {
        if let name, let c = data.clients.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return c.id
        }
        return data.clients.first { calendarID(for: $0.id) == e.calendarID }?.id
    }

    /// Séance miroir lue dans un événement ; la durée écrite par l'autre Mac redonne le temps d'absence retiré.
    private func mirrorSession(_ e: CalendarService.LoggedEvent, _ parsed: ParsedNotes, clientID: UUID, keeping old: Session?) -> Session {
        let span = e.end.timeIntervalSince(e.start)
        let excluded = parsed.minutes.map { max(0, span - Double($0 * 60)) } ?? 0
        return Session(id: old?.id ?? UUID(), clientID: clientID, start: e.start, end: e.end, excludedSeconds: excluded,
                       title: e.title, note: parsed.note, objectives: parsed.objectives, calendarEventID: e.id,
                       reviewed: true, claudeSessionCount: old?.claudeSessionCount ?? 0, imported: true)
    }

    /// Ce que contient la description d'un événement Tiroflan.
    struct ParsedNotes {
        var note: String
        var objectives: [ObjectiveMention]
        var clientName: String?
        var minutes: Int?
    }

    /// Relit une description écrite par `eventNotes` : résumé, puis « Objectifs : » avec « - titre (statut) »,
    /// puis la dernière ligne « Tamtam · 2 h 36 · noté avec Tiroflan ».
    static func parseNotes(_ notes: String) -> ParsedNotes {
        var parts = notes.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        var result = ParsedNotes(note: "", objectives: [], clientName: nil, minutes: nil)

        if let i = parts.lastIndex(where: { $0.contains(CalendarService.marker) }) {
            let fields = parts[i].components(separatedBy: " · ")
            if fields.count >= 3 {
                result.clientName = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                result.minutes = parseMinutes(fields[1])
            }
            parts.remove(at: i)
        }
        if let i = parts.lastIndex(where: { $0.hasPrefix("Objectifs :") }) {
            result.objectives = parts[i].split(separator: "\n").dropFirst().compactMap { line in
                var text = line.trimmingCharacters(in: .whitespaces)
                guard text.hasPrefix("- ") else { return nil }
                text.removeFirst(2)
                guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else {
                    return ObjectiveMention(title: text, status: .avance, detail: "")
                }
                let title = text[..<open].trimmingCharacters(in: .whitespaces)
                let status = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
                return ObjectiveMention(title: title, status: ObjectiveStatus(loose: status), detail: "")
            }
            parts.remove(at: i)
        }
        result.note = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    /// Inverse de `Fmt.words` : « 45 min », « 2 h », « 2 h 36 » donnent 45, 120 et 156 minutes.
    static func parseMinutes(_ text: String) -> Int? {
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = numbers.first else { return nil }
        if text.contains("h") { return first * 60 + (numbers.count > 1 ? numbers[1] : 0) }
        return text.contains("min") ? first : nil
    }

    func setWriteCalendar(_ id: String?) {
        data.settings.writeCalendarID = id
        commit()
    }

    func setWriteToCalendar(_ on: Bool) {
        data.settings.writeToCalendar = on
        commit()
    }

    /// Après l'accès à l'agenda : relit les agendas pour que le choix automatique par client fonctionne.
    func adoptDefaultCalendarIfNeeded() {
        calendar.reload()
        onChange?()
    }

    func setClientCalendar(_ id: UUID, _ calendarID: String?) {
        guard let i = data.clients.firstIndex(where: { $0.id == id }) else { return }
        data.clients[i].calendarID = calendarID
        commit()
    }

    // MARK: - Séances manuelles

    func upsertSession(id: UUID?, clientID: UUID, start: Date, end: Date, title: String, note: String) {
        // Un miroir se modifie sur le Mac où la séance a été notée.
        if let id, session(id)?.imported == true { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id, let i = data.sessions.firstIndex(where: { $0.id == id }) {
            var s = data.sessions[i]
            let moved = s.start != start || s.end != end
            s.clientID = clientID
            s.start = start
            s.end = end
            // Horaires corrigés à la main : le bloc d'agenda donne la durée, plus de temps retiré caché.
            if moved { s.excludedSeconds = 0 }
            s.title = cleanTitle
            s.note = trimmed
            s.reviewed = true
            syncCalendar(&s, wanted: s.calendarEventID != nil)
            data.sessions[i] = s
            commit()
            // Horaires corrigés et toujours pas de note : on retente le résumé sur le nouveau créneau.
            if moved && trimmed.isEmpty { autoSummarize(s.id) }
        } else {
            var s = Session(clientID: clientID, start: start, end: end, title: cleanTitle, note: trimmed, reviewed: true)
            syncCalendar(&s, wanted: data.settings.writeToCalendar)
            let planned = replacePlannedSlots(for: s)
            data.sessions.append(s)
            commit()
            if trimmed.isEmpty { autoSummarize(s.id) }
            proposeExtension(for: s.clientID, shortfall: planned - s.duration)
        }
    }

    func deleteSession(_ id: UUID) {
        guard let i = data.sessions.firstIndex(where: { $0.id == id }), !data.sessions[i].imported else { return }
        if let eventID = data.sessions[i].calendarEventID { calendar.deleteEvent(id: eventID) }
        data.sessions.remove(at: i)
        commit()
    }

    // MARK: - Créneaux planifiés et objectif de la semaine

    /// La séance réelle remplace la partie des créneaux planifiés qu'elle chevauche (agenda du client, titre
    /// au nom du client, sans invités) : tout ce qui précède la fin de la séance est retiré, la suite du
    /// créneau reste planifiée (ex. séance 08:00-08:30 dans un créneau 08:00-12:00 : il reste 08:30-12:00).
    /// Renvoie la durée planifiée jusqu'à la fin de la séance, pour savoir si la séance a été plus courte.
    /// Rien n'est touché si la séance n'est pas elle-même dans l'agenda.
    @discardableResult
    private func replacePlannedSlots(for s: Session) -> TimeInterval {
        guard s.calendarEventID != nil, let c = client(s.clientID), let calID = calendarID(for: s.clientID) else { return 0 }
        let slots = calendar.plannedSlots(calendarID: calID, clientName: c.name, from: s.start, to: s.end)
        var due: TimeInterval = 0
        for slot in slots {
            due += min(slot.end, s.end).timeIntervalSince(slot.start)
            // Suite d'au moins 15 min : on la garde. En dessous, on retire tout pour ne pas laisser de miettes.
            if slot.end.timeIntervalSince(s.end) >= 15 * 60 {
                _ = calendar.setStart(id: slot.id, to: s.end)
            } else {
                calendar.deleteEvent(id: slot.id)
            }
        }
        return due
    }

    /// Créneaux planifiés d'un client qui restent dans la semaine après `date`.
    private func upcomingSlots(for clientID: UUID, in week: DateInterval, after date: Date) -> [PlannedSlot] {
        guard let c = client(clientID), let calID = calendarID(for: clientID), date < week.end else { return [] }
        return calendar.plannedSlots(calendarID: calID, clientName: c.name, from: max(date, week.start), to: week.end)
    }

    /// Décompte de la semaine : fait, planifié (partie à venir), objectif. nil si le client n'a pas d'objectif.
    func weekBalance(for clientID: UUID, at date: Date) -> WeekBalance? {
        guard let hours = client(clientID)?.weeklyHours, hours > 0,
              let week = Calendar.fr.dateInterval(of: .weekOfYear, for: date) else { return nil }
        var done = data.sessions.filter { $0.clientID == clientID && week.contains($0.start) }.reduce(0) { $0 + $1.duration }
        if let r = data.running, r.clientID == clientID, week.contains(r.start) { done += elapsedRunning(at: date) }
        let planned = upcomingSlots(for: clientID, in: week, after: date)
            .reduce(0) { $0 + $1.end.timeIntervalSince(max($1.start, date)) }
        return WeekBalance(target: hours * 3600, done: done, planned: planned)
    }

    /// Séance plus courte que le créneau prévu : propose d'allonger le prochain créneau planifié de la semaine
    /// qui peut l'être sans chevaucher aucun événement. Le manque est plafonné par ce qu'il reste à caser
    /// dans la semaine (objectif − fait − planifié), pour ne rien proposer si la semaine est déjà couverte.
    private func proposeExtension(for clientID: UUID, shortfall: TimeInterval) {
        let now = Date()
        var missing = shortfall
        if let balance = weekBalance(for: clientID, at: now) { missing = min(missing, balance.missing) }
        guard missing >= 15 * 60, let c = client(clientID), let week = Calendar.fr.dateInterval(of: .weekOfYear, for: now) else { return }
        missing = (missing / 300).rounded(.up) * 300  // arrondi aux 5 minutes supérieures

        for slot in upcomingSlots(for: clientID, in: week, after: now) where slot.start > now {
            let newEnd = slot.end.addingTimeInterval(missing)
            guard Calendar.fr.isDate(newEnd.addingTimeInterval(-1), inSameDayAs: slot.start),
                  calendar.isFree(from: slot.end, to: newEnd, excluding: slot.id) else { continue }
            extensionProposal = ExtensionProposal(clientID: clientID, slot: slot, newEnd: newEnd, missing: missing)
            notifier?.post(id: "extend", title: "Il te manque \(Fmt.words(missing)) pour \(c.name) cette semaine",
                           body: "Allonger « \(slot.title) » \(Fmt.dayShort(slot.start)) jusqu'à \(Fmt.time(newEnd)) ?",
                           category: Notifier.extendCategory)
            onChange?()
            return
        }
        notifier?.post(id: "extend", title: "Il te manque \(Fmt.words(missing)) pour \(c.name) cette semaine",
                       body: "Aucun créneau planifié de la semaine ne peut être allongé sans chevauchement.")
    }

    func acceptExtension() {
        guard let p = extensionProposal else { return }
        extensionProposal = nil
        if !calendar.setEnd(id: p.slot.id, to: p.newEnd) {
            notifier?.post(id: "extend", title: "Allongement impossible", body: "Le créneau a été déplacé ou supprimé entre-temps.")
        }
        calendar.reload()
        onChange?()
    }

    func dismissExtension() {
        extensionProposal = nil
        onChange?()
    }

    // MARK: - Clients et réglages

    func addClient() {
        let c = Client(name: "Nouveau client")
        data.clients.append(c)
        commit()
    }

    func updateClient(_ id: UUID, name: String? = nil, domain: String? = nil) {
        guard let i = data.clients.firstIndex(where: { $0.id == id }) else { return }
        if let name { data.clients[i].name = name }
        if let domain { data.clients[i].emailDomain = domain.trimmingCharacters(in: .whitespaces).lowercased() }
        commit()
    }

    /// Objectif d'heures par semaine ; 0 ou moins le retire.
    func setWeeklyHours(_ id: UUID, _ hours: Double) {
        guard let i = data.clients.firstIndex(where: { $0.id == id }) else { return }
        data.clients[i].weeklyHours = hours > 0 ? min(60, hours) : nil
        commit()
    }

    func canRemoveClient(_ id: UUID) -> Bool {
        data.clients.count > 1 && data.running?.clientID != id && !data.sessions.contains { $0.clientID == id }
    }

    func removeClient(_ id: UUID) {
        guard canRemoveClient(id) else { return }
        data.clients.removeAll { $0.id == id }
        if data.selectedClientID == id { data.selectedClientID = data.clients.first?.id }
        commit()
    }

    func setIdleMinutes(_ m: Int) {
        data.settings.idleMinutes = min(60, max(5, m))
        commit()
    }

    func setLongRunHours(_ h: Int) {
        data.settings.longRunHours = min(12, max(1, h))
        commit()
    }

    func setClaudePath(_ path: String) {
        data.settings.claudePath = path.isEmpty ? nil : path
        commit()
    }

    /// Panneau refermé : on revient à l'accueil, sauf si un résumé est en cours de validation.
    func panelHidden() {
        if case .review = route { return }
        route = .main
    }

    // MARK: - Sauvegarde

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Écriture atomique ; copie de sécurité du fichier précédent au premier enregistrement de chaque lancement.
    private func save() {
        let fm = FileManager.default
        if !backedUp, fm.fileExists(atPath: fileURL.path) {
            let backup = supportDir.appendingPathComponent("data.backup.json")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: fileURL, to: backup)
            backedUp = true
        }
        do {
            try Store.encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Tiroflan : échec de la sauvegarde, \(error)")
        }
    }

    private func commit() {
        calendar.excludedEventIDs = Set(data.sessions.compactMap(\.calendarEventID))
        save()
        onChange?()
    }
}
