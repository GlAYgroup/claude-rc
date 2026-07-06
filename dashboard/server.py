#!/usr/bin/env python3
# ============================================================================
# claude-rc dashboard server
#   管理画面(index.html)と PWA 資産を配信し、/api/* で claude-rc を呼び出して
#   フォルダ/セッションの RC をトグルする。
#
#   バインド:
#     RC_DASH_BIND=127.0.0.1 (既定) … このMacのみ（メニューバーのポップオーバー用）
#     RC_DASH_BIND=0.0.0.0        … LAN / Tailscale からも到達可（スマホ対応）
#   認証:
#     127.0.0.1 からのアクセスはトークン不要（ローカルUIを壊さない）。
#     それ以外は RC_DASH_TOKEN が必須（?token= / X-RC-Token / Cookie）。
#     トークンは初回起動時に自動生成し config.sh に保存。
#   設定は config.sh が正で、起動時に `claude-rc getcfg` で読む。
# ============================================================================
import hmac
import json
import os
import re
import secrets
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
RC   = os.environ.get("CLAUDE_RC_BIN") or os.path.expanduser("~/bin/claude-rc")

ENV = dict(os.environ)
ENV["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" \
              + os.path.expanduser("~/.local/bin") + ":" + os.path.expanduser("~/bin") \
              + ":" + ENV.get("PATH", "")

STATIC = {
    "/":                     ("index.html",          "text/html; charset=utf-8"),
    "/index.html":           ("index.html",          "text/html; charset=utf-8"),
    "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json"),
    "/sw.js":                ("sw.js",               "application/javascript"),
    "/icon.svg":             ("icon.svg",            "image/svg+xml"),
    "/favicon.ico":          ("icon.svg",            "image/svg+xml"),
    "/icon-180.png":         ("icon-180.png",        "image/png"),
}

def rc(*args, timeout=90):
    """claude-rc をサブプロセスで実行。 (rc, stdout, stderr) を返す。"""
    try:
        p = subprocess.run([RC, *args], capture_output=True, text=True,
                           encoding="utf-8", env=ENV, timeout=timeout)
        return p.returncode, (p.stdout or ""), (p.stderr or "")
    except Exception as e:
        return 1, "", str(e)

def cfg(key, default=""):
    _, v, _ = rc("getcfg", key)
    v = v.strip()
    return v if v else default

# ---- 起動時に config から確定させる ----
PORT  = int(os.environ.get("RC_DASH_PORT") or cfg("RC_DASH_PORT", "8787"))
BIND  = cfg("RC_DASH_BIND", "127.0.0.1")
TOKEN = cfg("RC_DASH_TOKEN", "")
if not TOKEN:
    TOKEN = secrets.token_hex(16)
    rc("setcfg", "RC_DASH_TOKEN", TOKEN)

def sh(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, env=ENV, timeout=5)
        return (p.stdout or "").strip()
    except Exception:
        return ""

def lan_ip():
    for ifc in ("en0", "en1", "en2"):
        ip = sh(["ipconfig", "getifaddr", ifc])
        if ip:
            return ip
    return ""

def tailscale_ip():
    out = sh(["ifconfig"])
    m = re.search(r"inet (100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d+\.\d+)", out)
    return m.group(1) if m else ""

def access_info():
    enabled = BIND not in ("127.0.0.1", "localhost", "::1")
    urls = []
    if enabled:
        ip = lan_ip()
        if ip:
            urls.append({"label": "Wi-Fi (同じネットワーク)", "url": f"http://{ip}:{PORT}/?token={TOKEN}"})
        ts = tailscale_ip()
        if ts:
            urls.append({"label": "Tailscale (外出先OK)", "url": f"http://{ts}:{PORT}/?token={TOKEN}"})
    return {"enabled": enabled, "bind": BIND, "urls": urls}

def parse_tsv(out, ncol):
    rows = []
    for ln in out.splitlines():
        if not ln.strip():
            continue
        parts = ln.split("\t")
        if len(parts) < ncol:
            parts += [""] * (ncol - len(parts))
        rows.append(parts[:ncol])
    return rows

def launchd_on():
    out = sh(["launchctl", "list"])
    return any("claude-rc.start" in ln for ln in out.splitlines())

def get_state():
    _, reg, _  = rc("registered", "--porcelain")
    _, git, _  = rc("git-folders", "--porcelain")
    _, ses, _  = rc("sessions", "10", "--porcelain")
    registered = [{"path": p, "name": n, "run": r == "1", "exists": e == "1"}
                  for (p, n, r, e) in parse_tsv(reg, 4)]
    gitfolders = [{"path": p, "name": n} for (p, n) in parse_tsv(git, 2)]
    sessions   = [{"id": i, "cwd": c, "run": r == "1", "summary": s}
                  for (i, c, r, s) in parse_tsv(ses, 4)]
    settings = {
        "RC_PERMISSION_MODE": cfg("RC_PERMISSION_MODE", "auto"),
        "RC_RESUME_MODE":     cfg("RC_RESUME_MODE", "1"),
        "START_STAGGER_SECS": cfg("START_STAGGER_SECS", "2"),
        "RC_DEBUG_LOG":       cfg("RC_DEBUG_LOG", "0"),
    }
    running = sum(1 for x in registered if x["run"]) + sum(1 for x in sessions if x["run"])
    return {"registered": registered, "git": gitfolders, "sessions": sessions,
            "settings": settings, "running": running, "launchd": launchd_on(),
            "access": access_info()}

