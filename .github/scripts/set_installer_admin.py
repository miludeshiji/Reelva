#!/usr/bin/env python3
"""Request UAC before the Inno Setup loader extracts its temporary files."""

import argparse
from pathlib import Path


# Replace Inno Setup's padded execution-level tag in place.
# Keep the EXE size and appended installer data intact; do not rewrite resources.
AS_INVOKER = (
    b'<requestedExecutionLevel level="asInvoker"            uiAccess="false"/>'
)
REQUIRE_ADMIN = (
    b'<requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>'
)


def require_admin(path: Path) -> None:
    data = path.read_bytes()
    if not data.startswith(b"MZ"):
        raise ValueError("Installer is not a Windows executable")

    invoker_count = data.count(AS_INVOKER)
    admin_count = data.count(REQUIRE_ADMIN)
    if invoker_count == 0 and admin_count == 1:
        return
    if invoker_count != 1 or admin_count != 0:
        raise ValueError("Expected one Inno Setup loader execution-level manifest")

    offset = data.index(AS_INVOKER)
    with path.open("r+b") as installer:
        installer.seek(offset)
        installer.write(REQUIRE_ADMIN)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("installer", type=Path)
    args = parser.parse_args()
    require_admin(args.installer)
    print(f"Installer execution level: requireAdministrator ({args.installer})")


if __name__ == "__main__":
    main()
