"""Выложить визитку на https://legac.ru и спрятать админку на /console/.

Не трогает systemd/API (второй чат может деплоить бэкенд). Только файлы сайта и nginx reload.

Нужно: RYADOM_SSH_PASS, собранная admin/dist (npm run build в admin/).
"""
from __future__ import annotations

import io
import os
import tarfile
import time
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
PASS = os.environ.get("RYADOM_SSH_PASS", "")
if not PASS:
    raise SystemExit("Set RYADOM_SSH_PASS env var")
REMOTE = "/opt/ryadom56"
ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
DIST = ROOT / "admin" / "dist"

PATCHER = r'''
from pathlib import Path
import re
import subprocess
import sys

SNIP_PATH = Path("/etc/nginx/snippets/ryadom56-web.conf")
WEB_ROOT = "/opt/ryadom56/web"
MARKER = "ryadom56-web.conf"

snippet = Path("/opt/ryadom56/deploy/nginx_web.inc.conf").read_text(encoding="utf-8")
port = "8001"
for p in Path("/etc/nginx").rglob("*"):
    if not p.is_file():
        continue
    t = p.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"proxy_pass http://127\.0\.0\.1:(\d+)/api/", t)
    if m:
        port = m.group(1)
        break
snippet = snippet.replace("127.0.0.1:8001", f"127.0.0.1:{port}")
SNIP_PATH.parent.mkdir(parents=True, exist_ok=True)
SNIP_PATH.write_text(snippet, encoding="utf-8")

new_loc = f"""    include /etc/nginx/snippets/ryadom56-web.conf;
    location / {{
        root {WEB_ROOT};
        try_files $uri $uri/ =404;
    }}"""


def ours(block: str) -> bool:
    return any(x in block for x in ("ryadom56", "admin/dist", "legac.ru", "155.212.174.201"))


def patch_block(block: str) -> str:
    if not ours(block):
        return block
    if "location /api/" not in block and "admin/dist" not in block:
        return block
    out = block.replace("root /opt/ryadom56/admin/dist;", "root /opt/ryadom56/web;")
    if MARKER in out:
        return out

    def repl(m):
        body = m.group(0)
        if "admin/dist" in body or "try_files $uri $uri/ /index.html" in body or f"root {WEB_ROOT}" in body:
            return new_loc
        return body

    updated, n = re.subn(r"location\s+/\s*\{[^{}]*\}", repl, out)
    if n == 0 or MARKER not in updated:
        idx = updated.rfind("}")
        if idx != -1:
            updated = updated[:idx] + new_loc + "\n" + updated[idx:]
    return updated


changed = 0
backups = []
files = []
for folder in (Path("/etc/nginx/sites-enabled"), Path("/etc/nginx/sites-available"), Path("/etc/nginx/conf.d")):
    if folder.is_dir():
        files.extend(folder.iterdir())
seen = set()
for p in files:
    if not p.is_file():
        continue
    key = str(p.resolve())
    if key in seen:
        continue
    seen.add(key)
    text = p.read_text(encoding="utf-8", errors="replace")
    if not ours(text):
        continue
    print("----", p, "----")
    print(text[:1800])
    parts = re.split(r"(?<=\n)(?=server\s*\{)", text)
    new_parts = [patch_block(part) for part in parts]
    new_text = "".join(new_parts)
    if new_text != text:
        bak = Path(str(p) + ".bak-web")
        bak.write_text(text, encoding="utf-8")
        backups.append((p, bak))
        p.write_text(new_text, encoding="utf-8")
        changed += 1
        print("patched", p)
print("api_port", port, "files_changed", changed)
test = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
print(test.stdout)
print(test.stderr)
if test.returncode != 0:
    for p, bak in backups:
        p.write_text(bak.read_text(encoding="utf-8"), encoding="utf-8")
        print("restored", p)
    sys.exit(1)
'''


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 180) -> str:
    print(">", cmd[:220])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = (out + ("\n" + err if err.strip() else "")).strip()
    if text:
        print(text[-3000:])
    if code != 0:
        raise SystemExit(f"fail {code}: {cmd}")
    return out


def tar_dir(src: Path, arcname: str) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(src, arcname=arcname)
    return buf.getvalue()


def main() -> None:
    if not (SITE / "index.html").is_file():
        raise SystemExit("site/index.html missing")
    if not (DIST / "index.html").is_file():
        raise SystemExit("admin/dist missing — cd admin && npm run build")

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)
    run(c, f"mkdir -p {REMOTE}/web {REMOTE}/admin {REMOTE}/deploy")
    sftp = c.open_sftp()

    site_gz = tar_dir(SITE, "web")
    with sftp.file("/tmp/ryadom56-web.tar.gz", "wb") as f:
        f.write(site_gz)
    print("put site")

    dist_gz = tar_dir(DIST, "dist")
    with sftp.file("/tmp/ryadom56-admin.tar.gz", "wb") as f:
        f.write(dist_gz)
    print("put admin/dist")

    inc = ROOT / "deploy" / "nginx_web.inc.conf"
    sftp.put(str(inc), f"{REMOTE}/deploy/nginx_web.inc.conf")
    sftp.close()

    run(
        c,
        "rm -rf /opt/ryadom56/web && mkdir -p /opt/ryadom56 && "
        "tar -xzf /tmp/ryadom56-web.tar.gz -C /opt/ryadom56 && rm -f /tmp/ryadom56-web.tar.gz",
    )
    run(
        c,
        "rm -rf /opt/ryadom56/admin/dist && mkdir -p /opt/ryadom56/admin && "
        "tar -xzf /tmp/ryadom56-admin.tar.gz -C /opt/ryadom56/admin && rm -f /tmp/ryadom56-admin.tar.gz",
    )
    # на случай если alias не сработает — дубль через symlink
    run(c, "ln -sfn /opt/ryadom56/admin/dist /opt/ryadom56/web/console")
    run(c, f"python3 - <<'PY'\n{PATCHER}\nPY")
    run(c, "nginx -t && systemctl reload nginx")
    time.sleep(1)
    run(c, "curl -sS -o /dev/null -w 'root %{http_code} %{redirect_url}\\n' http://127.0.0.1:8080/")
    run(c, "curl -sS -o /dev/null -w 'https_root %{http_code}\\n' https://127.0.0.1/ -k --resolve legac.ru:443:127.0.0.1 || true")
    run(
        c,
        "python3 - <<'PY'\n"
        "from pathlib import Path\n"
        "p=Path('/opt/ryadom56/web/index.html')\n"
        "print('web_index', p.is_file(), p.stat().st_size if p.is_file() else 0)\n"
        "print('console_link', Path('/opt/ryadom56/web/console').is_symlink() or Path('/opt/ryadom56/web/console/index.html').is_file())\n"
        "print('admin_index', Path('/opt/ryadom56/admin/dist/index.html').is_file())\n"
        "t=Path('/opt/ryadom56/web/index.html').read_text(encoding='utf-8')\n"
        "print('is_landing', 'Всё, что рядом' in t and 'Админка' not in t)\n"
        "PY",
    )
    c.close()
    print("SITE_DEPLOY_OK")
    print("Public:  https://legac.ru/")
    print("Admin:   https://legac.ru/console/")


if __name__ == "__main__":
    main()
