"""Pull latest main on VPS and restart API. Does not purge DB demo data."""
from __future__ import annotations

import os
import sys
import time

import paramiko

HOST = "155.212.174.201"
PASS = os.environ.get("RYADOM_SSH_PASS") or (sys.argv[1] if len(sys.argv) > 1 else "")
if not PASS:
    raise SystemExit("Set RYADOM_SSH_PASS or pass password as argv[1]")
REMOTE = "/opt/ryadom56"


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 300) -> str:
    print(">", cmd[:180])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = (out + ("\n" + err if err.strip() else "")).encode("ascii", "replace").decode()
    if text.strip():
        print(text[-3000:])
    if code != 0:
        raise SystemExit(f"fail {code}: {cmd}")
    return out


def main() -> None:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)

    run(c, f"cd {REMOTE} && git fetch --depth 1 origin main && git reset --hard origin/main && git log -1 --oneline")
    run(c, f"{REMOTE}/venv/bin/pip install -q -r {REMOTE}/backend/requirements.txt")
    run(
        c,
        f"grep -q '^SEED_DEMO_CONTENT=' {REMOTE}/backend/.env && "
        f"sed -i 's/^SEED_DEMO_CONTENT=.*/SEED_DEMO_CONTENT=false/' {REMOTE}/backend/.env || "
        f"echo 'SEED_DEMO_CONTENT=false' >> {REMOTE}/backend/.env",
    )
    # Keep nginx body size at 100m if config exists
    run(
        c,
        "grep -q 'client_max_body_size' /etc/nginx/sites-available/ryadom56 && "
        "sed -i 's/client_max_body_size.*/client_max_body_size 100m;/' /etc/nginx/sites-available/ryadom56 || true",
    )
    run(c, "nginx -t && systemctl reload nginx")
    run(c, "systemctl restart ryadom56")
    time.sleep(4)
    run(c, "systemctl is-active ryadom56")
    run(c, "curl -sS http://127.0.0.1:8080/api/health")
    run(c, "curl -sS -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:8080/")
    c.close()
    print("DONE")


if __name__ == "__main__":
    main()
