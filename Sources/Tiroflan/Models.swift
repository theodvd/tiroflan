import Foundation

/// Dossier de l'app : ~/Library/Application Support/Tiroflan.
/// Global (et non membre du Store) pour être lisible depuis un thread de fond.
let supportDir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tiroflan", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}()

/// Un client (ou un projet perso) auquel on rattache des séances.
struct Client: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Domaine e-mail des participants (ex. « tamtam.ai ») pour reconnaître ses RDV dans l'agenda.
    var emailDomain: String
    /// Agenda où écrire ses séances (sa couleur fait le code couleur) ; nil = automatique.
    var calendarID: String?
    /// Heures à faire par semaine (ex. 21 pour Tamtam) ; nil = pas d'objectif, pas de décompte.
    var weeklyHours: Double?

    init(id: UUID = UUID(), name: String, emailDomain: String = "", calendarID: String? = nil, weeklyHours: Double? = nil) {
        self.id = id
        self.name = name
        self.emailDomain = emailDomain
        self.calendarID = calendarID
        self.weeklyHours = weeklyHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emailDomain = try c.decodeIfPresent(String.self, forKey: .emailDomain) ?? ""
        calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID)
        weeklyHours = try c.decodeIfPresent(Double.self, forKey: .weeklyHours)
    }
}

/// État d'un objectif tel que Claude le déduit d'une séance.
enum ObjectiveStatus: String, Codable, CaseIterable {
    case avance, bloque, termine

    /// Lecture tolérante de ce que renvoie Claude (accents, majuscules).
    init(loose: String) {
        let s = loose.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        if s.hasPrefix("bloq") { self = .bloque }
        else if s.hasPrefix("termin") || s.hasPrefix("fait") { self = .termine }
        else { self = .avance }
    }

    init(from decoder: Decoder) throws {
        self.init(loose: try decoder.singleValueContainer().decode(String.self))
    }

    var label: String {
        switch self {
        case .avance: return "avance"
        case .bloque: return "bloqué"
        case .termine: return "terminé"
        }
    }
}

/// Un objectif mentionné dans le résumé d'une séance.
struct ObjectiveMention: Codable, Hashable {
    var title: String
    var status: ObjectiveStatus
    var detail: String
}

/// Une séance de travail terminée.
struct Session: Codable, Identifiable, Hashable {
    var id: UUID
    var clientID: UUID
    var start: Date
    var end: Date
    /// Temps retiré (absence détectée, Mac en veille).
    var excludedSeconds: Double
    /// Titre court de la séance (titre de l'événement d'agenda).
    var title: String
    var note: String
    var objectives: [ObjectiveMention]
    var calendarEventID: String?
    /// Faux tant que le résumé n'a pas été validé ou ignoré.
    var reviewed: Bool
    var claudeSessionCount: Int
    /// Séance notée sur un autre Mac, reprise depuis l'agenda : un miroir qui suit son événement
    /// et ne se modifie que sur le Mac où elle a été notée.
    var imported: Bool

    var duration: TimeInterval { max(0, end.timeIntervalSince(start) - excludedSeconds) }

    init(id: UUID = UUID(), clientID: UUID, start: Date, end: Date, excludedSeconds: Double = 0,
         title: String = "", note: String = "", objectives: [ObjectiveMention] = [], calendarEventID: String? = nil,
         reviewed: Bool = false, claudeSessionCount: Int = 0, imported: Bool = false) {
        self.id = id
        self.clientID = clientID
        self.start = start
        self.end = end
        self.excludedSeconds = excludedSeconds
        self.title = title
        self.note = note
        self.objectives = objectives
        self.calendarEventID = calendarEventID
        self.reviewed = reviewed
        self.claudeSessionCount = claudeSessionCount
        self.imported = imported
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clientID = try c.decode(UUID.self, forKey: .clientID)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        excludedSeconds = try c.decodeIfPresent(Double.self, forKey: .excludedSeconds) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        objectives = try c.decodeIfPresent([ObjectiveMention].self, forKey: .objectives) ?? []
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        reviewed = try c.decodeIfPresent(Bool.self, forKey: .reviewed) ?? true
        claudeSessionCount = try c.decodeIfPresent(Int.self, forKey: .claudeSessionCount) ?? 0
        imported = try c.decodeIfPresent(Bool.self, forKey: .imported) ?? false
    }
}

