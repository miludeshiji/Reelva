#!/usr/bin/env python3
"""Consumer-focused contract tests for Reelva release metadata logic."""

from pathlib import Path
import sys
import tempfile
import unittest

# Ensure .github/scripts is importable
scripts_dir = Path(__file__).resolve().parents[1]
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import release_metadata  # noqa: E402


class TestReleaseMetadata(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def _create_files(
        self,
        pubspec_version: str,
        changelog: str | None = None,
        readme: str | None = None,
    ):
        pubspec_path = self.root / "pubspec.yaml"
        with open(pubspec_path, "w", encoding="utf-8") as f:
            f.write(f"name: reelva\nversion: {pubspec_version}\n")

        if changelog is not None:
            changelog_path = self.root / "CHANGELOG.md"
            with open(changelog_path, "w", encoding="utf-8") as f:
                f.write(changelog)

        if readme is not None:
            readme_path = self.root / "README.md"
            with open(readme_path, "w", encoding="utf-8") as f:
                f.write(readme)

    def test_formal_release_success(self):
        repo = "miludeshiji/Reelva"
        tag = "v0.1.0"
        changelog = (
            "# 更新日志\n\n"
            "## v0.1.0\n\n"
            "- 首个正式版本发布。\n\n"
            "## 未发布\n"
        )
        readme = (
            "# Reelva\n\n"
            "下载地址：\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-arm64-v8a.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-armeabi-v7a.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-x86_64.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-windows-x64.zip\n"
        )
        self._create_files("0.1.0+1", changelog, readme)

        notes_out = self.root / "notes.md"
        gh_out = self.root / "github_output.txt"

        ver, is_beta = release_metadata.validate_release(
            root=self.root,
            tag=tag,
            repository=repo,
            notes_output=str(notes_out),
            github_output=str(gh_out),
        )

        self.assertEqual(ver, "0.1.0")
        self.assertFalse(is_beta)
        self.assertTrue(notes_out.is_file())
        self.assertIn("首个正式版本发布", notes_out.read_text(encoding="utf-8"))

        gh_text = gh_out.read_text(encoding="utf-8")
        self.assertIn("version=0.1.0", gh_text)
        self.assertIn("prerelease=false", gh_text)

    def test_beta_release_success(self):
        repo = "miludeshiji/Reelva"
        tag = "v0.1.0-beta1"
        changelog = (
            "# 更新日志\n\n"
            "## v0.1.0-beta1\n\n"
            "- 测试预览版本说明。\n\n"
            "## 未发布\n"
        )
        readme = "# Reelva\n\nBeta 版本说明文档，不要求下载链接。"
        self._create_files("0.1.0-beta1+1", changelog, readme)

        notes_out = self.root / "notes.md"
        gh_out = self.root / "github_output.txt"

        ver, is_beta = release_metadata.validate_release(
            root=self.root,
            tag=tag,
            repository=repo,
            notes_output=str(notes_out),
            github_output=str(gh_out),
        )

        self.assertEqual(ver, "0.1.0-beta1")
        self.assertTrue(is_beta)
        self.assertTrue(notes_out.is_file())

        expected_prefix = (
            "## **注意**\n"
            "**beta版可能存在大量bug，无必要请勿下载**\n\n"
        )
        notes_content = notes_out.read_text(encoding="utf-8")
        self.assertTrue(notes_content.startswith(expected_prefix))
        self.assertIn("测试预览版本说明", notes_content)

        gh_text = gh_out.read_text(encoding="utf-8")
        self.assertIn("version=0.1.0-beta1", gh_text)
        self.assertIn("prerelease=true", gh_text)

    def test_version_and_tag_mismatch(self):
        self._create_files("0.1.0+1", "## v0.1.0\n\n- 日志", "# Readme")

        # Tag version differs
        with self.assertRaises(ValueError):
            release_metadata.validate_release(
                root=self.root,
                tag="v0.1.1",
                repository="miludeshiji/Reelva",
            )

        # Tag does not start with 'v'
        with self.assertRaises(ValueError):
            release_metadata.validate_release(
                root=self.root,
                tag="0.1.0",
                repository="miludeshiji/Reelva",
            )

    def test_missing_or_empty_changelog_notes(self):
        # Missing section
        changelog_missing = "# 更新日志\n\n## 未发布\n- 条目\n"
        self._create_files("0.1.0+1", changelog_missing, "# Readme")
        with self.assertRaises(ValueError):
            release_metadata.validate_release(
                root=self.root,
                tag="v0.1.0",
                repository="miludeshiji/Reelva",
            )

        # Empty section
        changelog_empty = "# 更新日志\n\n## v0.1.0\n\n## 未发布\n- 条目\n"
        self._create_files("0.1.0+1", changelog_empty, "# Readme")
        with self.assertRaises(ValueError):
            release_metadata.validate_release(
                root=self.root,
                tag="v0.1.0",
                repository="miludeshiji/Reelva",
            )

    def test_formal_readme_link_missing_or_wrong(self):
        changelog = "## v0.1.0\n\n- 正式发布日志\n"
        # README missing windows zip link
        readme_incomplete = (
            "# Reelva\n\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-arm64-v8a.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-armeabi-v7a.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-x86_64.apk\n"
        )
        self._create_files("0.1.0+1", changelog, readme_incomplete)

        with self.assertRaises(ValueError):
            release_metadata.validate_release(
                root=self.root,
                tag="v0.1.0",
                repository="miludeshiji/Reelva",
            )

    def test_formal_release_with_beta_warning_fails(self):
        changelog = (
            "## v0.1.0\n\n"
            "## **注意**\n"
            "**beta版可能存在大量bug，无必要请勿下载**\n\n"
            "- 正式发布日志\n"
        )
        readme = (
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-arm64-v8a.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-armeabi-v7a.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-android-x86_64.apk\n"
            "- https://github.com/miludeshiji/Reelva/releases/download/v0.1.0/Reelva-0.1.0-windows-x64.zip\n"
        )
        self._create_files("0.1.0+1", changelog, readme)

        with self.assertRaises(ValueError):
            release_metadata.validate_release(
                root=self.root,
                tag="v0.1.0",
                repository="miludeshiji/Reelva",
            )

    def test_invalid_build_numbers_and_versions(self):
        # Missing build number
        self._create_files("0.1.0")
        with self.assertRaises(ValueError):
            release_metadata.parse_pubspec_version(self.root / "pubspec.yaml")

        # Zero build number (must be positive integer)
        self._create_files("0.1.0+0")
        with self.assertRaises(ValueError):
            release_metadata.parse_pubspec_version(self.root / "pubspec.yaml")

        # Invalid beta number (beta 0)
        self._create_files("0.1.0-beta0+1")
        with self.assertRaises(ValueError):
            release_metadata.parse_pubspec_version(self.root / "pubspec.yaml")

        # Non-beta prerelease tag
        self._create_files("0.1.0-alpha+1")
        with self.assertRaises(ValueError):
            release_metadata.parse_pubspec_version(self.root / "pubspec.yaml")


if __name__ == "__main__":
    unittest.main()
