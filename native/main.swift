// claude-rc menu-bar vibrancy panel
//
// A tiny, dependency-free replacement for the SwiftBar "webview=true" plugin.
// SwiftBar's WKWebView popover cannot show real desktop vibrancy (verified by
// reading SwiftBar's own source — no NSVisualEffectView, no drawsBackground
// handling anywhere in it). This app owns its own borderless, non-activating
// NSPanel with a real NSVisualEffectView behind a transparent WKWebView, so
// the actual desktop shows through — matching the Control Center / BetterDisplay
// look the user asked for.
//
// Build: see build.sh in this directory (no Xcode project needed).

import AppKit
import WebKit

// MARK: - Vibrant content view (NSVisualEffectView backmost + WKWebView on top)

final class VibrantWebContainer: NSView {
    let effectView = NSVisualEffectView()
    let webView: WKWebView

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frameRect)

        wantsLayer = true

        // 1. Visual effect view — backmost, fills container, real desktop blur.
        //    .hudWindow + .behindWindow + .active is the documented combination for a
        //    dark Control-Center-style menu bar dropdown (confirmed via research).
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = false
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        // 2. WKWebView — on top, transparent, pinned identically.
        //    drawsBackground=false (KVC) is REQUIRED and must be set before the first
        //    load(); underPageBackgroundColor=.clear is the macOS 12+ public supplement
        //    for the overscroll/rubber-band region. Both together, belt-and-suspenders.
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // ?native=1 tells the dashboard's own CSS to drop its faux-vibrancy
        // background and go fully transparent so this real blur shows through.
        if let url = URL(string: "http://127.0.0.1:8787/?native=1") {
            webView.load(URLRequest(url: url))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func reload() {
        if let url = URL(string: "http://127.0.0.1:8787/?native=1") {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Borderless, non-activating panel

final class VibrantPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Status bar controller

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var panel: VibrantPanel!
    private var container: VibrantWebContainer!
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private let panelSize = NSSize(width: 380, height: 640)

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Text glyph, not an SF Symbol name, to guarantee it renders identically
            // to the existing 🟢 identity from the (now retired) SwiftBar plugin.
            button.title = "🟢"
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        panel = makePanel()
    }

    private func makePanel() -> VibrantPanel {
        let p = VibrantPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.appearance = NSAppearance(named: .vibrantDark)

        let c = VibrantWebContainer(frame: NSRect(origin: .zero, size: panelSize))
        c.wantsLayer = true
        c.layer?.cornerRadius = 14
        c.layer?.masksToBounds = true
        p.contentView = c
        container = c

        return p
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = NSPoint(
            x: buttonFrameInScreen.midX - panelSize.width / 2,
            y: buttonFrameInScreen.minY - panelSize.height
        )
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        container.reload()  // pick up any state changes made since it was last shown

        startOutsideClickMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)
        stopOutsideClickMonitors()
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            // Ignore clicks on the status bar button itself — its own action
            // handles toggling; otherwise this monitor would close the panel and
            // the button action would immediately reopen it (flicker / stuck-open bug).
            if let buttonWindow = self.statusItem.button?.window, event.window === buttonWindow {
                return event
            }

            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.closePanel()
            }
            return event
        }
    }

    private func stopOutsideClickMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localClickMonitor { NSEvent.removeMonitor(m); localClickMonitor = nil }
    }
}

// MARK: - App entry point (script-mode main.swift — no @main, no -parse-as-library)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // belt-and-suspenders alongside LSUIElement: no Dock icon, no app-switcher entry

let controller = StatusBarController()
controller.start()

app.run()
