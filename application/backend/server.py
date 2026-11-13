#!/usr/bin/env python3
"""Backend do EC2 Server Dashboard.

Usa somente a biblioteca padrao do Python (sem pip). Escuta apenas em
127.0.0.1:8000: quem recebe o trafego publico (porta 80) e o Nginx, que
repassa as chamadas /api/ para este processo.
"""
import json
import os
import platform
import shutil
import socket
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8000
IMDS = "http://169.254.169.254/latest"

_metadata_cache = {"expires": 0.0, "data": {}}
_cpu_last = {"total": None, "idle": None}


def _imds_get(path, token):
    request = urllib.request.Request(
        f"{IMDS}/{path}", headers={"X-aws-ec2-metadata-token": token}
    )
    with urllib.request.urlopen(request, timeout=1) as response:
        return response.read().decode().strip()


def instance_metadata():
    """Le metadados da instancia via IMDSv2 (token obrigatorio). Cache de 5 min."""
    now = time.time()
    if now < _metadata_cache["expires"]:
        return _metadata_cache["data"]

    fields = {
        "instance_id": "meta-data/instance-id",
        "instance_type": "meta-data/instance-type",
        "availability_zone": "meta-data/placement/availability-zone",
        "private_ip": "meta-data/local-ipv4",
        "public_ip": "meta-data/public-ipv4",
        "ami_id": "meta-data/ami-id",
    }
    data = {}
    try:
        token_request = urllib.request.Request(
            f"{IMDS}/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        with urllib.request.urlopen(token_request, timeout=1) as response:
            token = response.read().decode()
        for name, path in fields.items():
            try:
                data[name] = _imds_get(path, token)
            except Exception:
                data[name] = None
    except Exception:
        data = {name: None for name in fields}

    _metadata_cache.update(expires=now + 300, data=data)
    return data


def memory():
    values = {}
    with open("/proc/meminfo", encoding="ascii") as handle:
        for line in handle:
            key, _, rest = line.partition(":")
            values[key] = int(rest.split()[0]) * 1024
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    used = total - available
    return {
        "total_bytes": total,
        "used_bytes": used,
        "used_percent": round(used * 100 / total, 1) if total else 0.0,
    }


def cpu_percent():
    """Uso de CPU entre duas leituras consecutivas de /proc/stat."""
    with open("/proc/stat", encoding="ascii") as handle:
        fields = [int(v) for v in handle.readline().split()[1:]]
    idle = fields[3] + fields[4]
    total = sum(fields)
    last_total, last_idle = _cpu_last["total"], _cpu_last["idle"]
    _cpu_last.update(total=total, idle=idle)
    if last_total is None or total == last_total:
        return 0.0
    busy = (total - last_total) - (idle - last_idle)
    return round(busy * 100 / (total - last_total), 1)


def disk():
    usage = shutil.disk_usage("/")
    return {
        "total_bytes": usage.total,
        "used_bytes": usage.used,
        "used_percent": round(usage.used * 100 / usage.total, 1),
    }


def os_name():
    try:
        with open("/etc/os-release", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return platform.system()


def status():
    with open("/proc/uptime", encoding="ascii") as handle:
        uptime = float(handle.read().split()[0])
    load1, load5, load15 = os.getloadavg()
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "hostname": socket.gethostname(),
        "os": os_name(),
        "kernel": platform.release(),
        "architecture": platform.machine(),
        "python": platform.python_version(),
        "uptime_seconds": int(uptime),
        "cpu_count": os.cpu_count(),
        "cpu_percent": cpu_percent(),
        "load_average": {"1m": load1, "5m": load5, "15m": load15},
        "memory": memory(),
        "disk": disk(),
        "instance": instance_metadata(),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "EC2Dashboard"
    sys_version = ""

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _route(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/status":
            self._send(200, status())
        elif path == "/api/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not_found"})

    do_GET = _route
    do_HEAD = _route


if __name__ == "__main__":
    cpu_percent()  # primeira leitura serve de referencia
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
