"""Write Flutter build defines without logging application credentials."""

import json
import os
from pathlib import Path


def main():
    target = Path(".dart_tool/danmaku-defines.json")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps({"DANDANPLAY_APP_SECRET": os.environ.get("DANDANPLAY_APP_SECRET", "")}),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
