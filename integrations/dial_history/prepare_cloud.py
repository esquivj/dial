#!/usr/bin/env python3
"""Assemble a code-only Vercel project from an explicit allowlist."""
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
BUILD = HERE / "cloud-build"


def main():
    BUILD.mkdir(exist_ok=True)
    # The link may persist, but only these code files are staged for deployment.
    allowed = {"api", "lib", "public", "vercel.json", "requirements.txt", ".python-version", ".vercel", ".gitignore"}
    unexpected = {p.name for p in BUILD.iterdir()} - allowed
    if unexpected:
        raise ValueError("Unexpected build contents; inspect before deploying: " + ", ".join(sorted(unexpected)))
    for folder in ("api", "lib", "public"):
        target = BUILD / folder
        if target.exists():
            shutil.rmtree(target)
        target.mkdir()
    shutil.copyfile(HERE / "cloud/api/index.py", BUILD / "api/index.py")
    for name in ("dial_history.py", "cloud_store.py"):
        shutil.copyfile(HERE / name, BUILD / "lib" / name)
    for name in ("vercel.json", "requirements.txt", ".python-version"):
        shutil.copyfile(HERE / "cloud" / name, BUILD / name)
    (BUILD / "public/.gitkeep").touch()
    print(json.dumps({"project_directory": str(BUILD), "contains_listening_data": False, "contains_credentials": False}))


if __name__ == "__main__":
    main()
