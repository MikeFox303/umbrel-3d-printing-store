import importlib.util
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_COMPOSE = ROOT / "my3d-bambuddy" / "docker-compose.yml"
SERVER = ROOT / "my3d-bambuddy-manager" / "src" / "server.py"


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)


def main():
    compose = SOURCE_COMPOSE.read_text(encoding="utf-8")
    match = re.search(
        r"image:\s*(ghcr\.io/maziggy/bambuddy:[^@\s]+@sha256:[0-9a-f]{64})",
        compose,
    )
    if not match:
        raise RuntimeError("Could not resolve pinned Bambuddy bootstrap image")
    image = match.group(1)

    root = Path(tempfile.mkdtemp(prefix="bambuddy-manager-clone-smoke-"))
    app_root = root / "apps"
    target = app_root / "my3d-bambuddy"
    data = target / "data"
    logs = target / "logs"
    manager_data = root / "manager"
    data.mkdir(parents=True)
    logs.mkdir(parents=True)
    manager_data.mkdir(parents=True)

    target_compose = target / "docker-compose.yml"
    target_compose.write_text(
        "services:\n"
        "  server:\n"
        f"    image: {image}\n"
        "    environment:\n"
        "      TZ: UTC\n"
        "      PUID: \"1000\"\n"
        "      PGID: \"1000\"\n"
        "      PORT: \"8000\"\n",
        encoding="utf-8",
    )

    name = "bambuddy-manager-clone-smoke"
    run("docker", "rm", "-f", name, check=False)
    try:
        run("docker", "pull", image)
        run(
            "docker",
            "create",
            "--name",
            name,
            "--entrypoint",
            "/bin/sh",
            "-p",
            "127.0.0.1:18002:8000",
            "-e",
            "TZ=UTC",
            "-e",
            "PUID=1000",
            "-e",
            "PGID=1000",
            "-e",
            "PORT=8000",
            "-v",
            f"{data}:/app/data",
            "-v",
            f"{logs}:/app/logs",
            image,
            "-c",
            "sleep 600",
        )
        run("docker", "start", name)

        os.environ["MANAGER_DATA_DIR"] = str(manager_data)
        os.environ["UMBREL_APP_DATA_ROOT"] = str(app_root)
        os.environ["BAMBUDDY_CONTAINER_NAME"] = name
        os.environ["BAMBUDDY_HEALTH_URL"] = "http://127.0.0.1:18002/health"
        os.environ["ALLOW_SWITCHING"] = "false"

        spec = importlib.util.spec_from_file_location("manager_clone_smoke_server", SERVER)
        manager = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(manager)

        previous = manager.inspect_container()
        if (previous.get("Config") or {}).get("Entrypoint") != ["/bin/sh"]:
            raise RuntimeError("Smoke fixture did not apply the old Entrypoint override")

        clone_spec = manager.build_clone_spec(previous)
        env_keys = {item.split("=", 1)[0] for item in clone_spec.get("Env", [])}
        if env_keys != {"TZ", "PUID", "PGID", "PORT"}:
            raise RuntimeError(f"Manager preserved unexpected image environment: {sorted(env_keys)}")
        if "Cmd" in clone_spec or "Entrypoint" in clone_spec:
            raise RuntimeError("Manager clone spec froze old image command defaults")

        manager.stop_container()
        manager.remove_container()
        manager.create_clone_from_spec(clone_spec, image)
        manager.start_container()
        manager.wait_for_health(120)
        manager.verify_running_image(image)

        current = manager.inspect_container()
        current_config = current.get("Config") or {}
        if current_config.get("Entrypoint") == ["/bin/sh"]:
            raise RuntimeError("Recreated container retained the old Entrypoint override")
        if current_config.get("Cmd") == ["-c", "sleep 600"]:
            raise RuntimeError("Recreated container retained the old Cmd override")
        current_env = {
            item.split("=", 1)[0]: item.split("=", 1)[1]
            for item in current_config.get("Env") or []
            if "=" in item
        }
        if current_env.get("HOME") != "/app":
            raise RuntimeError("New image defaults were not inherited during recreation")
        if current_env.get("PORT") != "8000":
            raise RuntimeError("Explicit Compose environment was not preserved")
    finally:
        run("docker", "rm", "-f", name, check=False)
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
