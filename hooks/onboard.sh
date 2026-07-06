#!/usr/bin/env bash
# claude-rc SessionStart フック本体。
# 新しいフォルダで初めて claude セッションを開いたとき、そのフォルダを claude-rc の
# 常駐対象に自動追加し、スマホから「永続的に」触れるようにする。
# GitHub への push はしない（server一覧追加＋常駐起動だけ）。

dir="${CLAUDE_PROJECT_DIR:-$PWD}"

# 末尾スラッシュを正規化（/Users/x/code/ → /Users/x/code）。SCAN_DIR ルート判定のため。
dir="${dir%/}"

# 除外：ホーム直下・一時/システム・雑多な置き場（誤って常駐対象にしないため）
case "$dir" in
  "$HOME"|"$HOME/"|"$HOME/Downloads"*|"$HOME/Desktop"*|"$HOME/Library"*|/tmp/*|/private/*|/var/*) exit 0 ;;
esac

# 除外：ハーネスが作る使い捨て git worktree や .claude 内部パス。
# （セッション終了で削除され、登録すると死にエントリ化するため）
case "$dir" in
  */.claude/*|*/.git/*) exit 0 ;;
esac

# 除外：SCAN_DIRS のルート自身（プロジェクトの親フォルダであってプロジェクトではない）。
# config.sh から SCAN_DIRS を読み、完全一致したら何もしない。
CFG="$HOME/.config/claude-rc/config.sh"
if [ -r "$CFG" ]; then
  # SCAN_DIRS だけを安全に取り出す（config.sh 全体は source せず副作用を避ける）。
  # shellcheck disable=SC1090
  SCAN_DIRS=()
  source "$CFG" 2>/dev/null || true
  for root in "${SCAN_DIRS[@]}"; do
    [ "$dir" = "${root%/}" ] && exit 0
  done
fi

CRC="$HOME/bin/claude-rc"
[ -x "$CRC" ] || exit 0

# セッション開始を遅らせないようバックグラウンドで実行。add は冪等（既登録なら何もしない）。
# --no-repo と RC_AUTO_REPO=0 の二重ガードで GitHub への push は絶対にしない。
RC_AUTO_REPO=0 nohup "$CRC" add --no-repo "$dir" >> "$HOME/.config/claude-rc/logs/onboard.log" 2>&1 &
exit 0
