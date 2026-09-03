import http.client
import json
import os
import re
import shutil
import socket
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("PORT", "8787"))
DOCKER_SOCKET = os.environ.get("DOCKER_SOCKET", "/var/run/docker.sock")
APP_DATA_ROOT = Path(os.environ.get("UMBREL_APP_DATA_ROOT", "/umbrel-app-data"))
TARGET_APP_ID = os.environ.get("BAMBUDDY_APP_ID", "my3d-bambuddy")
TARGET_DIR = APP_DATA_ROOT / TARGET_APP_ID
TARGET_COMPOSE = TARGET_DIR / "docker-compose.yml"
TARGET_DATA = TARGET_DIR / "data"
MANAGER_DATA = Path(os.environ.get("MANAGER_DATA_DIR", "/manager-data"))
BACKUP_DIR = MANAGER_DATA / "backups"
STATE_FILE = MANAGER_DATA / "state.json"
CHANNEL_BASE = os.environ.get(
    "CHANNEL_BASE_URL",
    "https://raw.githubusercontent.com/MikeFox303/umbrel-3d-printing-store/main/channels/bambuddy",
).rstrip("/")
CONTAINER_NAME = os.environ.get("BAMBUDDY_CONTAINER_NAME", "my3d-bambuddy_server_1")
HEALTH_URL = os.environ.get("BAMBUDDY_HEALTH_URL", "http://host.docker.internal:8000/health")
ALLOW_SWITCHING = os.environ.get("ALLOW_SWITCHING", "true").lower() == "true"
IMAGE_RE = re.compile(r"ghcr\.io/maziggy/bambuddy:[^@\s]+@sha256:[0-9a-f]{64}")
STABLE_IMAGE_RE = re.compile(
    r"ghcr\.io/maziggy/bambuddy:[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?@sha256:[0-9a-f]{64}"
)
BETA_IMAGE_RE = re.compile(
    r"ghcr\.io/maziggy/bambuddy:daily@sha256:[0-9a-f]{64}"
)
LOCK = threading.Lock()

MANAGER_DATA.mkdir(parents=True, exist_ok=True)
BACKUP_DIR.mkdir(parents=True, exist_ok=True)


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, socket_path):
        super().__init__("localhost")
        self.socket_path = socket_path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.socket_path)


def docker_request(method, path, body=None, expected=(200, 201, 204, 304), raw=False):
    payload = None if body is None else json.dumps(body).encode()
    conn = UnixHTTPConnection(DOCKER_SOCKET)
    headers = {"Content-Type": "application/json"} if payload is not None else {}
    conn.request(method, f"/v1.43{path}", body=payload, headers=headers)
    response = conn.getresponse()
    data = response.read()
    status = response.status
    conn.close()
    if status not in expected:
        detail = data.decode(errors="replace")[:2000]
        raise RuntimeError(f"Docker API {method} {path} failed: HTTP {status}: {detail}")
    if not data:
        return None
    text = data.decode(errors="replace")
    if raw:
        return text
    return json.loads(text)


def inspect_container():
    return docker_request("GET", f"/containers/{urllib.parse.quote(CONTAINER_NAME, safe='')}/json")


def stop_container():
    docker_request(
        "POST",
        f"/containers/{urllib.parse.quote(CONTAINER_NAME, safe='')}/stop?t=30",
        expected=(204, 304),
    )


def start_container():
    docker_request(
        "POST",
        f"/containers/{urllib.parse.quote(CONTAINER_NAME, safe='')}/start",
        expected=(204, 304),
    )


def remove_container():
    docker_request(
        "DELETE",
        f"/containers/{urllib.parse.quote(CONTAINER_NAME, safe='')}?force=true",
        expected=(204,),
    )


def digest_pull_reference(image):
    if not IMAGE_RE.fullmatch(image):
        raise ValueError("Image is not an approved pinned Bambuddy reference")
    tagged, digest = image.rsplit("@", 1)
    slash = tagged.rfind("/")
    colon = tagged.rfind(":")
    repository = tagged[:colon] if colon > slash else tagged
    return f"{repository}@{digest}"


def pull_image(image):
    reference = digest_pull_reference(image)
    path = f"/images/create?fromImage={urllib.parse.quote(reference, safe='')}"
    result = docker_request("POST", path, expected=(200,), raw=True) or ""
    for line in result.splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if item.get("error"):
            raise RuntimeError(f"Docker pull failed: {item['error']}")


