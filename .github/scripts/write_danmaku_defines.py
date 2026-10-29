"""Write Flutter build defines without logging application credentials."""

import json
import os
from pathlib import Path


def main():
    secret = os.environ.get("DANDANPLAY_APP_SECRET", "")
    target = Path(".dart_tool/danmaku-defines.json")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps({"DANDANPLAY_APP_SECRET": secret}),
        encoding="utf-8",
    )
    if secret:
        print("DANDANPLAY_APP_SECRET configured; dandanplay enabled for this build.")
    else:
        print(
            "::warning::DANDANPLAY_APP_SECRET is missing; this build only supports "
            "Bilibili danmaku. Configure the repository Actions secret and rebuild."
        )


if __name__ == "__main__":
    main()
