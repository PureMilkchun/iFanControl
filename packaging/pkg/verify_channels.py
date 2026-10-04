#!/usr/bin/env python3
"""Check the frozen legacy channel and the current native PKG channel before deployment."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
from urllib.parse import urlparse
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def verify(docs, pin):
    legacy = json.loads((docs / "update-manifest.json").read_text())
    latest = json.loads((docs / "update-manifest-pkg.json").read_text())
    for key in ("latest_version", "latest_build", "assets"):
        assert legacy[key] == pin[key], f"Frozen legacy channel changed: {key}"
    assert legacy["latest_version"] == "2.9.9" and legacy["latest_build"] == 52
    assert latest["latest_build"] >= 52
    assert "macos_arm64_zip_url" not in latest["assets"], "Native channel must only offer PKG"
    assert "macos_arm64_pkg_url" not in legacy["assets"], "Keep legacy channel isolated"

    archive = docs / Path(urlparse(legacy["assets"]["macos_arm64_zip_url"]).path).name
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == legacy["assets"]["sha256"]
    # Retain the old fallback URL as the same frozen archive.
    assert (docs / "iFanControl-macOS.zip").read_bytes() == archive.read_bytes()
    with zipfile.ZipFile(archive) as z:
        assert "install.sh" in z.namelist() and "kentsmc" in z.namelist()
        assert not any(Path(name).name == "config.json" for name in z.namelist())
        info = plistlib.loads(z.read("iFanControl.app/Contents/Info.plist"))
        assert info["CFBundleShortVersionString"] == "2.9.9" and info["CFBundleVersion"] == "52"
        assert b"update-manifest-pkg.json" in z.read("iFanControl.app/Contents/MacOS/iFanControl")

    package = docs / Path(urlparse(latest["assets"]["macos_arm64_pkg_url"]).path).name
    assert package.suffix == ".pkg"
    assert hashlib.sha256(package.read_bytes()).hexdigest() == latest["assets"]["pkg_sha256"]
    assert f'?build={latest["latest_build"]}' in latest["assets"]["macos_arm64_pkg_url"]
    print("PASS: legacy channel frozen at 2.9.9/build52; native PKG channel and both artifact hashes valid")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docs", type=Path, default=ROOT.parent / "docs")
    parser.add_argument("--pin", type=Path, default=Path(__file__).with_name("legacy-channel.json"))
    args = parser.parse_args()
    verify(args.docs, json.loads(args.pin.read_text()))
