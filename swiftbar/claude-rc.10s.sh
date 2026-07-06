#!/usr/bin/env bash
# ============================================================================
# SwiftBar plugin for claude-rc — メニューバーの 🟢 をクリックすると、
# 管理パネル（ダッシュボード）をその場のポップオーバー(WebView)で表示する。
# ファイル名の "10s" は更新間隔。置き場所: SwiftBar の Plugin Directory。
#
# <xbar.title>claude-rc</xbar.title>
# <xbar.desc>claude-rc control panel in a menu bar popover.</xbar.desc>
# <swiftbar.persistentWebView>true</swiftbar.persistentWebView>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# ============================================================================
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/bin:$HOME/.local/bin:$PATH"
RC="$(command -v claude-rc 2>/dev/null || true)"; [ -n "$RC" ] || RC="$HOME/bin/claude-rc"

PORT=8787
# index.html の更新時刻をバージョンとして付ける：persistentWebView は URL が同じだと
# 古いページをキャッシュし続けるため、HTML更新時に URL を変えて確実に再読込させる。
VER="$(stat -f %m "$HOME/.config/claude-rc/dashboard/index.html" 2>/dev/null || echo 0)"
URL="http://127.0.0.1:$PORT/?v=$VER"

# パネルのサーバーが落ちていたら起こす（WebView 表示の前提）
if ! curl -s --max-time 1 "http://127.0.0.1:$PORT/api/ping" >/dev/null 2>&1; then
  RC_DASH_PORT="$PORT" CLAUDE_RC_BIN="$RC" nohup python3 \
    "$HOME/.config/claude-rc/dashboard/server.py" \
    >> "$HOME/.config/claude-rc/logs/dashboard.log" 2>&1 &
fi

# メニューバー・タイトル（クリック＝パネルをポップオーバー表示）
echo "🟢 | webview=true href=$URL webvieww=520 webviewh=760"
