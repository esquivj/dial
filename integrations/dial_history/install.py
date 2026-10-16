#!/usr/bin/env python3
"""Install the local reader and discovery files; no Spotify credentials are read."""
import json
import os
from pathlib import Path
import plistlib
import secrets
import shlex
import shutil
import socket
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import dial_history as dial


def main():
    runtime, home = dial.RUNTIME, dial.HOME
    python = shutil.which("python3") or sys.executable
    label = "com.juanos.dial-history"
    plist_path = Path.home() / "Library/LaunchAgents" / (label + ".plist")
    target = "gui/" + str(os.getuid())
    # Existing service can own the port. Otherwise detect collisions before installing.
    loaded = subprocess.run(["launchctl", "print", target + "/" + label], capture_output=True).returncode == 0
    if not loaded:
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", dial.PORT))
    for folder in (runtime, home, home / "exports"):
        folder.mkdir(parents=True, exist_ok=True)
        folder.chmod(0o700)
    for name in ("dial_history.py", "README.md"):
        shutil.copyfile(HERE / name, runtime / name)
        (runtime / name).chmod(0o600)
    if not dial.TOKEN.exists():
        fd = os.open(dial.TOKEN, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as file:
            file.write(secrets.token_urlsafe(48) + "\n")
    dial.TOKEN.chmod(0o600)
    command = Path.home() / ".local/bin/dial-history"
    command.parent.mkdir(parents=True, exist_ok=True)
    command.write_text("#!/bin/sh\nexec " + shlex.quote(python) + " " + shlex.quote(str(runtime / "dial_history.py")) + ' "$@"\n')
    command.chmod(0o700)
    manifest = {**dial.discovery(), "command": str(command), "local_base_url": f"http://127.0.0.1:{dial.PORT}",
                "token_file": str(dial.TOKEN), "documentation": str(home / "README.md"), "remote_base_url": None,
                "status_command": [str(command), "status"], "export_directory": str(home / "exports")}
    existing_manifest = home / "manifest.json"
    if existing_manifest.exists():
        existing = json.loads(existing_manifest.read_text())
        for key in ("remote_base_url", "remote_access", "cloud_base_url", "cloud_access", "private_network_base_url", "private_network_access"):
            if key in existing:
                manifest[key] = existing[key]
    existing_manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    existing_manifest.chmod(0o600)
    shutil.copyfile(HERE / "README.md", home / "README.md")
    (home / "README.md").chmod(0o600)
    (home / "openapi.json").write_text(json.dumps(dial.openapi(), indent=2) + "\n")
    (home / "openapi.json").chmod(0o600)
    plist_path.parent.mkdir(parents=True, exist_ok=True)
    config = {"Label": label, "ProgramArguments": [python, str(runtime / "dial_history.py"), "serve"],
              "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10, "Umask": 0o077,
              "StandardOutPath": str(runtime / "service.log"), "StandardErrorPath": str(runtime / "service-error.log")}
    if loaded:
        subprocess.run(["launchctl", "bootout", target + "/" + label], check=True, capture_output=True)
    plist_path.write_bytes(plistlib.dumps(config))
    plist_path.chmod(0o600)
    subprocess.run(["launchctl", "bootstrap", target, str(plist_path)], check=True, capture_output=True)
    print(json.dumps({"manifest": str(existing_manifest), "command": str(command), "service": label}))


if __name__ == "__main__":
    main()