def create_clone(previous, image):
    config = previous.get("Config") or {}
    host = previous.get("HostConfig") or {}
    allowed_host = (
        "Binds",
        "NetworkMode",
        "RestartPolicy",
        "AutoRemove",
        "CapAdd",
        "CapDrop",
        "Dns",
        "DnsOptions",
        "DnsSearch",
        "ExtraHosts",
        "GroupAdd",
        "IpcMode",
        "PidMode",
        "Privileged",
        "ReadonlyRootfs",
        "SecurityOpt",
        "ShmSize",
        "Tmpfs",
        "Ulimits",
        "Devices",
        "LogConfig",
        "Init",
    )
    host_config = {
        key: host[key] for key in allowed_host if key in host and host[key] is not None
    }
    body = {
        "Hostname": config.get("Hostname", ""),
        "Domainname": config.get("Domainname", ""),
        "User": config.get("User", ""),
        "AttachStdin": False,
        "AttachStdout": False,
        "AttachStderr": False,
        "Tty": False,
        "OpenStdin": False,
        "StdinOnce": False,
        "Env": config.get("Env") or [],
        "Cmd": config.get("Cmd"),
        "Image": image,
        "Volumes": config.get("Volumes"),
        "ExposedPorts": config.get("ExposedPorts"),
        "Healthcheck": config.get("Healthcheck"),
        "WorkingDir": config.get("WorkingDir", ""),
        "Entrypoint": config.get("Entrypoint"),
        "Labels": config.get("Labels") or {},
        "StopSignal": config.get("StopSignal"),
        "StopTimeout": config.get("StopTimeout"),
        "HostConfig": host_config,
    }
    docker_request(
        "POST",
        f"/containers/create?name={urllib.parse.quote(CONTAINER_NAME, safe='')}",
        body=body,
        expected=(201,),
    )


def wait_for_health(timeout=120):
    deadline = time.time() + timeout
    last_error = ""
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(HEALTH_URL, timeout=3) as response:
                if 200 <= response.status < 300:
                    return
        except Exception as exc:
            last_error = str(exc)
        time.sleep(2)
    raise RuntimeError(f"Bambuddy did not become healthy within {timeout}s: {last_error}")


def read_compose_image():
    text = TARGET_COMPOSE.read_text()
    match = IMAGE_RE.search(text)
    if not match:
        raise RuntimeError(
            "Pinned official Bambuddy image not found in installed docker-compose.yml"
        )
    return match.group(0)


def write_compose_image(image):
    if not IMAGE_RE.fullmatch(image):
        raise ValueError("Target image is not a pinned official Bambuddy image")
    text = TARGET_COMPOSE.read_text()
    next_text, count = IMAGE_RE.subn(image, text, count=1)
    if count != 1:
        raise RuntimeError("Could not update installed Bambuddy image pin")
    TARGET_COMPOSE.write_text(next_text)


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Bambuddy-Manager/0.1"})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


def get_channels():
    channels = {}
    for name in ("stable", "beta"):
        cache = MANAGER_DATA / f"{name}.json"
        try:
            data = fetch_json(f"{CHANNEL_BASE}/{name}.json")
            cache.write_text(json.dumps(data, indent=2) + "\n")
        except Exception:
            if cache.exists():
                data = json.loads(cache.read_text())
            else:
                data = {"channel": name, "available": False}
        channels[name] = data
    return channels


def load_state():
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def save_state(state):
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2) + "\n")
    tmp.replace(STATE_FILE)


def channel_for_image(image, channels):
    for name, meta in channels.items():
        if meta.get("immutableImage") == image:
            return name
    # Channel metadata always points at the newest approved digest. A machine
    # can legitimately still be running an older approved Stable or Daily
    # digest, so infer the channel from the immutable reference shape too.
    if STABLE_IMAGE_RE.fullmatch(image):
        return "stable"
    if BETA_IMAGE_RE.fullmatch(image):
        return "beta"
    return "custom"


def copy_sqlite_snapshot(snapshot_dir):
    snapshot_dir.mkdir(parents=True, exist_ok=False)
    copied = []
    for name in ("bambuddy.db", "bambuddy.db-wal", "bambuddy.db-shm"):
        src = TARGET_DATA / name
        if src.exists():
            shutil.copy2(src, snapshot_dir / name)
            copied.append(name)
    if "bambuddy.db" not in copied:
        raise RuntimeError(f"{TARGET_DATA / 'bambuddy.db'} does not exist")
    shutil.copy2(TARGET_COMPOSE, snapshot_dir / "docker-compose.yml")
    return copied


