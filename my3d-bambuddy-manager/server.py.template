import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import sqlite3
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MANAGER_VERSION = "0.2.0"
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
MAX_SNAPSHOTS = max(3, int(os.environ.get("MAX_SNAPSHOTS", "12")))

DIGEST_RE = re.compile(r"sha256:[0-9a-f]{64}")
IMAGE_RE = re.compile(r"ghcr\.io/maziggy/bambuddy:[^@\s]+@sha256:[0-9a-f]{64}")
STABLE_VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?")
BETA_VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+b[0-9]+-daily\.[0-9]{8}")
STABLE_IMAGE_RE = re.compile(
    r"ghcr\.io/maziggy/bambuddy:[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?@sha256:[0-9a-f]{64}"
)
BETA_IMAGE_RE = re.compile(r"ghcr\.io/maziggy/bambuddy:daily@sha256:[0-9a-f]{64}")
SQLITE_DATABASES = ("bambuddy.db", "bambutrack.db")
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
    status_code = response.status
    conn.close()
    if status_code not in expected:
        detail = data.decode(errors="replace")[:2000]
        raise RuntimeError(f"Docker API {method} {path} failed: HTTP {status_code}: {detail}")
    if not data:
        return None
    text = data.decode(errors="replace")
    if raw:
        return text
    return json.loads(text)


def inspect_container():
    return docker_request("GET", f"/containers/{urllib.parse.quote(CONTAINER_NAME, safe='')}/json")


def container_exists():
    try:
        inspect_container()
        return True
    except Exception:
        return False


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


def _server_section_lines():
    lines = TARGET_COMPOSE.read_text(encoding="utf-8").splitlines()
    start = None
    for index, line in enumerate(lines):
        if re.fullmatch(r"\s{2}server:\s*", line):
            start = index + 1
            break
    if start is None:
        raise RuntimeError("server service not found in installed docker-compose.yml")
    section = []
    for line in lines[start:]:
        if re.match(r"^\s{2}\S", line):
            break
        section.append(line)
    return section


def compose_environment_keys():
    section = _server_section_lines()
    env_index = None
    for index, line in enumerate(section):
        if re.fullmatch(r"\s{4}environment:\s*", line):
            env_index = index + 1
            break
    if env_index is None:
        return []
    keys = []
    for line in section[env_index:]:
        if re.match(r"^\s{4}\S", line):
            break
        mapping = re.match(r"^\s{6}([A-Za-z_][A-Za-z0-9_]*):(?:\s|$)", line)
        if mapping:
            keys.append(mapping.group(1))
            continue
        listed = re.match(r"^\s{6}-\s*([A-Za-z_][A-Za-z0-9_]*)(?:=|$)", line)
        if listed:
            keys.append(listed.group(1))
    return keys


def validate_supported_compose():
    section = _server_section_lines()
    unsupported = []
    for line in section:
        match = re.match(
            r"^\s{4}(command|entrypoint|user|working_dir|hostname|domainname|healthcheck):",
            line,
        )
        if match:
            unsupported.append(match.group(1))
    if unsupported:
        unique = ", ".join(sorted(set(unsupported)))
        raise RuntimeError(
            "Installed Bambuddy compose contains service overrides that Manager 0.2 "
            f"cannot safely preserve yet: {unique}"
        )


def _env_map(items):
    values = {}
    for item in items or []:
        if "=" in item:
            key, value = item.split("=", 1)
            values[key] = value
    return values


def build_clone_spec(previous):
    validate_supported_compose()
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
        "PortBindings",
        "Sysctls",
        "Runtime",
        "CgroupnsMode",
    )
    host_config = {
        key: host[key] for key in allowed_host if key in host and host[key] is not None
    }
    all_env = _env_map(config.get("Env"))
    env = [
        f"{key}={all_env[key]}"
        for key in compose_environment_keys()
        if key in all_env
    ]
    return {
        "Env": env,
        "Labels": config.get("Labels") or {},
        "HostConfig": host_config,
    }


