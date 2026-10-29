#!/usr/bin/env python3
"""Verify that changing the loader manifest preserves the installer payload."""

from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import set_installer_admin  # noqa: E402


MANIFEST = b'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
<security><requestedPrivileges>
<requestedExecutionLevel level="asInvoker"            uiAccess="false"/>
</requestedPrivileges></security>
</trustInfo>
</assembly>'''
PREFIX = b"MZ\0loader resource data\0"
PAYLOAD = b"Inno Setup Setup Data (6.7.0)\0" + bytes(range(256)) * 8


class TestSetInstallerAdmin(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.path = Path(self.temp_dir.name) / "installer.exe"

    def test_uac_manifest_preserves_size_offsets_and_payload(self):
        original = PREFIX + MANIFEST + PAYLOAD
        self.path.write_bytes(original)

        set_installer_admin.require_admin(self.path)

        result = self.path.read_bytes()
        self.assertEqual(len(result), len(original))
        self.assertEqual(result[:len(PREFIX)], PREFIX)
        self.assertEqual(result[len(PREFIX) + len(MANIFEST):], PAYLOAD)
        manifest = ET.fromstring(result[len(PREFIX):len(PREFIX) + len(MANIFEST)])
        execution_level = manifest.find(
            ".//{urn:schemas-microsoft-com:asm.v3}requestedExecutionLevel"
        )
        self.assertEqual(execution_level.attrib, {
            "level": "requireAdministrator",
            "uiAccess": "false",
        })
        tag_start = original.index(b"<requestedExecutionLevel")
        tag_end = original.index(b">", tag_start) + 1
        self.assertEqual(result[:tag_start], original[:tag_start])
        self.assertEqual(result[tag_end:], original[tag_end:])

    def test_already_patched_installer_is_unchanged(self):
        self.path.write_bytes(PREFIX + MANIFEST + PAYLOAD)
        set_installer_admin.require_admin(self.path)
        patched = self.path.read_bytes()

        set_installer_admin.require_admin(self.path)

        self.assertEqual(self.path.read_bytes(), patched)

    def test_unexpected_or_ambiguous_manifest_does_not_modify_file(self):
        for original in (
            PREFIX + PAYLOAD,
            PREFIX + MANIFEST + MANIFEST + PAYLOAD,
            PREFIX + MANIFEST.replace(b"            uiAccess", b" uiAccess") + PAYLOAD,
            MANIFEST + PAYLOAD,
        ):
            with self.subTest(original=original[:40]):
                self.path.write_bytes(original)

                with self.assertRaises(ValueError):
                    set_installer_admin.require_admin(self.path)

                self.assertEqual(self.path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
