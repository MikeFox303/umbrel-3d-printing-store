import importlib.util
import json
import os
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "my3d-bambuddy-manager" / "src" / "server.py"
TEST_ROOT = Path(tempfile.mkdtemp(prefix="bambuddy-manager-unit-"))
os.environ["MANAGER_DATA_DIR"] = str(TEST_ROOT / "manager")
os.environ["UMBREL_APP_DATA_ROOT"] = str(TEST_ROOT / "apps")
os.environ["ALLOW_SWITCHING"] = "false"

spec = importlib.util.spec_from_file_location("bambuddy_manager_server", SERVER)
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


def pinned(tag, char):
    return f"ghcr.io/maziggy/bambuddy:{tag}@sha256:{char * 64}"


def channel(name, version, image, char):
    return {
        "schemaVersion": 1,
        "channel": name,
        "version": version,
        "digest": f"sha256:{char * 64}",
        "immutableImage": image,
        "testedPlatforms": ["linux/amd64", "linux/arm64"],
        "available": True,
    }


class ManagerTestCase(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(manager.TARGET_DIR, ignore_errors=True)
        manager.TARGET_DATA.mkdir(parents=True, exist_ok=True)
        shutil.rmtree(manager.BACKUP_DIR, ignore_errors=True)
        manager.BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        if manager.STATE_FILE.exists():
            manager.STATE_FILE.unlink()
        for cached in (manager.MANAGER_DATA / "stable.json", manager.MANAGER_DATA / "beta.json"):
            if cached.exists():
                cached.unlink()

    def write_compose(self, image=None, extra=""):
        image = image or pinned("1.2.5.5", "a")
        manager.TARGET_COMPOSE.write_text(
            "services:\n"
            "  server:\n"
            f"    image: {image}\n"
            "    environment:\n"
            "      PORT: \"8000\"\n"
            "      PUID: \"1000\"\n"
            "      CUSTOM_VALUE: ${CUSTOM_VALUE:-fallback}\n"
            f"{extra}",
            encoding="utf-8",
        )


class ChannelDetectionTests(ManagerTestCase):
    def setUp(self):
        super().setUp()
        self.channels = {
            "stable": {"immutableImage": pinned("1.2.6", "1")},
            "beta": {"immutableImage": pinned("daily", "2")},
        }

    def test_exact_current_channel_metadata_is_recognized(self):
        self.assertEqual(
            manager.channel_for_image(self.channels["stable"]["immutableImage"], self.channels),
            "stable",
        )
        self.assertEqual(
            manager.channel_for_image(self.channels["beta"]["immutableImage"], self.channels),
            "beta",
        )

    def test_older_pinned_stable_is_still_stable(self):
        self.assertEqual(
            manager.channel_for_image(pinned("1.2.5.5", "a"), self.channels),
            "stable",
        )

    def test_older_daily_digest_is_still_beta(self):
        self.assertEqual(
            manager.channel_for_image(pinned("daily", "b"), self.channels),
            "beta",
        )

    def test_unknown_tag_is_custom(self):
        self.assertEqual(
            manager.channel_for_image(pinned("experimental", "c"), self.channels),
            "custom",
        )


class ChannelMetadataTests(ManagerTestCase):
    def test_valid_stable_and_beta_metadata_are_accepted(self):
        stable = channel("stable", "1.2.6", pinned("1.2.6", "1"), "1")
        beta = channel(
            "beta",
            "1.2.7b1-daily.20260903",
            pinned("daily", "2"),
            "2",
        )
        self.assertIs(manager.validate_channel_metadata("stable", stable), stable)
        self.assertIs(manager.validate_channel_metadata("beta", beta), beta)

    def test_crossed_channel_images_are_rejected(self):
        stable_with_daily = channel("stable", "1.2.6", pinned("daily", "1"), "1")
        beta_with_stable = channel(
            "beta",
            "1.2.7b1-daily.20260903",
            pinned("1.2.7", "2"),
            "2",
        )
        with self.assertRaises(ValueError):
            manager.validate_channel_metadata("stable", stable_with_daily)
        with self.assertRaises(ValueError):
            manager.validate_channel_metadata("beta", beta_with_stable)

    def test_digest_and_platform_mismatch_are_rejected(self):
        stable = channel("stable", "1.2.6", pinned("1.2.6", "1"), "2")
        with self.assertRaises(ValueError):
            manager.validate_channel_metadata("stable", stable)
        stable = channel("stable", "1.2.6", pinned("1.2.6", "1"), "1")
        stable["testedPlatforms"] = ["linux/amd64"]
        with self.assertRaises(ValueError):
            manager.validate_channel_metadata("stable", stable)


class ImageGuardTests(ManagerTestCase):
    def test_pull_reference_discards_mutable_tag_and_keeps_digest(self):
        digest = "d" * 64
        image = pinned("daily", "d")
        self.assertEqual(
            manager.digest_pull_reference(image),
            f"ghcr.io/maziggy/bambuddy@sha256:{digest}",
        )

    def test_unpinned_or_other_repository_images_are_rejected(self):
        with self.assertRaises(ValueError):
            manager.digest_pull_reference("ghcr.io/maziggy/bambuddy:daily")
        with self.assertRaises(ValueError):
            manager.digest_pull_reference(
                f"ghcr.io/example/bambuddy:daily@sha256:{'e' * 64}"
            )

    def test_compose_image_replacement_stays_on_official_pinned_image(self):
        old = pinned("1.2.5.5", "a")
        new = pinned("daily", "b")
        self.write_compose(old)
        manager.write_compose_image(new)
        self.assertEqual(manager.read_compose_image(), new)
        with self.assertRaises(ValueError):
            manager.write_compose_image("ghcr.io/maziggy/bambuddy:daily")


class ClonePolicyTests(ManagerTestCase):
    def test_clone_spec_preserves_only_explicit_compose_environment(self):
        self.write_compose()
        previous = {
            "Config": {
                "Env": [
                    "HOME=/app",
                    "USER=bambuddy",
                    "PORT=8000",
                    "PUID=1000",
                    "CUSTOM_VALUE=expanded-value",
                ],
                "Cmd": ["old-image-command"],
                "Entrypoint": ["old-image-entrypoint"],
                "Labels": {"com.docker.compose.service": "server"},
            },
            "HostConfig": {
                "NetworkMode": "host",
                "Binds": ["/host/data:/app/data"],
                "RestartPolicy": {"Name": "on-failure", "MaximumRetryCount": 0},
                "CapAdd": ["NET_BIND_SERVICE"],
                "Init": True,
            },
        }
        spec = manager.build_clone_spec(previous)
        self.assertEqual(
            spec["Env"],
            ["PORT=8000", "PUID=1000", "CUSTOM_VALUE=expanded-value"],
        )
        self.assertNotIn("Cmd", spec)
        self.assertNotIn("Entrypoint", spec)
        self.assertEqual(spec["HostConfig"]["NetworkMode"], "host")
        self.assertEqual(spec["HostConfig"]["CapAdd"], ["NET_BIND_SERVICE"])

    def test_unsupported_compose_command_refuses_switch_recreation(self):
        self.write_compose(extra="    command: [\"custom\"]\n")
        with self.assertRaises(RuntimeError):
            manager.validate_supported_compose()


class SnapshotTests(ManagerTestCase):
    def create_database(self, values):
        db_path = manager.TARGET_DATA / "bambuddy.db"
        with sqlite3.connect(db_path) as db:
            db.execute("CREATE TABLE IF NOT EXISTS sample(value TEXT)")
            db.execute("DELETE FROM sample")
            db.executemany("INSERT INTO sample(value) VALUES (?)", [(value,) for value in values])
            db.commit()
        return db_path

    def read_values(self):
        with sqlite3.connect(manager.TARGET_DATA / "bambuddy.db") as db:
            return [row[0] for row in db.execute("SELECT value FROM sample ORDER BY rowid")]

    def test_snapshot_round_trip_restores_database_and_compose(self):
        old_image = pinned("1.2.5.5", "a")
        new_image = pinned("daily", "b")
        self.write_compose(old_image)
        self.create_database(["stable"])

        snapshot = manager.make_snapshot(old_image, "stable")
        manifest = manager.load_snapshot_manifest(snapshot)
        self.assertEqual(manifest["image"], old_image)
        self.assertIn("bambuddy.db", manifest["databases"])

        self.create_database(["beta", "changed"])
        manager.write_compose_image(new_image)
        manager.restore_snapshot(snapshot)

        self.assertEqual(self.read_values(), ["stable"])
        self.assertEqual(manager.read_compose_image(), old_image)

    def test_snapshot_checksum_detects_corruption(self):
        image = pinned("1.2.5.5", "a")
        self.write_compose(image)
        self.create_database(["safe"])
        snapshot = manager.make_snapshot(image, "stable")
        with (snapshot / "bambuddy.db").open("ab") as handle:
            handle.write(b"corruption")
        with self.assertRaises(RuntimeError):
            manager.load_snapshot_manifest(snapshot)

    def test_snapshot_path_cannot_escape_backup_root(self):
        outside = TEST_ROOT / "outside-snapshot"
        outside.mkdir(exist_ok=True)
        with self.assertRaises(RuntimeError):
            manager._snapshot_path(outside)


if __name__ == "__main__":
    unittest.main()
