import AppKit
import Combine

final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelWindowController: NSWindowController, NSWindowDelegate {
    let store: PanelStore
    let panelView: PanelView

    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?
    private var lastHidden: Bool?
    private var lastLevel: PanelLevelMode?

    init(store: PanelStore, appStore: AppStore) {
        self.store = store
        self.panelView = PanelView(store: store, appStore: appStore)

        let frame = Self.saneFrame(store.config.frame.rect)
        let window = PanelWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = panelView
        window.setFrame(frame, display: false)

        super.init(window: window)
        shouldCascadeWindows = false

        window.delegate = self

        if frame != store.config.frame.rect {
            store.updateFrame(PanelFrame(rect: frame))
        }

        apply(store.config)
        store.$config
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)

        installKeyMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        store.updateFrame(PanelFrame(rect: window.frame))
    }

    private func apply(_ config: PanelConfig) {
        guard let window else { return }

        if lastLevel != config.levelMode {
            window.level = Self.level(for: config.levelMode)
            lastLevel = config.levelMode
            if !config.isHidden {
                window.orderFrontRegardless()
            }
        }

        if lastHidden != config.isHidden {
            if config.isHidden {
                window.orderOut(nil)
            } else {
                window.orderFrontRegardless()
            }
            lastHidden = config.isHidden
        }

        let target = config.frame.rect
        if !Self.framesClose(window.frame, target) {
            window.setFrame(target, display: true)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }

            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.panelView.beginSearch()
                return nil
            }

            if event.keyCode == 53, self.panelView.isSearchActive {
                self.panelView.endSearch(clear: true)
                return nil
            }

            if event.keyCode == 49, !self.panelView.isSearchActive, self.panelView.hasHoveredItem {
                self.panelView.previewHoveredItem()
                return nil
            }

            return event
        }
    }

    private static func level(for mode: PanelLevelMode) -> NSWindow.Level {
        switch mode {
        case .desktop:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating:
            return .floating
        }
    }

    private static func framesClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 1 &&
        abs(a.origin.y - b.origin.y) < 1 &&
        abs(a.size.width - b.size.width) < 1 &&
        abs(a.size.height - b.size.height) < 1
    }

    private static func saneFrame(_ frame: CGRect) -> CGRect {
        let screens = NSScreen.screens
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if screens.contains(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(center) }) {
            return frame
        }
        let visible = (NSScreen.main ?? screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var adjusted = frame
        adjusted.origin.x = visible.minX + 40
        adjusted.origin.y = visible.maxY - adjusted.height - 40
        return adjusted
    }
}
