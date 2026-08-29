from __future__ import annotations

import io
import secrets
import tarfile
import time
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
PASS = __import__("os").environ.get("RYADOM_SSH_PASS", "")
if not PASS:
    raise SystemExit("Set RYADOM_SSH_PASS env var")
REMOTE = "/opt/ryadom56"
ROOT = Path(__file__).resolve().parents[1]
SECRET = secrets.token_urlsafe(48)
API_PORT = 8001
HTTP_PORT = 8080


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 300) -> str:
    print(">", cmd[:140])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()

    def safe(s: str) -> str:
        return s.encode("ascii", "replace").decode("ascii")

    if out:
        print(safe(out[-2500:]))
    if err:
        print(safe(err[-1500:]))
    if code != 0:
        raise SystemExit(f"fail {code}: {cmd}")
    return out


def main() -> None:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)

    env = f"""APP_NAME=Ryadom56
SECRET_KEY={SECRET}
DATABASE_URL=sqlite:////opt/ryadom56/backend/data/ryadom56.db
CORS_ORIGINS=["http://{HOST}:{HTTP_PORT}","http://127.0.0.1:{HTTP_PORT}"]
ADMIN_EMAIL=admin@ryadom56.ru
ADMIN_PASSWORD=admin123
ADMIN_NAME=Admin
"""
    systemd = f"""[Unit]
Description=Ryadom56 API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory={REMOTE}/backend
EnvironmentFile={REMOTE}/backend/.env
ExecStart={REMOTE}/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port {API_PORT} --workers 1
Restart=always
RestartSec=3
MemoryMax=350M

[Install]
WantedBy=multi-user.target
"""
    nginx = f"""server {{
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
        root {REMOTE}/web;
        try_files $uri $uri/ =404;
    }}
}}
"""

    run(c, f"mkdir -p {REMOTE}/backend/data/uploads {REMOTE}/backend/data/releases {REMOTE}/admin")
    sftp = c.open_sftp()
    with sftp.file(f"{REMOTE}/backend/.env", "w") as f:
        f.write(env)
    with sftp.file("/etc/systemd/system/ryadom56.service", "w") as f:
        f.write(systemd)
    with sftp.file("/etc/nginx/sites-available/ryadom56", "w") as f:
        f.write(nginx)
    sftp.close()

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(ROOT / "admin" / "dist", arcname="dist")
    buf.seek(0)
    sftp = c.open_sftp()
    with sftp.file("/tmp/ryadom56-admin.tar.gz", "wb") as f:
        f.write(buf.read())
    sftp.close()
    run(c, f"tar -xzf /tmp/ryadom56-admin.tar.gz -C {REMOTE}/admin && rm -f /tmp/ryadom56-admin.tar.gz")
    run(c, "ln -sfn /etc/nginx/sites-available/ryadom56 /etc/nginx/sites-enabled/ryadom56")
    run(c, "nginx -t && systemctl reload nginx")
    run(c, "systemctl daemon-reload && systemctl enable --now ryadom56 && systemctl restart ryadom56")
    time.sleep(5)
    run(c, "systemctl is-active ryadom56")
    run(c, f"journalctl -u ryadom56 -n 40 --no-pager || true")
    run(c, f"curl -sS http://127.0.0.1:{API_PORT}/api/health || true")
    run(c, f"curl -sS -o /dev/null -w '%{{http_code}}\\n' http://127.0.0.1:{HTTP_PORT}/ || true")
    run(c, f"curl -sS -o /dev/null -w '%{{http_code}}\\n' http://127.0.0.1:{HTTP_PORT}/api/health || true")
    # cloud providers sometimes need iptables
    run(c, f"iptables -C INPUT -p tcp --dport {HTTP_PORT} -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport {HTTP_PORT} -j ACCEPT || true")
    c.close()
    print("DONE")
    print(f"Site:  http://{HOST}:{HTTP_PORT}/")
    print(f"Admin: http://{HOST}:{HTTP_PORT}/console/")
    print(f"API:   http://{HOST}:{HTTP_PORT}/api/health")


if __name__ == "__main__":
    main()
