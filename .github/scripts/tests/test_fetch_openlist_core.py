import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from fetch_openlist_core import (
    EXPECTED_ARCHITECTURES,
    PACKAGE_FILES,
    install_target,
    load_lock,
    replace_entries,
    safe_extract,
    selected_asset,
)


COMMIT = "a" * 40


class FetchOpenListCoreTest(unittest.TestCase):
    def lock(self, target, archive):
        return {
            "schema": 1,
            "repository": "Venera-Works/Venera-OpenList-Core",
            "version": "0.1.0-beta.5",
            "tag": "core-v0.1.0-beta.5",
            "sourceCommit": COMMIT,
            "rpcAbi": 1,
            "assets": {
                target: {
                    "name": f"openlist-core-{target}.zip",
                    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                },
            },
        }

    def archive(self, directory, target, *, metadata=None, files=None):
        archive = Path(directory) / f"{target}.zip"
        metadata = metadata or {
            "version": "0.1.0-beta.5",
            "sourceCommit": COMMIT,
            "rpcAbi": 1,
            "platform": target,
            "architectures": sorted(EXPECTED_ARCHITECTURES[target]),
        }
        files = files or PACKAGE_FILES[target]
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("metadata.json", json.dumps(metadata))
            for name in files:
                bundle.writestr(name, name)
        return archive

    def downloader(self, archive):
        urls = []

        def download(url, destination):
            urls.append(url)
            destination.write_bytes(archive.read_bytes())

        return download, urls

    def test_checked_in_lock_covers_supported_platforms(self):
        lock = load_lock()
        for target in EXPECTED_ARCHITECTURES:
            self.assertEqual(selected_asset(lock, target)["name"], f"openlist-core-{target}.zip")
        self.assertEqual(lock["version"], "0.1.0-beta.5")
        self.assertEqual(lock["rpcAbi"], 1)

    def test_rejects_incomplete_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory, "android")
            lock = self.lock("android", archive)
            lock["sourceCommit"] = None
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                selected_asset(lock, "android")

    def test_rejects_wrong_digest_without_replacing_installed_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory, "android")
            lock = self.lock("android", archive)
            lock["assets"]["android"]["sha256"] = "0" * 64
            root = Path(directory) / "app"
            installed = root / "android" / "app" / "libs" / "openlistcore.aar"
            installed.parent.mkdir(parents=True)
            installed.write_text("previous version")
            with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                install_target("android", lock, root, self.downloader(archive)[0])
            self.assertEqual(installed.read_text(), "previous version")

    def test_rejects_wrong_metadata_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            for field, wrong in (("platform", "android"), ("rpcAbi", 2), ("sourceCommit", "b" * 40)):
                with self.subTest(field=field):
                    metadata = {
                        "version": "0.1.0-beta.5",
                        "sourceCommit": COMMIT,
                        "rpcAbi": 1,
                        "platform": "windows-x64",
                        "architectures": ["x86_64"],
                        field: wrong,
                    }
                    archive = self.archive(directory, "windows-x64", metadata=metadata)
                    root = Path(directory) / "app"
                    with self.assertRaisesRegex(RuntimeError, field):
                        install_target("windows-x64", self.lock("windows-x64", archive), root, self.downloader(archive)[0])
                    self.assertFalse((root / "native").exists())

    def test_rejects_unsafe_archive_paths_and_symbolic_links(self):
        with tempfile.TemporaryDirectory() as directory:
            for member in ("../outside", "C:/outside", "/outside", "..\\outside"):
                with self.subTest(member=member):
                    archive = Path(directory) / "unsafe.zip"
                    with zipfile.ZipFile(archive, "w") as bundle:
                        info = zipfile.ZipInfo()
                        info.filename = member
                        bundle.writestr(info, "bad")
                    with self.assertRaisesRegex(RuntimeError, "unsafe path"):
                        safe_extract(archive, Path(directory) / "out")
            archive = Path(directory) / "link.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                link = zipfile.ZipInfo("link")
                link.create_system = 3
                link.external_attr = 0o120777 << 16
                bundle.writestr(link, "../outside")
            with self.assertRaisesRegex(RuntimeError, "symbolic link"):
                safe_extract(archive, Path(directory) / "out")

    def test_rejects_metadata_for_wrong_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory, "android", metadata={
                "version": "0.1.0-beta.5",
                "sourceCommit": COMMIT,
                "rpcAbi": 1,
                "platform": "android",
                "architectures": ["arm64-v8a"],
            })
            with self.assertRaisesRegex(RuntimeError, "architectures"):
                install_target("android", self.lock("android", archive), Path(directory) / "app", self.downloader(archive)[0])

    def test_rejects_missing_platform_file(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory, "windows-x64", files=("LICENSE.OpenList.txt",))
            with self.assertRaisesRegex(RuntimeError, "venera_openlist.dll"):
                install_target("windows-x64", self.lock("windows-x64", archive), Path(directory) / "app", self.downloader(archive)[0])

    def test_installs_selected_android_binary_and_license(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory, "android")
            downloader, urls = self.downloader(archive)
            root = Path(directory) / "app"
            install_target("android", self.lock("android", archive), root, downloader)
            self.assertEqual(urls, [
                "https://github.com/Venera-Works/Venera-OpenList-Core/releases/download/"
                "core-v0.1.0-beta.5/openlist-core-android.zip"
            ])
            self.assertEqual((root / "android" / "app" / "libs" / "openlistcore.aar").read_text(), "openlistcore.aar")
            self.assertEqual((root / "android" / "app" / "src" / "main" / "assets" / "licenses" / "LICENSE.OpenList.txt").read_text(), "LICENSE.OpenList.txt")

    def test_installs_windows_binary_and_license_beside_each_other(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory, "windows-x64")
            root = Path(directory) / "app"
            install_target("windows-x64", self.lock("windows-x64", archive), root, self.downloader(archive)[0])
            installed = root / "native" / "openlist_core" / "artifacts" / "windows"
            self.assertEqual((installed / "venera_openlist.dll").read_text(), "venera_openlist.dll")
            self.assertEqual((installed / "LICENSE.OpenList.txt").read_text(), "LICENSE.OpenList.txt")

    def test_restores_previous_files_when_install_fails_midway(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "first"
            second = root / "second"
            first.write_text("old first")
            second.write_text("old second")
            source = root / "source"
            source.write_text("new")
            import os
            real_replace = os.replace

            def replace(source_path, destination):
                if ".new-" in str(source_path) and destination == second:
                    raise OSError("simulated install failure")
                return real_replace(source_path, destination)

            with mock.patch("fetch_openlist_core.os.replace", side_effect=replace):
                with self.assertRaisesRegex(OSError, "simulated install failure"):
                    replace_entries([(source, first), (source, second)])
            self.assertEqual(first.read_text(), "old first")
            self.assertEqual(second.read_text(), "old second")
            self.assertFalse(any(".new-" in item.name or ".old-" in item.name for item in root.iterdir()))


if __name__ == "__main__":
    unittest.main()
