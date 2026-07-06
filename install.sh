#!/usr/bin/env bash
# ============================================================================
# claude-rc installer
#   ./install.sh            … 本体・ダッシュボード・プラグイン類を配置
#   ./install.sh --launchd  … さらに自動起動(自己修復＋スリープ抑止)も登録
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"
CFG="$HOME/.config/claude-rc"

echo "== claude-rc を配置します =="

mkdir -p "$BIN_DIR" "$CFG/dashboard" "$CFG/swiftbar" "$CFG/hooks" "$CFG/launchd" "$CFG/logs"

install -m 755 "$REPO/claude-rc" "$BIN_DIR/claude-rc"
echo "  bin      → $BIN_DIR/claude-rc"

cp "$REPO/dashboard/server.py" \
   "$REPO/dashboard/index.html" \
   "$REPO/dashboard/manifest.webmanifest" \
   "$REPO/dashboard/sw.js" \
   "$REPO/dashboard/icon.svg" \
   "$REPO/dashboard/icon-180.png" \
   "$CFG/dashboard/"
echo "  panel    → $CFG/dashboard/"

install -m 755 "$REPO/swiftbar/claude-rc.10s.sh" "$CFG/swiftbar/claude-rc.10s.sh"
echo "  swiftbar → $CFG/swiftbar/claude-rc.10s.sh"

install -m 755 "$REPO/hooks/onboard.sh" "$CFG/hooks/onboard.sh"
echo "  hooks    → $CFG/hooks/onboard.sh"

if [ ! -f "$CFG/config.sh" ]; then
  cp "$REPO/config.example.sh" "$CFG/config.sh"
  echo "  config   → $CFG/config.sh (新規作成)"
else
  echo "  config   → 既存の $CFG/config.sh を維持"
fi

# launchd テンプレートを実パスに展開
for t in com.claude-rc.start com.claude-rc.caffeinate; do
  sed "s|__HOME__|$HOME|g" "$REPO/launchd/$t.plist.tmpl" > "$CFG/launchd/$t.plist"
done
echo "  launchd  → $CFG/launchd/ (テンプレート展開済み)"

if [ "${1:-}" = "--launchd" ]; then
  cp "$CFG/launchd/"com.claude-rc.*.plist "$HOME/Library/LaunchAgents/"
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.claude-rc.start.plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.claude-rc.caffeinate.plist" 2>/dev/null || true
  echo "  自動起動 → 登録しました（自己修復5分毎＋スリープ抑止）"
fi

echo
echo "== 完了 =="
echo
echo "次のステップ:"
echo "  1. PATH に $BIN_DIR を追加（未追加なら）:  export PATH=\"\$HOME/bin:\$PATH\""
echo "  2. 常駐したいフォルダで一度 'claude' を実行し workspace trust を承認"
echo "  3. 起動:            claude-rc start"
echo "  4. 管理パネル:      claude-rc dashboard"
echo "  5. メニューバー常駐: brew install --cask swiftbar"
echo "     SwiftBar の Plugin Directory を $CFG/swiftbar に設定"
echo "  6. 自動起動を後から入れる場合: ./install.sh --launchd"
