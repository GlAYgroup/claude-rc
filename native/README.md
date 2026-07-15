# ClaudeRCPanel — native menu-bar vibrancy panel

A tiny, dependency-free macOS menu-bar app that hosts the claude-rc dashboard in a
borderless panel with **real desktop vibrancy** (`NSVisualEffectView`, `.behindWindow`)
— the translucent, blurred-desktop look you get in Control Center / BetterDisplay.

It replaces the SwiftBar `webview=true` plugin, which cannot be made translucent
(SwiftBar's `WKWebView` popover has no transparency hooks anywhere in its source).

## Build & run

```sh
./build.sh --run      # compiles with swiftc (no Xcode project), ad-hoc signs, launches
```

Output is `build/ClaudeRCPanel.app` (git-ignored — rebuild it, don't commit it).

## Install (login-persistent)

```sh
./build.sh
cp -R build/ClaudeRCPanel.app /Applications/
sed "s#__HOME__#$HOME#g" ../launchd/com.claude-rc.panel.plist.tmpl \
  > ~/Library/LaunchAgents/com.claude-rc.panel.plist
launchctl load ~/Library/LaunchAgents/com.claude-rc.panel.plist
```

(The template already points at `/Applications/ClaudeRCPanel.app`, so the `sed` is a
no-op unless you install elsewhere. The app is `LSUIElement`, so no Dock icon.)

The app owns the dashboard server's lifecycle: on launch and on every panel open it
runs the same curl-guarded `python3 server.py` self-heal the SwiftBar plugin used to,
so the panel works standalone.

## Gotchas we hit (all fixed in main.swift)

These cost real debugging time; they're documented so the next person doesn't repeat them.

- **A layer-backed container kills `.behindWindow` vibrancy.** Nesting the
  `NSVisualEffectView` inside a plain `NSView` that has `wantsLayer = true` +
  `layer.cornerRadius` + `layer.masksToBounds` renders the whole panel *fully
  transparent* (invisible — you see the desktop sharply through it, no blur, no
  content). Fix: make the `NSVisualEffectView` the window's `contentView` directly,
  with the `WKWebView` as its subview.

- **Round corners with `maskImage`, not `masksToBounds`.** The mask-image must be built
  with `lockFocus` (a resizable rounded-rect with `capInsets` + `.stretch`). An
  `NSImage(size:flipped:drawingHandler:)` variant produced an all-clear mask that
  hid the entire panel.

- **`.blendingMode` must be `.behindWindow`.** `.withinWindow` blurs only the app's own
  content, never the real desktop.

- **`WKWebView` transparency needs `setValue(false, forKey: "drawsBackground")`** set
  *before* the first `load()`. `underPageBackgroundColor = .clear` (macOS 12+) only
  covers the overscroll region and isn't enough alone. The loaded page's own CSS must
  also be transparent — the dashboard does this under `?native=1`.

- **Don't trust `statusItem.button.window.frame` for positioning.** When the panel is
  toggled programmatically it can report a stale/invalid frame that throws the panel
  far off-screen (we saw origin `-24,-1159`). Anchor deterministically to the menu-bar
  screen's `visibleFrame.maxY`, use the button's X only when the frame looks valid, and
  clamp on-screen.

- **The app must start the dashboard server itself.** A `WKWebView` can render the
  cached HTML with no server, but every `/api/*` call then fails
  ("サーバーに接続できません"). `ensureServer()` handles this.

## Why swiftc and not Xcode

`main.swift` is compiled in script mode (top-level statements, no `@main`,
no `-parse-as-library`). Ad-hoc codesign (`codesign --force --deep --sign -`) is enough
for local `open`-launch. Zero entitlements are needed for `http://127.0.0.1` loads
(non-sandboxed apps have full network access; ATS exempts loopback).
