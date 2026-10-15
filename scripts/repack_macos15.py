#!/usr/bin/env python3
"""Re-sign existing 52/71 Apps for macOS15; no compilation or installation."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import zipfile

FALLBACK = "https://github.com/PureMilkchun/iFanControl/releases/tag/v2.9.8"
NOTICE = "若出现兼容性问题，可前往 GitHub 下载 2.9.8：" + FALLBACK


def sha(data):
    return hashlib.sha256(data).hexdigest()


def sections(data):
    """Hash every file-backed Mach-O program section, excluding signatures."""
    assert struct.unpack_from("<I", data)[0] == 0xfeedfacf
    count = struct.unpack_from("<I", data, 16)[0]
    offset, result = 32, {}
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        if command == 0x19:
            section_count = struct.unpack_from("<I", data, offset + 64)[0]
            for i in range(section_count):
                entry = offset + 72 + i * 80
                name = data[entry:entry + 16].split(b"\0")[0].decode()
                segment = data[entry + 16:entry + 32].split(b"\0")[0].decode()
                length, start = struct.unpack_from("<QI", data, entry + 40)
                flags = struct.unpack_from("<I", data, entry + 64)[0]
                if start and length and flags & 0xff not in (1, 12, 18):
                    result[segment + "," + name] = sha(data[start:start + length])
        offset += size
    assert result
    return result


def promote(app, expected_version, expected_build):
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    assert (info["CFBundleShortVersionString"], info["CFBundleVersion"]) == (expected_version, str(expected_build))
    assert info["LSMinimumSystemVersion"] == "26.0"
    executable = app / "Contents/MacOS/iFanControl"
    before = sections(executable.read_bytes())
    info["LSMinimumSystemVersion"] = "15.0"
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    assert sections(executable.read_bytes()) == before, "Program sections changed"
    return {"version": expected_version, "build": expected_build, "minimum_os": "15.0",
            "program_sections_identical": before, "executable_sha256": sha(executable.read_bytes())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy-zip", required=True, type=Path)
    parser.add_argument("--stable-app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    assert sha(args.legacy_zip.read_bytes()) == "b80296cbd80e7878e476e9dce0a1aaf03acea1decadf6d628d3743680771610d"
    legacy = args.output / "legacy52"
    stable = args.output / "stable71/iFanControl.app"
    assert not legacy.exists() and not stable.exists(), "Use a fresh output folder"
    with zipfile.ZipFile(args.legacy_zip) as source:
        for entry in source.infolist():
            relative = Path(entry.filename)
            assert not relative.is_absolute() and ".." not in relative.parts
            target = legacy / relative
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read(entry))
                target.chmod((entry.external_attr >> 16) & 0o777 or 0o644)
        reports = [promote(legacy / "iFanControl.app", "2.9.9", 52)]
        shutil.copytree(args.stable_app, stable, symlinks=True)
        reports.append(promote(stable, "3.0.0", 71))
        for name, note in [("README.md", NOTICE), ("README_EN.md", "If you encounter compatibility issues, download 2.9.8 from GitHub: " + FALLBACK)]:
            path = legacy / name
            path.write_text(note + "\n\n" + path.read_text())
        html = legacy / "安装说明.html"
        html.write_text(html.read_text().replace("<body>", '<body>\n<p>若出现兼容性问题，可前往 <a href="' + FALLBACK + '">GitHub 下载 2.9.8</a>。</p>', 1))
        installer = legacy / "install.sh"
        text = installer.read_text()
        anchor = "# 步骤 0: 检查必要文件"
        # Read OS version and refuse unsupported manual installs before mutation.
        block = ('printf "%s\\n" "macOS 15+ / Apple Silicon" "' + NOTICE + '"\n'
                 'IFAN_OS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d . -f 1)"\n'
                 'if ! [[ "$IFAN_OS_MAJOR" =~ ^[0-9]+$ ]] || [ "$IFAN_OS_MAJOR" -lt 15 ]; then\n'
                 '    echo "iFanControl 需要 macOS 15 或更新版本；请保留 2.9.8。"\n'
                 '    exit 1\nfi\n\n')
        assert text.count(anchor) == 1
        installer.write_text(text.replace(anchor, block + anchor))
        subprocess.run(["/bin/bash", "-n", str(installer)], check=True)
        archive = args.output / "iFanControl-macOS-2.9.9.zip"
        changed = []
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as dest:
            for entry in source.infolist():
                data = (legacy / entry.filename).read_bytes() if not entry.is_dir() else b""
                if data != source.read(entry):
                    changed.append(entry.filename)
                dest.writestr(copy.copy(entry), data)
        assert (legacy / "kentsmc").read_bytes() == source.read("kentsmc")
    assert b"update-manifest-pkg.json" in (legacy / "iFanControl.app/Contents/MacOS/iFanControl").read_bytes()
    record = {"application_recompiled": False, "actual_installation_performed": False,
              "tool_unchanged": True, "apps": reports, "legacy_changed_entries": changed,
              "legacy_archive_sha256": sha(archive.read_bytes()), "fallback_url": FALLBACK}
    (args.output / "repack-verification.json").write_text(json.dumps(record, indent=2) + "\n")
    print("PASS: 52/71 re-signed; all program sections and tool preserved; ZIP syntax valid.")


if __name__ == "__main__":
    main()
