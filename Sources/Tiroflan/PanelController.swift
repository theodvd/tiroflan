import AppKit
import SwiftUI

/// Fenêtre sans bordure qui peut recevoir le clavier (pour écrire la note de séance).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Panneau flottant sous l'icône de la barre des menus, sans flèche, refermé au clic ailleurs.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: KeyPanel
    private var hosting: NSHostingView<AnyView>?
    private weak var anchor: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    var onHide: (() -> Void)?

    override init() {
        // Panneau « activant » : Tiroflan passe au premier plan quand il s'ouvre, sinon le collage (⌘V)
        // et la dictée Wispr Flow partent dans l'app qui était devant.
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
                         styleMask: [.borderless], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
    }

    func setRoot<V: View>(_ view: V) {
        let host = NSHostingView(rootView: AnyView(view))
        host.translatesAutoresizingMaskIntoConstraints = true
        hosting = host
        panel.contentView = host
    }

    var isShown: Bool { panel.isVisible }

    func toggle(below button: NSStatusBarButton) {
        if isShown { hide() } else { show(below: button) }
    }

    func show(below button: NSStatusBarButton) {
        anchor = button
        let size = hosting?.fittingSize ?? CGSize(width: 360, height: 600)
        place(size: size)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        onHide?()
    }

    /// Le contenu a changé de taille (autre écran) : on garde le haut du panneau accroché sous l'icône.
    func resize(to size: CGSize) {
        guard panel.isVisible, size.height > 0 else { return }
        place(size: size)
    }

    private func place(size: CGSize) {
        let screen = anchor?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = visible.maxX - size.width - 8
        var y = visible.maxY - 6 - size.height
        // Sous l'icône si elle est affichée ; sinon (cachée par l'encoche ou les menus) en haut à droite.
        if let button = anchor, let window = button.window, window.isVisible,
           window.occlusionState.contains(.visible) {
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.width > 0, visible.minX...visible.maxX ~= buttonRect.midX {
                x = min(max(buttonRect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
                y = buttonRect.minY - 6 - size.height
            }
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