/// Suivi d'un objectif dans le temps, pour repérer ce qui bloque plusieurs séances de suite.
struct ObjectiveRecord: Codable, Hashable {
    var title: String
    var clientID: UUID
    var status: ObjectiveStatus
    var detail: String
    var blockedStreak: Int
    var lastSeen: Date
}

/// Chrono en cours, sauvegardé pour survivre à un redémarrage.
struct RunningTimer: Codable {
    var clientID: UUID
    var start: Date
    var excludedSeconds: Double
    /// Dernier signe de vie de l'app, pour détecter une veille ou un arrêt du Mac.
    var lastSeen: Date

    init(clientID: UUID, start: Date) {
        self.clientID = clientID
        self.start = start
        self.excludedSeconds = 0
        self.lastSeen = start
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try c.decode(UUID.self, forKey: .clientID)
        start = try c.decode(Date.self, forKey: .start)
        excludedSeconds = try c.decodeIfPresent(Double.self, forKey: .excludedSeconds) ?? 0
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? start
    }
}

/// Réglages de l'app.
struct Preferences: Codable {
    var writeCalendarID: String?
    var writeToCalendar: Bool
    var idleMinutes: Int
    var longRunHours: Int
    var claudePath: String?

    init() {
        writeCalendarID = nil
        writeToCalendar = true
        idleMinutes = 15
        longRunHours = 4
        claudePath = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writeCalendarID = try c.decodeIfPresent(String.self, forKey: .writeCalendarID)
        writeToCalendar = try c.decodeIfPresent(Bool.self, forKey: .writeToCalendar) ?? true
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 15
        longRunHours = try c.decodeIfPresent(Int.self, forKey: .longRunHours) ?? 4
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath)
    }
}

/// Tout ce que l'app enregistre, dans un seul fichier JSON.
struct AppData: Codable {
    var clients: [Client]
    var sessions: [Session]
    var objectives: [ObjectiveRecord]
    var running: RunningTimer?
    var selectedClientID: UUID?
    var settings: Preferences

    /// Données de départ : Tamtam (premier client freelance) et Perso.
    static func initial() -> AppData {
        let tamtam = Client(name: "Tamtam", emailDomain: "tamtam.ai")
        let perso = Client(name: "Perso")
        return AppData(clients: [tamtam, perso], sessions: [], objectives: [], running: nil,
                       selectedClientID: tamtam.id, settings: Preferences())
    }

    init(clients: [Client], sessions: [Session], objectives: [ObjectiveRecord], running: RunningTimer?,
         selectedClientID: UUID?, settings: Preferences) {
        self.clients = clients
        self.sessions = sessions
        self.objectives = objectives
        self.running = running
        self.selectedClientID = selectedClientID
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clients = try c.decodeIfPresent([Client].self, forKey: .clients) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        objectives = try c.decodeIfPresent([ObjectiveRecord].self, forKey: .objectives) ?? []
        running = try c.decodeIfPresent(RunningTimer.self, forKey: .running)
        selectedClientID = try c.decodeIfPresent(UUID.self, forKey: .selectedClientID)
        settings = try c.decodeIfPresent(Preferences.self, forKey: .settings) ?? Preferences()
    }
}

/// Un rendez-vous du jour lu dans l'agenda.
struct AgendaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// Domaines e-mail des participants, pour deviner le client.
    let domains: [String]
}

/// Créneau de travail planifié dans l'agenda (ex. « tamtam » de 14:00 à 16:00), pas encore une séance.
struct PlannedSlot: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
}

/// Décompte de la semaine pour un client qui a un objectif d'heures.
struct WeekBalance: Equatable {
    let target: TimeInterval
    /// Séances de la semaine, chrono en cours compris.
    let done: TimeInterval
    /// Créneaux planifiés restants (la partie à venir seulement).
    let planned: TimeInterval

    /// Temps qui n'est ni fait ni planifié.
    var missing: TimeInterval { max(0, target - done - planned) }
}

/// Proposition d'allonger un créneau planifié pour tenir l'objectif de la semaine.
struct ExtensionProposal: Equatable {
    let clientID: UUID
    let slot: PlannedSlot
    let newEnd: Date
    let missing: TimeInterval
}
