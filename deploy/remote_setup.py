"""One-shot deploy of Ryadom56 to VPS (alongside existing services)."""
from __future__ import annotations

import io
import os
import secrets
import tarfile
import time
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
USER = "root"
PASSWORD = os.environ.get("RYADOM_SSH_PASS", "")
if not PASSWORD:
    raise SystemExit("Set RYADOM_SSH_PASS env var")
ROOT = Path(__file__).resolve().parents[1]
REMOTE_APP = "/opt/ryadom56"
API_PORT = 8001
HTTP_PORT = 8080
REPO = "https://github.com/Restore2022/ryadom56.git"
SECRET = secrets.token_urlsafe(48)


def ssh_connect() -> paramiko.SSHClient:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PASSWORD, timeout=60, allow_agent=False, look_for_keys=False)
    return c


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 600) -> str:
    print(f"$ {cmd[:200]}")
    stdin, stdout, stderr = c.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    def _safe(s: str) -> str:
        return s.encode("ascii", "replace").decode("ascii")

    if out.strip():
        print(_safe(out[-4000:]))
    if err.strip():
        print(_safe(err[-2000:]))
    if code != 0:
        raise RuntimeError(_safe(f"Command failed ({code}): {cmd}\n{err}"))
    return out


def upload_admin(c: paramiko.SSHClient) -> None:
    dist = ROOT / "admin" / "dist"
    if not dist.exists():
        raise SystemExit("admin/dist missing — run npm run build first")
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(dist, arcname="dist")
    buf.seek(0)
    sftp = c.open_sftp()
    remote_tar = "/tmp/ryadom56-admin.tar.gz"
    with sftp.file(remote_tar, "wb") as f:
        f.write(buf.read())
    sftp.close()
    run(c, f"mkdir -p {REMOTE_APP}/admin && tar -xzf {remote_tar} -C {REMOTE_APP}/admin && rm -f {remote_tar}")


NGINX = f"""
server {{
    listen {HTTP_PORT};
    server_name {HOST};

    client_max_body_size 100m;

    location /api/ {{
        proxy_pass http://127.0.0.1:{API_PORT}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}

    location /uploads/ {{
        proxy_pass http://127.0.0.1:{API_PORT}/uploads/;
        proxy_set_header Host $host;
    }}

    location /docs {{
        proxy_pass http://127.0.0.1:{API_PORT}/docs;
        proxy_set_header Host $host;
    }}

    location /openapi.json {{
        proxy_pass http://127.0.0.1:{API_PORT}/openapi.json;
        proxy_set_header Host $host;
    }}

    include /etc/nginx/snippets/ryadom56-web.conf;

    location / {{
        root {REMOTE_APP}/web;
        try_files $uri $uri/ =404;
    }}
}}
"""

SYSTEMD = f"""
[Unit]
Description=Ryadom56 API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory={REMOTE_APP}/backend
EnvironmentFile={REMOTE_APP}/backend/.env
ExecStart={REMOTE_APP}/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port {API_PORT} --workers 1
Restart=always
RestartSec=3
MemoryMax=350M

[Install]
WantedBy=multi-user.target
"""

ENV = f"""
APP_NAME=Рядом56
SECRET_KEY={SECRET}
DATABASE_URL=sqlite:////opt/ryadom56/backend/data/ryadom56.db
CORS_ORIGINS=["http://{HOST}:{HTTP_PORT}","http://127.0.0.1:{HTTP_PORT}"]
ADMIN_EMAIL=admin@ryadom56.ru
ADMIN_PASSWORD=admin123
ADMIN_NAME=Администратор
"""


def main() -> None:
    c = ssh_connect()
    try:
        run(c, "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq")
        run(
            c,
            "export DEBIAN_FRONTEND=noninteractive; apt-get install -y -qq "
            "python3 python3-venv python3-pip git nginx curl",
        )
        # more swap if tiny
        run(
            c,
            "if [ ! -f /swapfile2 ]; then "
            "fallocate -l 1G /swapfile2 && chmod 600 /swapfile2 && mkswap /swapfile2 && swapon /swapfile2 && "
            "echo '/swapfile2 none swap sw 0 0' >> /etc/fstab; fi || true",
        )
        run(c, f"mkdir -p {REMOTE_APP}")
        run(
            c,
            f"if [ -d {REMOTE_APP}/.git ]; then cd {REMOTE_APP} && git fetch --depth 1 origin main && "
            f"git reset --hard origin/main; "
            f"else rm -rf {REMOTE_APP}/* {REMOTE_APP}/.[!.]* 2>/dev/null; "
            f"git clone --depth 1 -b main {REPO} {REMOTE_APP}; fi",
        )
        run(c, f"python3 -m venv {REMOTE_APP}/venv")
        run(
            c,
            f"{REMOTE_APP}/venv/bin/pip install -U pip wheel && "
            f"{REMOTE_APP}/venv/bin/pip install -r {REMOTE_APP}/backend/requirements.txt",
            timeout=900,
        )
        run(c, f"mkdir -p {REMOTE_APP}/backend/data/uploads {REMOTE_APP}/backend/data/releases")

        # write env + systemd + nginx via sftp
        sftp = c.open_sftp()
        with sftp.file(f"{REMOTE_APP}/backend/.env", "w") as f:
            f.write(ENV.strip() + "\n")
        with sftp.file("/etc/systemd/system/ryadom56.service", "w") as f:
            f.write(SYSTEMD.strip() + "\n")
        with sftp.file("/etc/nginx/sites-available/ryadom56", "w") as f:
            f.write(NGINX.strip() + "\n")
        sftp.close()

        upload_admin(c)

        run(c, "ln -sfn /etc/nginx/sites-available/ryadom56 /etc/nginx/sites-enabled/ryadom56")
        run(c, "nginx -t && systemctl reload nginx")
        run(c, "systemctl daemon-reload && systemctl enable --now ryadom56 && systemctl restart ryadom56")
        time.sleep(3)
        run(c, "systemctl --no-pager --full status ryadom56 | head -25 || true")
        run(c, f"curl -sS http://127.0.0.1:{API_PORT}/api/health")
        run(c, f"curl -sS -o /dev/null -w '%{{http_code}}' http://127.0.0.1:{HTTP_PORT}/")
        # open firewall if ufw active
        run(
            c,
            f"if command -v ufw >/dev/null && ufw status | grep -q active; then ufw allow {HTTP_PORT}/tcp; ufw reload; fi || true",
        )
        print("\nOK")
        print(f"Admin: http://{HOST}:{HTTP_PORT}/")
        print(f"API:   http://{HOST}:{HTTP_PORT}/api/health")
        print("Login: admin@ryadom56.ru / admin123")
    finally:
        c.close()


if __name__ == "__main__":
    main()
