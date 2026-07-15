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

// MARK: - Vibrant content view
//
// IMPORTANT: this view IS the NSVisualEffectView (it's the window's contentView),
// with the WKWebView as its subview. An earlier version nested the effect view
// inside a plain, layer-backed NSView container with cornerRadius + masksToBounds
// — and that layer mask silently KILLED `.behindWindow` compositing, so the whole
// panel rendered fully transparent (invisible). The fix, verified on-device: make
// the effect view the content view directly, and round the corners with `maskImage`
// (which the window server honours without breaking the desktop blur) instead of a
// masking sublayer.

final class VibrantWebContainer: NSVisualEffectView {
    let webView: WKWebView
    private let cornerRadius: CGFloat

    init(frame frameRect: NSRect, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frameRect)

        // .hudWindow + .behindWindow + .active = dark, Control-Center-style menu bar
        // dropdown that blurs the real desktop behind it.
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false

        // Rounded corners via a resizable mask image — safe for behind-window vibrancy
        // (unlike layer.masksToBounds, which disables the blur).
        maskImage = Self.roundedMask(radius: cornerRadius)

        // WKWebView — on top, transparent, pinned to the effect view.
        //   drawsBackground=false (KVC) is REQUIRED and must be set before the first
        //   load(); underPageBackgroundColor=.clear is the macOS 12+ public supplement
        //   for the overscroll/rubber-band region. Both together, belt-and-suspenders.
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
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

    // A resizable rounded-rectangle mask: a small stretchable image with cap insets so
    // the window server can tile it to any panel size while keeping crisp corners.
    // Built with lockFocus (the canonical, reliable form); an earlier drawingHandler
    // variant produced an all-clear mask that hid the entire panel.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2
        let image = NSImage(size: NSSize(width: d, height: d))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: d, height: d),
                     xRadius: radius, yRadius: radius).fill()
        image.unlockFocus()
        image.resizingMode = .stretch
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        return image
    }

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
            button.title = "🟢"
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        panel = makePanel()
        ensureServer()  // this app now owns the dashboard server's lifecycle
    }

    // Start the Python dashboard server if it isn't already answering. Mirrors the
    // self-heal the SwiftBar plugin used to do — the native app now owns it, so the
    // panel works standalone (WKWebView can cache the HTML but needs a live server
    // for /api/* calls, otherwise the page shows "サーバーに接続できません").
    private func ensureServer() {
        let script = """
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/bin:$PATH"
        if ! curl -s --max-time 1 http://127.0.0.1:8787/api/ping >/dev/null 2>&1; then
          mkdir -p "$HOME/.config/claude-rc/logs"
          RC_DASH_PORT=8787 CLAUDE_RC_BIN="$HOME/bin/claude-rc" nohup python3 \
            "$HOME/.config/claude-rc/dashboard/server.py" \
            >> "$HOME/.config/claude-rc/logs/dashboard.log" 2>&1 &
        fi
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", script]
        try? p.run()
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

        let c = VibrantWebContainer(frame: NSRect(origin: .zero, size: panelSize), cornerRadius: 14)
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
        // Anchor to the menu-bar screen (screens[0]) top edge, deterministically.
        // We DON'T trust statusItem.button.window.frame alone: when the panel is
        // toggled programmatically (Accessibility click) the button window can report
        // a stale/invalid frame, which previously threw the panel far off-screen
        // (observed origin -24,-1159). We use the button's X when it looks valid and
        // otherwise fall back to the screen centre, always clamped on-screen.
        let menuScreen = NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = menuScreen.visibleFrame   // excludes the menu bar; its maxY is the menu-bar bottom

        var buttonMidX = menuScreen.frame.midX
        if let button = statusItem.button, let bw = button.window {
            let f = bw.convertToScreen(button.convert(button.bounds, to: nil))
            // A valid status-button frame is a small rect sitting on the menu bar of
            // screens[0]; reject obviously-bogus frames (zero width, or off this screen).
            if f.width > 0, menuScreen.frame.intersects(f) {
                buttonMidX = f.midX
            }
        }

        let minX = menuScreen.frame.minX + 8
        let maxX = menuScreen.frame.maxX - panelSize.width - 8
        let originX = min(max(minX, buttonMidX - panelSize.width / 2), maxX)
        let originY = vf.maxY - panelSize.height          // top of panel flush under the menu bar

        ensureServer()     // revive the server if it died since last open
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
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
