# claude-rc 設定ファイル（そのまま bash として読み込まれます）
# install.sh がこのファイルを ~/.config/claude-rc/config.sh にコピーします（既存なら触りません）。

# [list でスキャンする親ディレクトリ]
# ここ直下の各サブフォルダを「プロジェクト候補」として調べます。
SCAN_DIRS=(
  "$HOME/code"
  "$HOME/Documents"
  "$HOME/Projects"
)

# [start で実際に remote-control を立ち上げるプロジェクト（フルパス）]
# 常駐させたい “アクティブな” ものだけを列挙してください。
# GUI（メニューバーのパネル）やスマホからも追加/削除できます。
ACTIVE_DIRS=(
  # "$HOME/code/my-project"
)

# ---- 動作設定（GUIの設定タブから変更可） ----

# 権限モード：新規/再起動する remote-control セッションの承認方針。
#   auto=自動（推奨） / acceptEdits=編集のみ自動 / bypassPermissions=全自動 /
#   空=毎回承認 / plan / dontAsk
RC_PERMISSION_MODE="auto"

# 会話の再開方法（session-on）: 1=要約から再開（推奨・安い） / 2=全体を再開
#RC_RESUME_MODE="1"

# 一斉起動の時差（秒）。claude.ai への登録が 429 で落ちるのを防ぐ。
#START_STAGGER_SECS="2"

# 1 で各常駐の詳細デバッグログを ~/.config/claude-rc/logs に残す。
#RC_DEBUG_LOG="0"

# 1 で start 時に private GitHub リポを自動作成（既定 0＝自動 push しない・安全）。
#RC_AUTO_REPO="0"

# ---- ダッシュボード（管理パネル） ----

# 待受ポート。
#RC_DASH_PORT="8787"

# 127.0.0.1=このMacのみ（既定） / 0.0.0.0=LAN・Tailscale からアクセス可（スマホ対応）。
# GUIの「スマホからのアクセス」トグルでも切替できます。
#RC_DASH_BIND="127.0.0.1"

# 外部アクセス用トークン。空なら初回起動時に自動生成されます。
#RC_DASH_TOKEN=""
