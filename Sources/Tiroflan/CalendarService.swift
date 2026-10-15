import EventKit
import Foundation

/// Accès à l'agenda via le Calendrier de macOS (EventKit).
/// Le compte Google étant déjà branché sur Calendrier, écrire ici écrit dans Google Agenda.
@MainActor
final class CalendarService: ObservableObject {
    let store = EKEventStore()
    @Published private(set) var authorized = false
    @Published private(set) var todayEvents: [AgendaItem] = []
    @Published private(set) var writableCalendars: [EKCalendar] = []

    /// Événements écrits par Tiroflan : jamais affichés comme rendez-vous du jour.
    var excludedEventIDs: Set<String> = [] {
        didSet { if excludedEventIDs != oldValue { reload() } }
    }

    /// Repère glissé dans la description des séances, pour les reconnaître même sans identifiant.
    static let marker = "noté avec Tiroflan"

    init() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    var notDetermined: Bool { EKEventStore.authorizationStatus(for: .event) == .notDetermined }

    /// Demande l'accès complet à l'agenda (fenêtre système au premier appel).
    func requestAccess() async {
        do {
            authorized = try await store.requestFullAccessToEvents()
        } catch {
            authorized = false
        }
        reload()
    }

    /// Relit les agendas modifiables et les rendez-vous du jour.
    func reload() {
        guard authorized else {
            todayEvents = []
            writableCalendars = []
            return
        }
        let all = store.calendars(for: .event)
        writableCalendars = all.filter(\.allowsContentModifications).sorted { $0.title < $1.title }

        let cal = Calendar.fr
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let readable = all.filter { $0.type != .birthday && $0.type != .subscription }
        guard !readable.isEmpty else {
            todayEvents = []
            return
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: readable)
        todayEvents = store.events(matching: predicate)
            .filter { event in
                !event.isAllDay
                    && !excludedEventIDs.contains(event.eventIdentifier ?? "")
                    && !(event.notes?.contains(Self.marker) ?? false)
            }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let domains = (event.attendees ?? []).compactMap { participant -> String? in
                    let address = participant.url.absoluteString.lowercased()
                    guard let at = address.lastIndex(of: "@") else { return nil }
                    return String(address[address.index(after: at)...])
                }
                return AgendaItem(id: event.calendarItemIdentifier + "@" + String(event.startDate.timeIntervalSince1970),
                                  title: event.title ?? "Sans titre",
                                  start: event.startDate, end: event.endDate, domains: domains)
            }
    }

    func calendarTitle(id: String?) -> String? {
        guard let id else { return nil }
        return store.calendar(withIdentifier: id)?.title
    }

    /// Agenda modifiable qui porte exactement ce nom (ex. un agenda « Tamtam » pour le client Tamtam).
    func calendarID(named name: String) -> String? {
        writableCalendars.first { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }?.calendarIdentifier
    }

    /// Agenda modifiable dont l'adresse est sur ce domaine (ex. « theo.david@tamtam.ai » pour tamtam.ai).
    func calendarID(forDomain domain: String) -> String? {
        let domain = domain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty else { return nil }
        return writableCalendars.first { $0.title.lowercased().hasSuffix("@" + domain) }?.calendarIdentifier
    }

    /// Agenda principal d'un compte (Google) : son titre est l'adresse du compte, comme le compte lui-même.
    /// Écarte les agendas partagés par d'autres (ex. celui de Clémentine), qui portent une autre adresse,
    /// et les comptes des clients (ex. theo.david@tamtam.ai), pour ne jamais y écrire une séance perso.
    func primaryAccountCalendarID(excludingDomains domains: [String]) -> String? {
        let suffixes = Self.suffixes(domains)
        return writableCalendars.first { cal in
            cal.title.contains("@") && cal.title.caseInsensitiveCompare(cal.source.title) == .orderedSame
                && !suffixes.contains { cal.title.lowercased().hasSuffix($0) }
        }?.calendarIdentifier
    }

    /// Vrai si l'agenda est celui d'un de ces domaines (ex. theo.david@tamtam.ai pour tamtam.ai).
    func isCalendar(_ id: String, onDomains domains: [String]) -> Bool {
        guard let title = store.calendar(withIdentifier: id)?.title.lowercased() else { return false }
        return Self.suffixes(domains).contains { title.hasSuffix($0) }
    }

    /// « tamtam.ai » devient « @tamtam.ai » ; les domaines vides sont ignorés.
    private static func suffixes(_ domains: [String]) -> [String] {
        domains.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            .map { "@" + $0 }
    }

    /// Agenda par défaut de macOS (peut varier : « dernier agenda utilisé »).
    var systemDefaultCalendarID: String? {
        guard authorized else { return nil }
        return store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// Événement de séance écrit par un Tiroflan, celui de ce Mac ou celui d'un autre.
    struct LoggedEvent {
        let id: String
        let calendarID: String
        let title: String
        let notes: String
        let start: Date
        let end: Date
    }

    /// Séances Tiroflan (repère « noté avec Tiroflan » dans la description) de ces agendas sur la période.
    /// Renvoie nil si l'agenda n'est pas lisible : la synchronisation ne doit alors rien conclure.
    func loggedEvents(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [LoggedEvent]? {
        guard authorized else { return nil }
        let calendars = calendarIDs.compactMap { store.calendar(withIdentifier: $0) }
        guard !calendars.isEmpty else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap { e in
            guard !e.isAllDay, let id = e.eventIdentifier, let notes = e.notes, notes.contains(Self.marker) else { return nil }
            return LoggedEvent(id: id, calendarID: e.calendar.calendarIdentifier, title: e.title ?? "",
                               notes: notes, start: e.startDate, end: e.endDate)
        }
    }

    /// Vrai si l'événement existe encore (où qu'il soit), pour ne jamais supprimer un miroir par erreur.
    func eventExists(id: String) -> Bool {
        store.event(withIdentifier: id) != nil
    }

    /// Crée l'événement d'une séance ; renvoie son identifiant.
    func createEvent(title: String, start: Date, end: Date, notes: String, calendarID: String) -> String? {
        guard authorized, let calendar = store.calendar(withIdentifier: calendarID) else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            NSLog("Tiroflan : création d'événement impossible, \(error)")
            return nil
        }
    }

    func updateEvent(id: String, title: String, start: Date, end: Date, notes: String) {
        guard authorized, let event = store.event(withIdentifier: id) else { return }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        try? store.save(event, span: .thisEvent, commit: true)
    }

    func deleteEvent(id: String) {
        guard authorized, let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Créneaux planifiés

    /// Créneaux de travail planifiés pour un client dans cet agenda, qui touchent la période.
    /// Un créneau planifié : titre qui commence par le nom du client (« tamtam », « Tamtam 1st day »),
    /// sans aucun invité, pas écrit par Tiroflan. Un vrai rendez-vous (avec invités) n'en est jamais un.
    func plannedSlots(calendarID: String, clientName: String, from start: Date, to end: Date) -> [PlannedSlot] {
        let name = clientName.trimmingCharacters(in: .whitespaces)
        guard authorized, !name.isEmpty, let cal = store.calendar(withIdentifier: calendarID) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
        return store.events(matching: predicate)
            .filter { e in
                let title = (e.title ?? "").trimmingCharacters(in: .whitespaces)
                return !e.isAllDay
                    && (e.attendees ?? []).isEmpty
                    && !(e.notes?.contains(Self.marker) ?? false)
                    && title.range(of: name, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
                    && e.endDate > start && e.startDate < end
            }
            .compactMap { e in
                e.eventIdentifier.map { PlannedSlot(id: $0, title: e.title ?? "", start: e.startDate, end: e.endDate) }
            }
            .sorted { $0.start < $1.start }
    }

    /// Vrai si aucun événement (tous agendas lisibles, agenda perso partagé compris) n'occupe la période,
    /// hors événements à la journée et hors l'événement `excluding` (le créneau qu'on allonge).
    func isFree(from start: Date, to end: Date, excluding: String?) -> Bool {
        guard authorized, end > start else { return false }
        let readable = store.calendars(for: .event).filter { $0.type != .birthday && $0.type != .subscription }
        guard !readable.isEmpty else { return true }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: readable)
        return !store.events(matching: predicate).contains { e in
            !e.isAllDay && e.eventIdentifier != excluding && e.endDate > start && e.startDate < end
                && e.availability != .free
        }
    }

    /// Avance le début d'un événement (la suite d'un créneau après une séance) ; renvoie faux s'il n'existe plus
    /// ou n'a pas pu être enregistré.
    func setStart(id: String, to start: Date) -> Bool {
        guard authorized, let event = store.event(withIdentifier: id), start < event.endDate else { return false }
        event.startDate = start
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            NSLog("Tiroflan : raccourcissement impossible, \(error)")
            return false
        }
    }

    /// Repousse la fin d'un événement ; renvoie faux s'il n'existe plus ou n'a pas pu être enregistré.
    func setEnd(id: String, to end: Date) -> Bool {
        guard authorized, let event = store.event(withIdentifier: id), end > event.startDate else { return false }
        event.endDate = end
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            NSLog("Tiroflan : allongement impossible, \(error)")
            return false
        }
    }
}