def create_clone_from_spec(spec, image):
    if not IMAGE_RE.fullmatch(image):
        raise ValueError("Target image is not a pinned official Bambuddy image")
    body = {
        "Image": image,
        "Env": spec.get("Env") or [],
        "Labels": spec.get("Labels") or {},
        "HostConfig": spec.get("HostConfig") or {},
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


def verify_running_image(expected_image):
    container = inspect_container()
    if not container.get("State", {}).get("Running"):
        raise RuntimeError("Bambuddy container is not running after start")
    actual = (container.get("Config") or {}).get("Image")
    if actual != expected_image:
        raise RuntimeError(f"Running Bambuddy image mismatch: expected {expected_image}, got {actual}")


def read_compose_image():
    text = TARGET_COMPOSE.read_text(encoding="utf-8")
    match = IMAGE_RE.search(text)
    if not match:
        raise RuntimeError("Pinned official Bambuddy image not found in installed docker-compose.yml")
    return match.group(0)


def write_compose_image(image):
    if not IMAGE_RE.fullmatch(image):
        raise ValueError("Target image is not a pinned official Bambuddy image")
    text = TARGET_COMPOSE.read_text(encoding="utf-8")
    next_text, count = IMAGE_RE.subn(image, text, count=1)
    if count != 1:
        raise RuntimeError("Could not update installed Bambuddy image pin")
    tmp = TARGET_COMPOSE.with_suffix(".manager.tmp")
    tmp.write_text(next_text, encoding="utf-8")
    tmp.replace(TARGET_COMPOSE)


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": f"Bambuddy-Manager/{MANAGER_VERSION}"})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


def validate_channel_metadata(name, data):
    if not isinstance(data, dict):
        raise ValueError(f"{name} channel metadata is not an object")
    if data.get("schemaVersion") != 1 or data.get("channel") != name:
        raise ValueError(f"{name} channel metadata identity is invalid")
    if not data.get("available"):
        return data
    image = data.get("immutableImage")
    digest = data.get("digest")
    version = data.get("version")
    platforms = data.get("testedPlatforms") or []
    if not isinstance(image, str) or not isinstance(digest, str) or not isinstance(version, str):
        raise ValueError(f"{name} channel metadata is incomplete")
    if not DIGEST_RE.fullmatch(digest) or not image.endswith(f"@{digest}"):
        raise ValueError(f"{name} channel digest does not match immutable image")
    if not {"linux/amd64", "linux/arm64"}.issubset(set(platforms)):
        raise ValueError(f"{name} channel is not validated on amd64 and arm64")
    if name == "stable":
        if not STABLE_VERSION_RE.fullmatch(version) or not STABLE_IMAGE_RE.fullmatch(image):
            raise ValueError("Stable channel does not contain a stable pinned Bambuddy image")
        if not image.startswith(f"ghcr.io/maziggy/bambuddy:{version}@"):
            raise ValueError("Stable channel version and image tag do not match")
    else:
        if not BETA_VERSION_RE.fullmatch(version) or not BETA_IMAGE_RE.fullmatch(image):
            raise ValueError("Beta channel does not contain a daily pinned Bambuddy image")
    return data


def get_channels():
    channels = {}
    for name in ("stable", "beta"):
        cache = MANAGER_DATA / f"{name}.json"
        remote_error = None
        try:
            data = validate_channel_metadata(name, fetch_json(f"{CHANNEL_BASE}/{name}.json"))
            cache.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        except Exception as exc:
            remote_error = str(exc)
            try:
                data = validate_channel_metadata(name, json.loads(cache.read_text(encoding="utf-8")))
                data = dict(data)
                data["stale"] = True
                data["warning"] = f"Using cached channel metadata: {remote_error}"
            except Exception:
                data = {
                    "schemaVersion": 1,
                    "channel": name,
                    "available": False,
                    "error": remote_error or "Channel metadata unavailable",
                }
        channels[name] = data
    return channels


def load_state():
    if not STATE_FILE.exists():
        return {}
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(state):
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    tmp.replace(STATE_FILE)


def channel_for_image(image, channels):
    for name, meta in channels.items():
        if meta.get("immutableImage") == image:
            return name
    if STABLE_IMAGE_RE.fullmatch(image):
        return "stable"
    if BETA_IMAGE_RE.fullmatch(image):
        return "beta"
    return "custom"


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def _sqlite_backup(source, destination):
    source_uri = f"file:{urllib.parse.quote(str(source), safe='/')}?mode=ro"
    with sqlite3.connect(source_uri, uri=True, timeout=10) as src:
        with sqlite3.connect(destination, timeout=10) as dst:
            src.backup(dst)
            result = dst.execute("PRAGMA integrity_check").fetchone()
            if not result or result[0] != "ok":
                raise RuntimeError(f"SQLite integrity_check failed for {source.name}: {result}")


def make_snapshot(current_image, current_channel):
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    snapshot_dir = BACKUP_DIR / f"{stamp}-{current_channel}"
    snapshot_dir.mkdir(parents=True, exist_ok=False)

    databases = {}
    for name in SQLITE_DATABASES:
        source = TARGET_DATA / name
        if not source.exists():
            continue
        destination = snapshot_dir / name
        stat = source.stat()
        _sqlite_backup(source, destination)
        os.chmod(destination, stat.st_mode & 0o777)
        databases[name] = {
            "sha256": _sha256(destination),
            "uid": stat.st_uid,
            "gid": stat.st_gid,
            "mode": stat.st_mode & 0o777,
        }

    if not databases:
        shutil.rmtree(snapshot_dir, ignore_errors=True)
        raise RuntimeError(f"No supported Bambuddy SQLite database found in {TARGET_DATA}")

    shutil.copy2(TARGET_COMPOSE, snapshot_dir / "docker-compose.yml")
    manifest = {
        "schemaVersion": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "channel": current_channel,
        "image": current_image,
        "databases": databases,
        "composeSha256": _sha256(snapshot_dir / "docker-compose.yml"),
    }
    (snapshot_dir / "snapshot.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return snapshot_dir


def _snapshot_path(value):
    if not value:
        raise RuntimeError("Snapshot path is missing")
    path = Path(value).resolve()
    root = BACKUP_DIR.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise RuntimeError("Snapshot path escapes Manager backup directory") from exc
    if not path.is_dir():
        raise RuntimeError(f"Snapshot does not exist: {path}")
    return path


def load_snapshot_manifest(snapshot_dir):
    snapshot_dir = _snapshot_path(snapshot_dir)
    manifest_path = snapshot_dir / "snapshot.json"
    if not manifest_path.exists():
        raise RuntimeError(f"Snapshot manifest is missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1:
        raise RuntimeError("Unsupported snapshot schema")
    image = manifest.get("image")
    if not isinstance(image, str) or not IMAGE_RE.fullmatch(image):
        raise RuntimeError("Snapshot contains an invalid Bambuddy image")
    databases = manifest.get("databases")
    if not isinstance(databases, dict) or not databases:
        raise RuntimeError("Snapshot does not contain database metadata")

    compose = snapshot_dir / "docker-compose.yml"
    if not compose.exists() or _sha256(compose) != manifest.get("composeSha256"):
        raise RuntimeError("Snapshot compose checksum verification failed")

    for name, metadata in databases.items():
        if name not in SQLITE_DATABASES or not isinstance(metadata, dict):
            raise RuntimeError("Snapshot contains an unsupported database")
        source = snapshot_dir / name
        if not source.exists() or _sha256(source) != metadata.get("sha256"):
            raise RuntimeError(f"Snapshot checksum verification failed for {name}")
        with sqlite3.connect(source) as db:
            result = db.execute("PRAGMA integrity_check").fetchone()
            if not result or result[0] != "ok":
                raise RuntimeError(f"Snapshot integrity_check failed for {name}: {result}")
    return manifest


def restore_snapshot(snapshot_dir):
    snapshot_dir = _snapshot_path(snapshot_dir)
    manifest = load_snapshot_manifest(snapshot_dir)
    TARGET_DATA.mkdir(parents=True, exist_ok=True)

    for name in SQLITE_DATABASES:
        for suffix in ("", "-wal", "-shm", "-journal"):
            target = TARGET_DATA / f"{name}{suffix}"
            if target.exists():
                target.unlink()

    for name, metadata in manifest["databases"].items():
        source = snapshot_dir / name
        target = TARGET_DATA / name
        shutil.copy2(source, target)
        try:
            os.chown(target, int(metadata.get("uid", -1)), int(metadata.get("gid", -1)))
        except (PermissionError, OSError, ValueError):
            pass
        try:
            os.chmod(target, int(metadata.get("mode", 0o664)))
        except (PermissionError, OSError, ValueError):
            pass

    shutil.copy2(snapshot_dir / "docker-compose.yml", TARGET_COMPOSE)
    return manifest


def _referenced_snapshots(state):
    refs = set()
    for key in ("stableSnapshot", "lastSnapshot"):
        value = state.get(key)
        if value:
            try:
                refs.add(str(_snapshot_path(value)))
            except Exception:
                pass
    pending = state.get("pending")
    if isinstance(pending, dict) and pending.get("snapshot"):
        try:
            refs.add(str(_snapshot_path(pending["snapshot"])))
        except Exception:
            pass
    return refs


def prune_snapshots(state):
    refs = _referenced_snapshots(state)
    snapshots = sorted(
        [item for item in BACKUP_DIR.iterdir() if item.is_dir()],
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    kept = 0
    for snapshot in snapshots:
        if str(snapshot.resolve()) in refs:
            continue
        kept += 1
        if kept > MAX_SNAPSHOTS:
            shutil.rmtree(snapshot, ignore_errors=True)


def _prepare_pending(
    state,
    operation,
    current_image,
    current_channel,
    target_image,
    target_channel,
    snapshot,
    clone_spec,
):
    pending = {
        "operation": operation,
        "fromImage": current_image,
        "fromChannel": current_channel,
        "targetImage": target_image,
        "targetChannel": target_channel,
        "snapshot": str(snapshot),
        "cloneSpec": clone_spec,
        "startedAt": datetime.now(timezone.utc).isoformat(),
    }
    state["pending"] = pending
    state["lastSnapshot"] = str(snapshot)
    save_state(state)
    return pending


def _replace_runtime(clone_spec, target_image):
    pull_image(target_image)
    write_compose_image(target_image)
    if container_exists():
        try:
            stop_container()
        except Exception:
            pass
        remove_container()
    create_clone_from_spec(clone_spec, target_image)
    start_container()
    wait_for_health()
    verify_running_image(target_image)


def _rollback_transaction(state, pending):
    snapshot = _snapshot_path(pending.get("snapshot"))
    manifest = restore_snapshot(snapshot)
    rollback_image = pending.get("fromImage") or manifest.get("image")
    if rollback_image != manifest.get("image"):
        raise RuntimeError("Pending transaction image does not match rollback snapshot")
    clone_spec = pending.get("cloneSpec")
    if not isinstance(clone_spec, dict):
        raise RuntimeError("Pending transaction is missing container recreation metadata")
    _replace_runtime(clone_spec, rollback_image)
    state.pop("pending", None)
    state["currentChannel"] = pending.get("fromChannel")
    state["currentImage"] = rollback_image
    state["updatedAt"] = datetime.now(timezone.utc).isoformat()
    save_state(state)
    return rollback_image


def switch_channel(target_channel):
    if target_channel not in ("stable", "beta"):
        raise ValueError("channel must be stable or beta")
    if not ALLOW_SWITCHING:
        raise RuntimeError("Channel switching is disabled by configuration")

    with LOCK:
        state = load_state()
        if state.get("pending"):
            raise RuntimeError(
                "An unfinished Manager transaction exists. Recover it before starting another switch."
            )

        channels = get_channels()
        target = validate_channel_metadata(target_channel, channels[target_channel])
        target_image = target.get("immutableImage")
        if not target.get("available") or not target_image:
            raise RuntimeError(f"{target_channel} channel is not available yet")
        expected_pattern = STABLE_IMAGE_RE if target_channel == "stable" else BETA_IMAGE_RE
        if not expected_pattern.fullmatch(target_image):
            raise RuntimeError(f"{target_channel} channel image does not match its channel policy")

        current_image = read_compose_image()
        current_channel = channel_for_image(current_image, channels)
        if current_image == target_image:
            return {"changed": False, "channel": target_channel, "image": target_image}

        previous = inspect_container()
        clone_spec = build_clone_spec(previous)
        snapshot_dir = None
        pending = None

        try:
            stop_container()
            snapshot_dir = make_snapshot(current_image, current_channel)

            if current_channel == "stable" and target_channel == "beta":
                state["stableSnapshot"] = str(snapshot_dir)
                state["stableImage"] = current_image

            pending = _prepare_pending(
                state,
                "switch",
                current_image,
                current_channel,
                target_image,
                target_channel,
                snapshot_dir,
                clone_spec,
            )

            if target_channel == "stable" and current_channel == "beta":
                stable_snapshot = _snapshot_path(state.get("stableSnapshot"))
                restore_snapshot(stable_snapshot)

            _replace_runtime(clone_spec, target_image)

            state.pop("pending", None)
            if target_channel == "stable" and current_channel == "beta":
                state.pop("stableSnapshot", None)
                state.pop("stableImage", None)
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
            prune_snapshots(state)
            return {
                "changed": True,
                "channel": target_channel,
                "image": target_image,
                "snapshot": str(snapshot_dir),
            }
        except Exception as exc:
            if pending:
                try:
                    _rollback_transaction(state, pending)
                except Exception as rollback_error:
                    raise RuntimeError(
                        "Switch failed and automatic rollback also failed; use recovery controls: "
                        f"{rollback_error}"
                    ) from exc
            else:
                try:
                    if not container_exists():
                        create_clone_from_spec(clone_spec, current_image)
                    start_container()
                except Exception:
                    pass
            raise


def rollback_last_snapshot():
    if not ALLOW_SWITCHING:
        raise RuntimeError("Rollback is disabled by configuration")

    with LOCK:
        state = load_state()
        if state.get("pending"):
            raise RuntimeError("Recover the unfinished transaction before manual rollback")

        target_snapshot = _snapshot_path(state.get("lastSnapshot"))
        target_manifest = load_snapshot_manifest(target_snapshot)
        target_image = target_manifest["image"]
        channels = get_channels()
        target_channel = channel_for_image(target_image, channels)

        current_image = read_compose_image()
        current_channel = channel_for_image(current_image, channels)
        if current_image == target_image:
            raise RuntimeError("Last snapshot already matches the current runtime")

        previous = inspect_container()
        clone_spec = build_clone_spec(previous)
        stop_container()
        safety_snapshot = make_snapshot(current_image, current_channel)

        pending = _prepare_pending(
            state,
            "manual-rollback",
            current_image,
            current_channel,
            target_image,
            target_channel,
            safety_snapshot,
            clone_spec,
        )

        try:
            restore_snapshot(target_snapshot)
            _replace_runtime(clone_spec, target_image)

            state.pop("pending", None)
            if target_channel == "beta" and current_channel == "stable":
                state["stableSnapshot"] = str(safety_snapshot)
                state["stableImage"] = current_image
            elif target_channel == "stable":
                state.pop("stableSnapshot", None)
                state.pop("stableImage", None)
            state.update(
                {
                    "currentChannel": target_channel,
                    "currentImage": target_image,
                    "previousChannel": current_channel,
                    "previousImage": current_image,
                    "lastSnapshot": str(safety_snapshot),
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                }
            )
            save_state(state)
            prune_snapshots(state)
            return {
                "changed": True,
                "channel": target_channel,
                "image": target_image,
                "rollbackSnapshot": str(target_snapshot),
                "reverseSnapshot": str(safety_snapshot),
            }
        except Exception as exc:
            try:
                _rollback_transaction(state, pending)
            except Exception as rollback_error:
                raise RuntimeError(
                    "Manual rollback failed and recovery to the starting state also failed: "
                    f"{rollback_error}"
                ) from exc
            raise


def recover_pending_transaction():
    if not ALLOW_SWITCHING:
        raise RuntimeError("Recovery is disabled by configuration")
    with LOCK:
        state = load_state()
        pending = state.get("pending")
        if not isinstance(pending, dict):
            return {"changed": False, "message": "No unfinished transaction"}
        image = _rollback_transaction(state, pending)
        prune_snapshots(state)
        return {"changed": True, "image": image, "channel": pending.get("fromChannel")}


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

    last_snapshot = None
    if state.get("lastSnapshot"):
        try:
            manifest = load_snapshot_manifest(state["lastSnapshot"])
            last_snapshot = {
                "path": state["lastSnapshot"],
                "createdAt": manifest.get("createdAt"),
                "channel": manifest.get("channel"),
                "image": manifest.get("image"),
            }
        except Exception:
            last_snapshot = None

    return {
        "managerVersion": MANAGER_VERSION,
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
            "lastSnapshot": last_snapshot,
        },
        "pending": state.get("pending"),
    }


INDEX = r'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bambuddy Manager</title>
<style>
:root{color-scheme:dark;font-family:Inter,system-ui,sans-serif;background:#10151b;color:#eef4fb}
body{margin:0;padding:24px}main{max-width:820px;margin:auto}.card{background:#1b232c;border:1px solid #34404c;border-radius:16px;padding:20px;margin:14px 0}
h1{margin:0 0 6px}h2{font-size:17px}.muted{color:#9bb0c5}.row{display:flex;gap:12px;flex-wrap:wrap;align-items:center}.pill{padding:6px 10px;border-radius:999px;background:#26313c}
button{border:0;border-radius:10px;padding:11px 16px;font-weight:700;cursor:pointer;margin-top:8px}button.primary{background:#18c76f;color:#07140c}button.warn{background:#e6a23c;color:#171006}button.danger{background:#dc5b5b;color:white}
button:disabled{opacity:.45;cursor:not-allowed}code{word-break:break-all;color:#b8d7f3}.error{color:#ff8f8f}.ok{color:#5ee69c}.notice{color:#ffd479}
</style>
</head>
<body><main>
<h1>Bambuddy Manager</h1><div class="muted">Stable / Beta channels, verified snapshots and rollback for Umbrel</div>
<div class="card"><h2>Текущая установка</h2><div id="current">Загрузка…</div></div>
<div class="card"><h2>Каналы</h2><div id="channels"></div></div>
<div class="card"><h2>Восстановление</h2><div id="recovery"></div></div>
<div class="card"><h2>Примечание</h2><div class="muted">Версия на плитке Umbrel — bootstrap-версия пакета. Фактической Stable/Beta версией управляет этот Manager по проверенному immutable digest.</div></div>
<div id="message"></div>
</main>
<script>
let state;
function text(el,value){document.querySelector(el).textContent=value}
async function load(){
  const r=await fetch('/api/status'); state=await r.json();
  if(!r.ok) throw new Error(state.error||'Ошибка');
  const c=state.current;
  document.querySelector('#current').innerHTML=`<div class="row"><span class="pill">${c.channel}</span><span>${c.running?'🟢 запущен':'🔴 остановлен'}</span></div><p><code>${c.image}</code></p>`;
  const root=document.querySelector('#channels'); root.innerHTML='';
  for(const name of ['stable','beta']){
    const m=state.channels[name]||{}; const beta=name==='beta';
    const same=m.immutableImage===c.image;
    const disabled=!state.switchingEnabled||!m.available||same||!!state.pending;
    let action=beta?'Перейти на Beta':'Перейти на Stable';
    if(c.channel===name&&!same) action=beta?'Обновить Beta':'Обновить Stable';
    const row=document.createElement('div'); row.style.margin='14px 0';
    const title=document.createElement('b'); title.textContent=beta?'Beta / Daily':'Stable'; row.appendChild(title);
    row.appendChild(document.createTextNode(` — ${m.version||'недоступен'}`));
    row.appendChild(document.createElement('br'));
    const note=document.createElement('span'); note.className='muted'; note.textContent=m.available?(m.stale?'кэшированные проверенные metadata':'проверен Store'):'ещё не опубликован'; row.appendChild(note);
    row.appendChild(document.createElement('br'));
    const button=document.createElement('button'); button.className=beta?'warn':'primary'; button.disabled=disabled; button.textContent=action; button.onclick=()=>switchTo(name); row.appendChild(button);
    root.appendChild(row);
  }
  const recovery=document.querySelector('#recovery'); recovery.innerHTML='';
  if(state.pending){
    const p=document.createElement('div'); p.className='notice'; p.textContent='Обнаружена незавершённая транзакция. Сначала восстановите исходное состояние.'; recovery.appendChild(p);
    const b=document.createElement('button'); b.className='danger'; b.textContent='Восстановить незавершённую транзакцию'; b.onclick=recoverPending; recovery.appendChild(b);
  }else if(state.rollback.lastSnapshot){
    const s=state.rollback.lastSnapshot;
    const p=document.createElement('div'); p.className='muted'; p.textContent=`Последний snapshot: ${s.channel} · ${s.createdAt||''}`; recovery.appendChild(p);
    const b=document.createElement('button'); b.className='danger'; b.textContent='Откатиться к последнему snapshot'; b.onclick=rollbackLast; recovery.appendChild(b);
  }else{
    recovery.textContent='Snapshot будет создан автоматически перед первым переключением.';
    recovery.className='muted';
  }
}
async function post(path,body){
  const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-Bambuddy-Manager':'1'},body:JSON.stringify(body||{})});
  const data=await r.json(); if(!r.ok) throw new Error(data.error||'Ошибка'); return data;
}
async function switchTo(channel){
  const warning=channel==='beta'
    ?'Bambuddy будет остановлен, база проверенно сохранена в snapshot, затем будет запущена Beta. Продолжить?'
    :'При возврате из Beta будет восстановлен Stable snapshot. Данные, созданные только в Beta после входа в Beta, не попадут в Stable. Продолжить?';
  if(!confirm(warning)) return;
  await action(()=>post('/api/switch',{channel}),'Переключение выполнено и health-check пройден.');
}
async function rollbackLast(){
  if(!confirm('Восстановить последний snapshot и соответствующую ему версию Bambuddy? Текущее состояние сначала будет сохранено в новый snapshot.')) return;
  await action(()=>post('/api/rollback',{}),'Rollback выполнен и проверен.');
}
async function recoverPending(){
  if(!confirm('Вернуть Bambuddy в состояние до незавершённой транзакции?')) return;
  await action(()=>post('/api/recover',{}),'Исходное состояние восстановлено.');
}
async function action(fn,success){
  const box=document.querySelector('#message'); box.className='card'; box.textContent='Операция выполняется…';
  try{await fn(); box.className='card ok'; box.textContent=success; await load();}
  catch(e){box.className='card error'; box.textContent=e.message;}
}
load().catch(e=>text('#current',e.message));
</script></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, data):
        payload = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/":
            payload = INDEX.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self' 'unsafe-inline'; frame-ancestors 'self'")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path == "/health":
            self._json(200, {"status": "ok", "version": MANAGER_VERSION})
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
        if self.path not in ("/api/switch", "/api/rollback", "/api/recover"):
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 0 or length > 4096:
                raise ValueError("request too large")
            body = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/api/switch":
                result = switch_channel(body.get("channel"))
            elif self.path == "/api/rollback":
                result = rollback_last_snapshot()
            else:
                result = recover_pending_transaction()
            self._json(200, result)
        except (ValueError, json.JSONDecodeError) as exc:
            self._json(400, {"error": str(exc)})
        except Exception as exc:
            self._json(500, {"error": str(exc)})

    def log_message(self, fmt, *args):
        print(f"[http] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Bambuddy Manager {MANAGER_VERSION} listening on 0.0.0.0:{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