def restore_sqlite_snapshot(snapshot_dir):
    db = snapshot_dir / "bambuddy.db"
    if not db.exists():
        raise RuntimeError(f"Snapshot is missing {db}")
    TARGET_DATA.mkdir(parents=True, exist_ok=True)
    for name in ("bambuddy.db", "bambuddy.db-wal", "bambuddy.db-shm"):
        target = TARGET_DATA / name
        if target.exists():
            target.unlink()
        source = snapshot_dir / name
        if source.exists():
            shutil.copy2(source, target)
    compose = snapshot_dir / "docker-compose.yml"
    if compose.exists():
        shutil.copy2(compose, TARGET_COMPOSE)


def make_snapshot(current_image, current_channel):
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    snapshot_dir = BACKUP_DIR / f"{stamp}-{current_channel}"
    copied = copy_sqlite_snapshot(snapshot_dir)
    manifest = {
        "createdAt": stamp,
        "channel": current_channel,
        "image": current_image,
        "files": copied,
    }
    (snapshot_dir / "snapshot.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return snapshot_dir


def switch_channel(target_channel):
    if target_channel not in ("stable", "beta"):
        raise ValueError("channel must be stable or beta")
    if not ALLOW_SWITCHING:
        raise RuntimeError("Channel switching is disabled by configuration")

    with LOCK:
        channels = get_channels()
        target = channels[target_channel]
        target_image = target.get("immutableImage")
        if not target.get("available") or not target_image:
            raise RuntimeError(f"{target_channel} channel is not available yet")
        if not IMAGE_RE.fullmatch(target_image):
            raise RuntimeError(
                "Channel metadata does not contain an approved immutable Bambuddy image"
            )

        current_image = read_compose_image()
        current_channel = channel_for_image(current_image, channels)
        if current_image == target_image:
            return {"changed": False, "channel": target_channel, "image": target_image}

        previous = inspect_container()
        state = load_state()
        snapshot_dir = None

        try:
            stop_container()
            snapshot_dir = make_snapshot(current_image, current_channel)

            if current_channel == "stable":
                state["stableSnapshot"] = str(snapshot_dir)
                state["stableImage"] = current_image

            if target_channel == "stable" and current_channel == "beta":
                stable_snapshot = state.get("stableSnapshot")
                if not stable_snapshot or not Path(stable_snapshot).exists():
                    raise RuntimeError(
                        "Safe Beta -> Stable switch requires the Stable snapshot created when Beta was entered"
                    )
                restore_sqlite_snapshot(Path(stable_snapshot))

            pull_image(target_image)
            write_compose_image(target_image)
            remove_container()
            create_clone(previous, target_image)
            start_container()
            wait_for_health()

            state.update(
                {
                    "currentChannel": target_channel,
                    "currentImage": target_image,
                    "previousChannel": current_channel,
                    "previousImage": current_image,
                    "lastSnapshot": str(snapshot_dir),
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                }
            )
            save_state(state)
            return {
                "changed": True,
                "channel": target_channel,
                "image": target_image,
                "snapshot": str(snapshot_dir),
            }
        except Exception:
            try:
                try:
                    inspect_container()
                    stop_container()
                    remove_container()
                except Exception:
                    pass
                if snapshot_dir and snapshot_dir.exists():
                    restore_sqlite_snapshot(snapshot_dir)
                write_compose_image(current_image)
                pull_image(current_image)
                create_clone(previous, current_image)
                start_container()
                wait_for_health(90)
            except Exception as rollback_error:
                raise RuntimeError(
                    "Switch failed and automatic rollback also failed; manual recovery is required: "
                    + str(rollback_error)
                )
            raise


def status():
    channels = get_channels()
    current_image = read_compose_image()
    try:
        container = inspect_container()
        running = bool(container.get("State", {}).get("Running"))
    except Exception:
        running = False
    current_channel = channel_for_image(current_image, channels)
    state = load_state()
    return {
        "managerVersion": "0.1.0",
        "switchingEnabled": ALLOW_SWITCHING,
        "current": {
            "channel": current_channel,
            "image": current_image,
            "running": running,
        },
        "channels": channels,
        "rollback": {
            "stableSnapshotAvailable": bool(
                state.get("stableSnapshot") and Path(state["stableSnapshot"]).exists()
            ),
            "lastSnapshot": state.get("lastSnapshot"),
        },
    }


INDEX = r'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bambuddy Manager</title>
<style>
:root{color-scheme:dark;font-family:Inter,system-ui,sans-serif;background:#10151b;color:#eef4fb}
body{margin:0;padding:24px}main{max-width:780px;margin:auto}.card{background:#1b232c;border:1px solid #34404c;border-radius:16px;padding:20px;margin:14px 0}
h1{margin:0 0 6px}h2{font-size:17px}.muted{color:#9bb0c5}.row{display:flex;gap:12px;flex-wrap:wrap;align-items:center}.pill{padding:6px 10px;border-radius:999px;background:#26313c}
button{border:0;border-radius:10px;padding:11px 16px;font-weight:700;cursor:pointer}button.primary{background:#18c76f;color:#07140c}button.warn{background:#e6a23c;color:#171006}
button:disabled{opacity:.45;cursor:not-allowed}code{word-break:break-all;color:#b8d7f3}.error{color:#ff8f8f}.ok{color:#5ee69c}
</style>
</head>
<body><main>
<h1>Bambuddy Manager</h1><div class="muted">Stable / Beta channel management for Umbrel</div>
<div class="card"><h2>Текущая установка</h2><div id="current">Загрузка…</div></div>
<div class="card"><h2>Каналы</h2><div id="channels"></div></div>
<div class="card"><h2>Безопасность</h2><div id="safety" class="muted"></div></div>
<div id="message"></div>
</main>
<script>
let state;
async function load(){
  const r=await fetch('/api/status'); state=await r.json();
  if(!r.ok) throw new Error(state.error||'Ошибка');
  const c=state.current;
  document.querySelector('#current').innerHTML=`<div class="row"><span class="pill">${c.channel}</span><span>${c.running?'🟢 запущен':'🔴 остановлен'}</span></div><p><code>${c.image}</code></p>`;
  const root=document.querySelector('#channels'); root.innerHTML='';
  for(const name of ['stable','beta']){
    const m=state.channels[name]||{}; const disabled=!state.switchingEnabled||!m.available||m.immutableImage===c.image;
    const beta=name==='beta';
    root.innerHTML+=`<div style="margin:14px 0"><b>${beta?'Beta / Daily':'Stable'}</b> — ${m.version||'недоступен'}<br><span class="muted">${m.available?'проверен Store':'ещё не опубликован'}</span><br><button class="${beta?'warn':'primary'}" ${disabled?'disabled':''} onclick="switchTo('${name}')">${beta?'Перейти на Beta':'Перейти на Stable'}</button></div>`;
  }
  document.querySelector('#safety').textContent=state.rollback.stableSnapshotAvailable?'Есть Stable snapshot для безопасного возврата из Beta.':'Stable snapshot будет создан автоматически перед переходом на Beta.';
}
async function switchTo(channel){
  const warning=channel==='beta'?'Перед переходом будет остановлен Bambuddy и создан snapshot базы. Продолжить?':'При возврате из Beta будет восстановлен Stable snapshot. Данные, созданные только в Beta после перехода, не попадут в Stable. Продолжить?';
  if(!confirm(warning)) return;
  const box=document.querySelector('#message'); box.innerHTML='<div class="card">Выполняется переключение…</div>';
  try{
    const r=await fetch('/api/switch',{method:'POST',headers:{'Content-Type':'application/json','X-Bambuddy-Manager':'1'},body:JSON.stringify({channel})});
    const data=await r.json(); if(!r.ok) throw new Error(data.error||'Ошибка');
    box.innerHTML='<div class="card ok">Готово. Bambuddy прошёл health-check.</div>'; await load();
  }catch(e){box.innerHTML=`<div class="card error">${e.message}</div>`}
}
load().catch(e=>document.querySelector('#current').textContent=e.message);
</script></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, data):
        payload = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/":
            payload = INDEX.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path == "/health":
            self._json(200, {"status": "ok"})
            return
        if self.path == "/api/status":
            try:
                self._json(200, status())
            except Exception as exc:
                self._json(500, {"error": str(exc)})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.headers.get("X-Bambuddy-Manager") != "1":
            self._json(403, {"error": "missing manager request header"})
            return
        if self.path != "/api/switch":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 4096:
                raise ValueError("request too large")
            body = json.loads(self.rfile.read(length) or b"{}")
            self._json(200, switch_channel(body.get("channel")))
        except ValueError as exc:
            self._json(400, {"error": str(exc)})
        except Exception as exc:
            self._json(500, {"error": str(exc)})

    def log_message(self, fmt, *args):
        print(f"[http] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Bambuddy Manager listening on 0.0.0.0:{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
