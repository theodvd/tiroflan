import AppKit
import ServiceManagement
import SwiftUI

/// Point d'entrée : icône dans la barre des menus, panneau, battement toutes les 15 s.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private let calendar = CalendarService()
    private lazy var store = Store(calendar: calendar)
    private let notifier = Notifier()
    private var ticker: Timer?
    private var calendarRefresher: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageLeading

        panel.setRoot(PanelRoot(store: store, calendar: calendar) { [weak self] size in
            self?.panel.resize(to: size)
        })
        panel.onHide = { [weak self] in self?.store.panelHidden() }

        notifier.store = store
        notifier.setup()
        store.notifier = notifier
        store.onChange = { [weak self] in self?.refreshStatusItem() }
        store.onRequestPanel = { [weak self] in self?.openPanel() }

        refreshStatusItem()
        ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.tick() }
        }
        ticker?.tolerance = 3

        // Toutes les 5 minutes : demande légère à macOS de rafraîchir Google, pour que les créneaux
        // supprimés dans Google Agenda ne restent pas comptés.
        calendarRefresher = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.calendar.refreshSources() }
        }
        calendarRefresher?.tolerance = 30

        // Retour de veille : le battement suivant mesure l'écart et propose de retirer ce temps.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.tick() }
        }

        firstLaunchSetup()

        // Lancée à la main (Finder, Spotlight, Launchpad) : l'app passe au premier plan, on ouvre le panneau.
        // Lancée à l'ouverture de session : elle reste discrète dans la barre des menus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if NSApp.isActive { self?.openPanel() }
        }
    }

    /// Double-clic sur l'app alors qu'elle tourne déjà : sans fenêtre, macOS n'afficherait rien, on ouvre le panneau.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPanel()
        return false
    }

    /// Menu Édition invisible : sans lui, une app de barre des menus ne reçoit pas ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z
    /// (indispensable pour coller une note ou dicter avec Wispr Flow, qui colle via ⌘V).
    private func installEditMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Tiroflan")
        appMenu.addItem(withTitle: "Fermer le panneau", action: #selector(closePanel), keyEquivalent: "w").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func closePanel() {
        panel.hide()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if !panel.isShown { calendar.refreshSources() }
        panel.toggle(below: button)
    }

    private func openPanel() {
        guard let button = statusItem.button, !panel.isShown else { return }
        calendar.refreshSources()
        panel.show(below: button)
    }

    /// Premier lancement : accès à l'agenda, relecture des agendas (choix automatique par client), lancement à l'ouverture de session.
    private func firstLaunchSetup() {
        let defaults = UserDefaults.standard
        if calendar.notDetermined {
            Task {
                await calendar.requestAccess()
                store.adoptDefaultCalendarIfNeeded()
            }
        } else {
            store.adoptDefaultCalendarIfNeeded()
        }
        if !defaults.bool(forKey: "loginItemSet") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "loginItemSet")
        }
    }

    // MARK: - Barre des menus

    /// Chrono en cours : flan au caramel orange + « Tamtam 1:23 ». Au repos : flan monochrome, toujours visible.
    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        if let running = store.data.running {
            button.image = MenuBarIcon.running(accent: Theme.accentNS)
            let title = NSMutableAttributedString(string: " \(store.client(running.clientID)?.name ?? "") ", attributes: [
                .font: Fonts.ns("Geist", size: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
            title.append(NSAttributedString(string: Fmt.hm(store.elapsedRunning(at: Date())), attributes: [
                .font: Fonts.ns("Geist Mono", size: 12.5, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]))
            button.attributedTitle = title
            button.toolTip = "Tiroflan · chrono en cours"
        } else {
            button.image = MenuBarIcon.idle()
            if store.pendingReviews.isEmpty {
                button.attributedTitle = NSAttributedString(string: "")
                button.toolTip = "Tiroflan"
            } else {
                button.attributedTitle = NSAttributedString(string: " ●", attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: Theme.accentNS,
                    .baselineOffset: 2,
                ])
                button.toolTip = "Tiroflan · séance à valider"
            }
        }
    }
}
