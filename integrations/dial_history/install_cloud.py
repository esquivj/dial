#!/usr/bin/env python3
"""Install an hourly publisher only after the cloud service has been configured."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

import dial_history as dial
from cloud_sync import atomic_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    args = parser.parse_args()
    url = urlsplit(args.base_url)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ("", "/"):
        raise ValueError("Use the verified HTTPS base URL without a path or credentials")
    runtime = dial.RUNTIME
    for name in ("cloud-config.json", "cloud-read-token"):
        path = runtime / name
        if not path.exists() or path.stat().st_mode & 0o077:
            raise ValueError("Missing or non-private cloud config: " + name)
    state = json.loads((runtime / "cloud-sync-state.json").read_text())
    if state.get("status") not in ("synced", "unchanged"):
        raise ValueError("Run and verify the initial cloud sync before installing")
    here = Path(__file__).resolve().parent
    for name in ("dial_history.py", "cloud_store.py", "cloud_sync.py"):
        shutil.copyfile(here / name, runtime / name)
        (runtime / name).chmod(0o600)
    venv = runtime / "cloud-venv"
    if not (venv / "bin/python").exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    # SDK version is pinned and isolated from Dial and the stdlib-only local API.
    subprocess.run([str(venv / "bin/python"), "-m", "pip", "install", "--quiet", "vercel==0.11.6"], check=True)
    label = "com.juanos.dial-history-cloud-sync"
    target = "gui/" + str(os.getuid())
    plist_path = Path.home() / "Library/LaunchAgents" / (label + ".plist")
    loaded = subprocess.run(["launchctl", "print", target + "/" + label], capture_output=True).returncode == 0
    if loaded:
        subprocess.run(["launchctl", "bootout", target + "/" + label], check=True, capture_output=True)
    config = {"Label": label, "ProgramArguments": [str(venv / "bin/python"), str(runtime / "cloud_sync.py")],
              "RunAtLoad": True, "StartInterval": 3600, "ProcessType": "Background", "Umask": 0o077,
              "StandardOutPath": str(runtime / "cloud-sync.log"), "StandardErrorPath": str(runtime / "cloud-sync-error.log")}
    plist_path.write_bytes(plistlib.dumps(config))
    plist_path.chmod(0o600)
    subprocess.run(["launchctl", "bootstrap", target, str(plist_path)], check=True, capture_output=True)
    manifest_path = dial.HOME / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("remote_access", {}).get("transport") == "tailscale_serve":
        manifest["private_network_base_url"] = manifest.get("remote_base_url")
        manifest["private_network_access"] = manifest["remote_access"]
    manifest["cloud_base_url"] = args.base_url.rstrip("/")
    manifest["cloud_access"] = {"transport": "https", "authentication": "Bearer read token; backend only",
        "token_file": str(runtime / "cloud-read-token"), "mode": "private_snapshot", "sync_interval_seconds": 3600,
        "sync_state_file": str(runtime / "cloud-sync-state.json"), "sync_command": config["ProgramArguments"],
        "availability": "Last synced history remains readable while Mac is asleep; new uploads need Mac awake and online."}
    manifest["remote_base_url"] = manifest["cloud_base_url"]
    manifest["remote_access"] = manifest["cloud_access"]
    atomic_json(manifest_path, manifest)
    print(json.dumps({"cloud_base_url": manifest["cloud_base_url"], "sync_interval_seconds": 3600,
                      "manifest": str(manifest_path), "service": label}))


if __name__ == "__main__":
    main()