def restart_self():
    # 新しい bind/token 設定で自分を再起動（fd は PEP446 で exec 時に閉じる）
    os.execv(sys.executable, [sys.executable, os.path.abspath(__file__)])

class H(BaseHTTPRequestHandler):
    # ---- helpers ----
    def _send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False)
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _json_body(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def _is_local(self):
        return self.client_address[0] in ("127.0.0.1", "::1")

    def _token_ok(self):
        q = parse_qs(urlparse(self.path).query)
        cand = (q.get("token", [""])[0]
                or self.headers.get("X-RC-Token", "")
                or self._cookie("rctoken"))
        return bool(cand) and hmac.compare_digest(cand, TOKEN)

    def _cookie(self, name):
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            k, _, v = part.strip().partition("=")
            if k == name:
                return v
        return ""

    def _authorized(self):
        return self._is_local() or self._token_ok()

    def log_message(self, *a):
        pass

    # ---- routes ----
    def do_GET(self):
        path = urlparse(self.path).path
        if not self._authorized():
            return self._send(401, "<h3>claude-rc: token required</h3>", "text/html; charset=utf-8")
        if path == "/api/ping":
            return self._send(200, {"ok": True})
        if path == "/api/state":
            return self._send(200, get_state())
        if path in STATIC:
            fn, ctype = STATIC[path]
            fp = os.path.join(HERE, fn)
            if os.path.isfile(fp):
                extra = {}
                # 有効なトークン付きで来たら Cookie を発行（PWA/以降のアクセス用・30日）
                if not self._is_local() and self._token_ok():
                    extra["Set-Cookie"] = f"rctoken={TOKEN}; Max-Age=2592000; Path=/; SameSite=Lax"
                with open(fp, "rb") as f:
                    return self._send(200, f.read(), ctype, extra)
            return self._send(404, {"error": f"{fn} not found"})
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorized():
            return self._send(401, {"error": "token required"})
        path = urlparse(self.path).path
        b = self._json_body()
        def ok(code=0, out="", err=""):
            return self._send(200, {"ok": code == 0, "out": out.strip(), "err": err.strip()})

        if path == "/api/folder-on":
            return ok(*rc("rc-on", b.get("path", "")))
        if path == "/api/folder-off":
            return ok(*rc("rc-off", b.get("name") or b.get("path", "")))
        if path == "/api/folder-add":
            return ok(*rc("add", "--no-repo", b.get("path", "")))
        if path == "/api/folder-remove":
            return ok(*rc("unregister", b.get("path", "")))
        if path == "/api/session-on":
            return ok(*rc("session-on", b.get("id", ""), b.get("cwd", "")))
        if path == "/api/session-off":
            return ok(*rc("session-off", b.get("id", "")))
        if path == "/api/setcfg":
            return ok(*rc("setcfg", b.get("key", ""), str(b.get("value", ""))))
        if path == "/api/launchd":
            return ok(*rc("resume" if b.get("on") else "pause"))
        if path == "/api/restart":
            self._send(200, {"ok": True, "restarting": True})
            threading.Timer(0.6, restart_self).start()
            return
        if path == "/api/choose-folder":
            if not self._is_local():
                return self._send(200, {"ok": False, "err": "フォルダ選択はMac上でのみ使えます"})
            try:
                p = subprocess.run(
                    ["osascript", "-e",
                     'POSIX path of (choose folder with prompt "常駐フォルダを選択")'],
                    capture_output=True, text=True, timeout=120)
                if p.returncode != 0:
                    return self._send(200, {"ok": False, "cancelled": True})
                folder = p.stdout.strip().rstrip("/")
                code, out, err = rc("add", "--no-repo", folder)
                return self._send(200, {"ok": code == 0, "path": folder,
                                        "out": out.strip(), "err": err.strip()})
            except Exception as e:
                return self._send(200, {"ok": False, "err": str(e)})
        if path == "/api/bulk":
            scope, on = b.get("scope", "all"), bool(b.get("on"))
            st = get_state()
            errs = []
            def do(code, out, err):
                if code != 0 and err.strip():
                    errs.append(err.strip())
            if scope in ("registered", "all"):
                if on:
                    do(*rc("start"))
                else:
                    for x in st["registered"]:
                        if x["run"]:
                            do(*rc("rc-off", x["name"]))
            if scope in ("sessions", "all"):
                for x in st["sessions"]:
                    if on and not x["run"]:
                        do(*rc("session-on", x["id"], x["cwd"]))
                    elif not on and x["run"]:
                        do(*rc("session-off", x["id"]))
            return self._send(200, {"ok": len(errs) == 0, "errors": errs})
        return self._send(404, {"error": "unknown endpoint"})

def main():
    os.makedirs(os.path.join(os.path.expanduser("~/.config/claude-rc"), "logs"), exist_ok=True)
    srv = ThreadingHTTPServer((BIND, PORT), H)
    print(f"claude-rc dashboard on http://{BIND}:{PORT}  (rc={RC})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
