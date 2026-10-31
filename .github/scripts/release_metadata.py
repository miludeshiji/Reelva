#!/usr/bin/env python3
"""Release metadata parser and validator for Reelva.

Supports extracting the pubspec version for CI build jobs (--print-version)
and validating tag, changelog, and README consistency for release jobs.
"""

import argparse
import os
from pathlib import Path
import re
import sys

BETA_WARNING_LINE1 = "## **注意**"
BETA_WARNING_LINE2 = "**beta版可能存在大量bug，下载前做好备份**"

FORMAL_VERSION_RE = re.compile(r"^(\d+\.\d+\.\d+)\+([1-9]\d*)$")
BETA_VERSION_RE = re.compile(r"^(\d+\.\d+\.\d+-beta[1-9]\d*)\+([1-9]\d*)$")


def parse_pubspec_version(pubspec_path: Path) -> tuple[str, str, bool]:
    if not pubspec_path.is_file():
        raise FileNotFoundError(f"pubspec.yaml not found at {pubspec_path}")

    raw_version = None
    with open(pubspec_path, "r", encoding="utf-8") as f:
        for line in f:
            line_str = line.strip()
            if line_str.startswith("version:"):
                val = line_str.split(":", 1)[1].split("#", 1)[0].strip()
                val = val.strip("\"'")
                raw_version = val
                break

    if not raw_version:
        raise ValueError(f"No 'version:' field found in {pubspec_path}")

    formal_match = FORMAL_VERSION_RE.match(raw_version)
    if formal_match:
        return formal_match.group(1), formal_match.group(2), False

    beta_match = BETA_VERSION_RE.match(raw_version)
    if beta_match:
        return beta_match.group(1), beta_match.group(2), True

    raise ValueError(
        f"Invalid version format in pubspec.yaml: '{raw_version}'. "
        "Must match 'X.Y.Z+<positive_int>' or 'X.Y.Z-beta<N>+<positive_int>' (N>=1)."
    )


def extract_changelog_section(changelog_path: Path, version_name: str) -> str:
    if not changelog_path.is_file():
        raise FileNotFoundError(f"CHANGELOG.md not found at {changelog_path}")

    with open(changelog_path, "r", encoding="utf-8") as f:
        content = f.read().replace("\r\n", "\n")

    target_heading = f"## v{version_name}"
    lines = content.splitlines()
    found = False
    section_lines: list[str] = []

    for line in lines:
        stripped = line.strip()
        if not found:
            if stripped == target_heading or stripped.startswith(f"{target_heading} "):
                found = True
            continue

        if stripped.startswith("# ") or stripped.startswith("## "):
            break

        section_lines.append(line)

    if not found:
        raise ValueError(f"Changelog section '{target_heading}' not found in {changelog_path}")

    section_text = "\n".join(section_lines).strip()
    if not section_text:
        raise ValueError(f"Changelog section '{target_heading}' in {changelog_path} is empty")

    return section_text


def validate_release(
    root: Path,
    tag: str,
    repository: str,
    notes_output: str | None = None,
    github_output: str | None = None,
) -> tuple[str, bool]:
    pubspec_path = root / "pubspec.yaml"
    changelog_path = root / "CHANGELOG.md"
    readme_path = root / "README.md"

    version_name, build_number, is_prerelease = parse_pubspec_version(pubspec_path)

    if not tag:
        raise ValueError("Tag must not be empty (set --tag or GITHUB_REF_NAME)")

    if not tag.startswith("v"):
        raise ValueError(f"Tag '{tag}' must start with 'v'")

    tag_version = tag[1:]
    if tag_version != version_name:
        raise ValueError(
            f"Tag version '{tag_version}' does not match pubspec version '{version_name}'"
        )

    raw_notes = extract_changelog_section(changelog_path, version_name)

    if is_prerelease:
        notes = f"{BETA_WARNING_LINE1}\n{BETA_WARNING_LINE2}\n\n{raw_notes}"
    else:
        if (
            BETA_WARNING_LINE1 in raw_notes
            or BETA_WARNING_LINE2 in raw_notes
            or "beta版可能存在大量bug" in raw_notes
        ):
            raise ValueError("Formal release notes must not contain Beta warning")

        notes = raw_notes
        if not readme_path.is_file():
            raise FileNotFoundError(f"README.md not found at {readme_path}")

        with open(readme_path, "r", encoding="utf-8") as f:
            readme_text = f.read()

        expected_artifacts = [
            f"Reelva-{version_name}-android-arm64-v8a.apk",
            f"Reelva-{version_name}-android-armeabi-v7a.apk",
            f"Reelva-{version_name}-android-x86_64.apk",
            f"Reelva-{version_name}-windows-x64.zip",
            f"Reelva-{version_name}-windows-x64-installer.exe",
        ]

        for artifact in expected_artifacts:
            expected_url = f"https://github.com/{repository}/releases/download/{tag}/{artifact}"
            if expected_url not in readme_text:
                raise ValueError(
                    f"Formal release requires download link in README.md: {expected_url}"
                )

    if notes_output:
        out_p = Path(notes_output)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        with open(out_p, "w", encoding="utf-8") as f:
            f.write(notes + "\n")

    if github_output:
        gh_p = Path(github_output)
        gh_p.parent.mkdir(parents=True, exist_ok=True)
        with open(gh_p, "a", encoding="utf-8") as f:
            f.write(f"version={version_name}\n")
            f.write(f"prerelease={str(is_prerelease).lower()}\n")

    return version_name, is_prerelease


def main() -> int:
    default_root = Path(__file__).resolve().parents[2]

    parser = argparse.ArgumentParser(description="Reelva release metadata parser and validator")
    parser.add_argument("--root", type=Path, default=default_root, help="Repository root path")
    parser.add_argument("--print-version", action="store_true", help="Print pubspec version without +build")
    parser.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME", ""), help="Release tag (e.g. v0.1.0)")
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY", "miludeshiji/Reelva"),
        help="GitHub repository owner/repo",
    )
    parser.add_argument("--notes-output", help="File to write release notes to")
    parser.add_argument(
        "--github-output",
        default=os.environ.get("GITHUB_OUTPUT", ""),
        help="Path to GITHUB_OUTPUT file",
    )

    args = parser.parse_args()

    if args.print_version:
        try:
            pubspec_path = args.root / "pubspec.yaml"
            version_name, _, _ = parse_pubspec_version(pubspec_path)
            sys.stdout.write(f"{version_name}\n")
            return 0
        except Exception as e:
            sys.stderr.write(f"Error parsing pubspec version: {e}\n")
            return 1

    try:
        version_name, is_prerelease = validate_release(
            root=args.root,
            tag=args.tag,
            repository=args.repository,
            notes_output=args.notes_output,
            github_output=args.github_output,
        )
        print(f"Release metadata validated: version={version_name}, prerelease={is_prerelease}")
        return 0
    except Exception as e:
        sys.stderr.write(f"Release validation error: {e}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
