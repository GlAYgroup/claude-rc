# claude-rc

**Manage Claude Code Remote Control per folder — from your Mac menu bar, or your phone.**

`claude-rc` keeps a fleet of [Claude Code](https://claude.com/claude-code) `remote-control` servers running — one per project folder — inside a dedicated tmux session, so every project on your Mac is reachable from the Claude mobile app / claude.ai/code at all times. A menu-bar popover panel (and a mobile web panel) lets you toggle folders and resume past conversations with one tap.

*日本語の説明は[下](#日本語)にあります。*

---

## Why

`claude remote-control` is per-directory and per-terminal. Once you have more than a couple of projects you end up babysitting terminal tabs. `claude-rc` turns that into:

- **One command** (`claude-rc start`) that brings up all your projects as remote-control servers in tmux windows
- **Self-healing** via launchd — dead servers respawn within 5 minutes, with crash logs preserved
- **A menu-bar panel** (SwiftBar popover) to toggle folders / resume sessions / change settings
- **Phone access** to the same panel (token-authenticated, LAN or Tailscale)
- **Session resume**: pick a recent conversation started on your PC and reopen it remotely (`claude --resume <id> --remote-control`)

Everything is plain bash + tmux + Python stdlib. No Node, no database, no cloud component beyond Claude itself.

## Requirements

- macOS (tested on Apple Silicon, macOS 15+)
- [Claude Code CLI](https://claude.com/claude-code) with a subscription (`claude` in PATH)
- `tmux` (`brew install tmux`)
- `python3` (ships with macOS command line tools)
- Optional: [SwiftBar](https://swiftbar.app) for the menu-bar panel (`brew install --cask swiftbar`)
- Optional: [Tailscale](https://tailscale.com) for phone access from outside your Wi-Fi

## Install

```bash
git clone https://github.com/GlAYgroup/claude-rc.git
cd claude-rc
./install.sh            # binaries + panel + config
# or: ./install.sh --launchd   # also register self-heal + sleep-prevention agents
```

Then:

1. Edit `~/.config/claude-rc/config.sh` — put your project folders in `ACTIVE_DIRS`
2. Run `claude` once in each folder to accept workspace trust
3. `claude-rc start`
4. `claude-rc status` shows each server and its claude.ai URL

For the menu bar: install SwiftBar and set its Plugin Directory to `~/.config/claude-rc/swiftbar`. A 🟢 appears; clicking it opens the control panel as a popover.

## Commands

| Command | What it does |
|---|---|
| `claude-rc start [name]` | Start all `ACTIVE_DIRS` (or one) as remote-control servers |
| `claude-rc stop [name]` | Stop all (or one) |
| `claude-rc restart <name>` | Restart one |
| `claude-rc status` / `watch [1s/5m/1h]` | Show state + connect URLs (once / repeatedly) |
| `claude-rc dashboard` | Start the web panel and open it as an app window |
| `claude-rc add [--no-repo] <dir>` | Register + start a new folder |
| `claude-rc unregister <dir>` | Remove a folder from the registry (reversible comment-out) |
| `claude-rc sessions [N]` | List recent conversations (from `~/.claude/projects`) |
| `claude-rc session-on <id> <cwd>` | Resume a past conversation with remote control |
| `claude-rc session-off <id>` | Stop a resumed conversation |
| `claude-rc rc-on/rc-off <dir>` | Toggle one folder without registering it |
| `claude-rc pause` / `resume` | Suspend / re-enable launchd self-heal |
| `claude-rc attach` | Attach to the raw tmux session |
| `claude-rc list` | Scan `SCAN_DIRS` and inventory projects |

## The panel

`claude-rc dashboard` serves a local web panel (Python stdlib, port 8787):

- **Folders tab** — registered folders with per-row toggles, red trash = unregister, plus unregistered git folders found under `SCAN_DIRS`, plus a native folder picker
- **Sessions tab** — recent conversations; toggling one resumes it remotely
- **Settings tab** — permission mode, resume mode, stagger, self-heal, debug log, phone access
- Group-level and global master switches for bulk on/off

The SwiftBar plugin embeds this panel as a menu-bar popover (`webview=true`). Note that inside the popover, native `confirm()` dialogs don't exist — the panel uses its own in-page modals.

## Phone access

Toggle **“スマホからのアクセス / phone access”** in the Settings tab (or set `RC_DASH_BIND="0.0.0.0"`). The server then also listens on your LAN / Tailscale interface with **token auth**:

- Requests from `127.0.0.1` need no token (the local popover keeps working)
- Anything else requires the token — as `?token=` once (sets a 30-day cookie), or `X-RC-Token` header
- The Settings tab shows ready-made URLs (Wi-Fi and Tailscale) with a copy button
- On your phone, open the URL once → “Add to Home Screen” → it behaves like an app

**Security notes:** the panel can start Claude sessions with your configured permission mode, so treat the URL+token as a secret. Prefer Tailscale (WireGuard-encrypted, private) over plain LAN for anything outside your home. Traffic on plain HTTP LAN is unencrypted. Never port-forward this to the open internet.

## Self-heal & sleep

`./install.sh --launchd` registers two LaunchAgents:

- `com.claude-rc.start` — runs `claude-rc start` at login and every 5 minutes (only dead servers are respawned; their last output is saved to `logs/<name>.crash.log`)
- `com.claude-rc.caffeinate` — prevents system sleep so servers stay reachable

Laptops: closed-lid sleep can still occur unless on AC power with an external display. `claude-rc pause` disables self-heal when you genuinely want things to stay stopped.

## Config reference

See [config.example.sh](config.example.sh) — `SCAN_DIRS`, `ACTIVE_DIRS`, `RC_PERMISSION_MODE`, `RC_RESUME_MODE`, `START_STAGGER_SECS`, `RC_DEBUG_LOG`, `RC_AUTO_REPO`, `RC_DASH_PORT`, `RC_DASH_BIND`, `RC_DASH_TOKEN`.

## Design notes / gotchas we hit

- **Locale-independent naming**: tmux window names derive from folder names via `LC_ALL=C` sanitization — UTF-8 locales treat Japanese as alphanumeric in `[:alnum:]`, which once made `status` report a running server as stopped.
- **Unicode normalization**: macOS paths mix NFC/NFD; duplicate-registration checks normalize via `iconv UTF-8-MAC` + case-folding, otherwise the same Japanese folder can register twice.
- **WKWebView popovers can't show `confirm()`** — always returns cancel. The panel ships its own modal.
- **`--spawn` belongs to the `remote-control` subcommand only**; `claude --resume <id> --remote-control` must run in the conversation's original cwd.
- Session resume of a big conversation triggers Claude's cost prompt; `session-on` watches the pane and answers it per `RC_RESUME_MODE`.

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.claude-rc.start.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.claude-rc.caffeinate.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.claude-rc.*.plist ~/bin/claude-rc
rm -rf ~/.config/claude-rc
```

## License

[MIT](LICENSE)

---

<a id="日本語"></a>

# 日本語

**Claude Code の Remote Control をフォルダ単位で常駐管理 — メニューバーからも、スマホからも。**

`claude-rc` は、プロジェクトフォルダごとに `claude remote-control` サーバーを専用 tmux セッション内で常駐させ、Mac 上の全プロジェクトをいつでも Claude モバイルアプリ / claude.ai/code から触れる状態に保ちます。メニューバーのポップオーバーパネル（スマホからは Web パネル）で、フォルダのオン/オフや過去会話の再開がワンタップでできます。

## 特徴

- **一括起動**: `claude-rc start` で登録フォルダ全部を tmux 窓として起動
- **自己修復**: launchd が5分ごとに死んだ常駐だけ復活（直前の出力は crash ログに退避）
- **メニューバーパネル**: SwiftBar のポップオーバーで、フォルダ/セッションのトグル・一括操作・設定変更
- **スマホ対応**: 同じパネルにトークン認証つきで LAN / Tailscale からアクセス。「ホーム画面に追加」でアプリ化
- **セッション再開**: PC で作った直近の会話を選んで `claude --resume <id> --remote-control` でリモート再開
- 依存は bash + tmux + Python 標準ライブラリのみ

## インストール

```bash
git clone https://github.com/GlAYgroup/claude-rc.git
cd claude-rc
./install.sh              # 本体＋パネル＋設定
# ./install.sh --launchd  # 自動起動（自己修復＋スリープ抑止）も登録
```

1. `~/.config/claude-rc/config.sh` の `ACTIVE_DIRS` に常駐させたいフォルダを列挙
2. 各フォルダで一度 `claude` を実行して workspace trust を承認
3. `claude-rc start` → `claude-rc status` で URL 確認
4. メニューバー化: `brew install --cask swiftbar` → Plugin Directory を `~/.config/claude-rc/swiftbar` に設定

## スマホからのアクセス

パネルの設定タブで「外部アクセスを許可」をオンにすると、LAN / Tailscale インターフェースでも待受します（トークン認証つき・localhost は認証なしのまま）。設定タブに表示される URL をスマホで一度開き、「ホーム画面に追加」すればアプリのように使えます。

**セキュリティ**: このパネルは Claude セッションを起動できる強い入口です。URL＋トークンは秘密として扱い、外出先からは平文 LAN ではなく Tailscale（WireGuard 暗号化）経由を推奨。インターネットへのポート開放は絶対にしないでください。

## ライセンス

[MIT](LICENSE)
