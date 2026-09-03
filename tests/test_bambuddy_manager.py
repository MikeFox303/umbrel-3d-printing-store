import importlib.util
import os
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


class ChannelDetectionTests(unittest.TestCase):
    def setUp(self):
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


class ImageGuardTests(unittest.TestCase):
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
        manager.TARGET_COMPOSE.parent.mkdir(parents=True, exist_ok=True)
        old = pinned("1.2.5.5", "a")
        new = pinned("daily", "b")
        manager.TARGET_COMPOSE.write_text(
            f"services:\n  server:\n    image: {old}\n",
            encoding="utf-8",
        )
        manager.write_compose_image(new)
        self.assertEqual(manager.read_compose_image(), new)
        with self.assertRaises(ValueError):
            manager.write_compose_image("ghcr.io/maziggy/bambuddy:daily")


if __name__ == "__main__":
    unittest.main()
