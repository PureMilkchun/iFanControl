#!/usr/bin/env python3
"""Build a native PKG from a local App/tool or verified legacy ZIP; never install it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from zoneinfo import ZoneInfo
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parent
DOCS = ROOT.parents[2] / "docs"
IDENTIFIER = "com.ifancontrol.pkg"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Use a locally rebuilt App")
    parser.add_argument("--tool", type=Path, help="Use a local kentsmc with --app (no ZIP or manifest required)")
    parser.add_argument("--source-zip", type=Path, default=DOCS / "iFanControl-macOS.zip")
    parser.add_argument("--manifest", type=Path, default=DOCS / "update-manifest.json")
    parser.add_argument("--output", type=Path, default=ROOT / "output")
    arguments = parser.parse_args()
    archive = None
    archive_checksum = None
    if arguments.tool:
        assert arguments.app and arguments.app.is_dir() and arguments.tool.is_file(), "--tool requires a valid --app and kentsmc"
        source_info = plistlib.loads((arguments.app / "Contents/Info.plist").read_bytes())
        version = source_info["CFBundleShortVersionString"]
        build = int(source_info["CFBundleVersion"])
    else:
        manifest = json.loads(arguments.manifest.read_text())
        archive = arguments.source_zip
        archive_checksum = manifest["assets"]["sha256"]
        assert sha256(archive) == archive_checksum, "ZIP checksum differs from manifest"
        version, build = manifest["latest_version"], manifest["latest_build"]
    package_version = f"{version}.{build}"
    output = arguments.output
    output.mkdir(parents=True, exist_ok=True)
    package = output / f"iFanControl-{version}.pkg"

    for script in (ROOT / "scripts").iterdir():
        script.chmod(0o755)
        run("/bin/bash", "-n", script)
        for command in re.findall(r"(?<![\w/.-])(/(?:usr/(?:s?bin)|s?bin)/[A-Za-z0-9_-]+)", script.read_text()):
            assert Path(command).is_file() and os.access(command, os.X_OK), f"Missing system command in {script.name}: {command}"

    with tempfile.TemporaryDirectory(prefix="ifan-pkg-build-") as temp:
        work = Path(temp)
        payload = work / "payload"
        app = payload / "Applications/iFanControl.app"
        tool = payload / "usr/local/bin/kentsmc"
        rule = payload / "private/etc/sudoers.d/kentsmc"

        if archive:
            with zipfile.ZipFile(archive) as source:
                for entry in source.infolist():
                    if entry.filename.startswith("iFanControl.app/"):
                        relative = Path(entry.filename)
                        assert ".." not in relative.parts and not relative.is_absolute()
                        target = payload / "Applications" / relative
                    elif entry.filename == "kentsmc":
                        target = tool
                    else:
                        continue
                    if entry.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(source.read(entry))
                        target.chmod((entry.external_attr >> 16) & 0o777 or 0o644)

        if arguments.app:
            assert arguments.app.is_dir(), "Local App does not exist"
            if app.exists():
                shutil.rmtree(app)
            shutil.copytree(arguments.app, app, symlinks=True)
        if arguments.tool:
            tool.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(arguments.tool, tool)
        assert app.is_dir() and tool.is_file()
        assert not list(app.rglob("config.json")), "Do not package user configuration"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == "com.ifancontrol.app"
        assert info["CFBundleShortVersionString"] == version
        assert info["CFBundleVersion"] == str(build)
        run("/usr/bin/codesign", "--verify", "--strict", app)
        run("/usr/bin/codesign", "--verify", tool)

        installer_resources = work / "resources"
        installer_resources.mkdir()
        # A 128 px image at 144 dpi is 64 pt in Cocoa's rich-text importer.
        # The original large PNG otherwise reopens at its full natural size.
        installer_icon = work / "AppIcon.png"
        run("/usr/bin/sips", "--resampleHeightWidth", "128", "128",
            "--setProperty", "dpiWidth", "144", "--setProperty", "dpiHeight", "144",
            app / "Contents/Resources/icon.png", "--out", installer_icon)
        run("/usr/bin/swift", ROOT / "render_welcome.swift",
            installer_icon, ROOT / "resources/Welcome.json",
            installer_resources / "Welcome.rtfd")
        run("/usr/bin/swift", ROOT / "render_open_hint.swift", installer_resources)

        rule.parent.mkdir(parents=True, exist_ok=True)
        rule.write_text("%admin ALL=(ALL) NOPASSWD: /usr/local/bin/kentsmc\n")
        rule.chmod(0o440)
        tool.chmod(0o755)
        run("/usr/sbin/visudo", "-c", "-f", rule)

        components = work / "components.plist"
        run("/usr/bin/pkgbuild", "--analyze", "--root", payload, components)
        component_info = plistlib.loads(components.read_bytes())
        for component in component_info:
            component["BundleIsRelocatable"] = False
            component["BundleIsVersionChecked"] = True
            component["BundleHasStrictIdentifier"] = True
            component["BundleOverwriteAction"] = "upgrade"
        components.write_bytes(plistlib.dumps(component_info))

        component_package = work / "iFanControl-component.pkg"
        run("/usr/bin/pkgbuild", "--root", payload, "--identifier", IDENTIFIER,
            "--version", package_version, "--install-location", "/",
            "--ownership", "recommended", "--component-plist", components,
            "--scripts", ROOT / "scripts", component_package)

        # Keep permissions on existing shared parent directories. The
        # postinstall script explicitly sets permissions on our own files.
        component_expanded = work / "component-expanded"
        run("/usr/sbin/pkgutil", "--expand", component_package, component_expanded)
        package_info_path = component_expanded / "PackageInfo"
        package_info = ET.parse(package_info_path)
        package_info.getroot().set("overwrite-permissions", "false")
        package_info.write(package_info_path, encoding="utf-8", xml_declaration=True)
        component_package.unlink()
        run("/usr/sbin/pkgutil", "--flatten", component_expanded, component_package)

        requirements = work / "requirements.plist"
        requirements.write_bytes(plistlib.dumps({"os": ["26.0"], "arch": ["arm64"]}))
        distribution = work / "Distribution.xml"
        run("/usr/bin/productbuild", "--synthesize", "--product", requirements,
            "--package", component_package, distribution)
        tree = ET.parse(distribution)
        xml_root = tree.getroot()
        title = xml_root.find("title")
        if title is None:
            title = ET.SubElement(xml_root, "title")
        title.text = "iFanControl"
        options = xml_root.find("options")
        if options is None:
            options = ET.SubElement(xml_root, "options")
        options.set("customize", "never")
        options.set("rootVolumeOnly", "true")
        options.set("hostArchitectures", "arm64")
        domains = xml_root.find("domains")
        if domains is None:
            domains = ET.SubElement(xml_root, "domains")
        domains.attrib.update(enable_anywhere="false", enable_currentUserHome="false", enable_localSystem="true")
        # Omitting a custom conclusion lets Installer display its native
        # success indicator. There is no extra readme page to click through.
        ET.SubElement(xml_root, "welcome", {"file": "Welcome.rtfd", "uti": "com.apple.flat-rtfd"})
        for element, filename in (("background", "OpenHint.pdf"),
                                  ("background-darkAqua", "OpenHint-dark.pdf")):
            ET.SubElement(xml_root, element, {"file": filename, "mime-type": "application/pdf",
                                             "alignment": "bottomleft", "scaling": "none"})
        ET.indent(tree)
        tree.write(distribution, encoding="utf-8", xml_declaration=True)
        run("/usr/bin/productbuild", "--distribution", distribution,
            "--package-path", work, "--resources", installer_resources, package)

        expanded = work / "expanded"
        run("/usr/sbin/pkgutil", "--expand-full", package, expanded)
        expanded_payload = expanded / "iFanControl-component.pkg/Payload"
        assert sha256(expanded / "Resources/Welcome.rtfd") == sha256(installer_resources / "Welcome.rtfd")
        for filename in ("OpenHint.pdf", "OpenHint-dark.pdf"):
            assert sha256(expanded / "Resources" / filename) == sha256(installer_resources / filename)
        assert ET.parse(expanded / "Distribution").getroot().find("conclusion") is None
        assert ET.parse(expanded / "Distribution").getroot().find("readme") is None
        assert ET.parse(expanded / "iFanControl-component.pkg/PackageInfo").getroot().get("overwrite-permissions") == "false"
        expanded_app = expanded_payload / "Applications/iFanControl.app"
        for source_file in app.rglob("*"):
            if source_file.is_file():
                counterpart = expanded_app / source_file.relative_to(app)
                assert counterpart.is_file() and sha256(source_file) == sha256(counterpart)
        assert sha256(tool) == sha256(expanded_payload / "usr/local/bin/kentsmc")
        assert rule.read_bytes() == (expanded_payload / "private/etc/sudoers.d/kentsmc").read_bytes()
        for script in (ROOT / "scripts").iterdir():
            assert script.read_bytes() == (expanded / "iFanControl-component.pkg/Scripts" / script.name).read_bytes()
        run("/usr/bin/codesign", "--verify", "--strict", expanded_app)
        run("/usr/bin/codesign", "--verify", expanded_payload / "usr/local/bin/kentsmc")
        shutil.copy2(distribution, output / "Distribution.xml")

    checksum = sha256(package)
    (output / f"{package.name}.sha256").write_text(f"{checksum}  {package.name}\n")
    (output / "build-info.json").write_text(json.dumps({
        "built_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds"),
        "source_zip": str(archive) if archive else None, "source_zip_sha256": archive_checksum,
        "tool_source": str(arguments.tool.resolve()) if arguments.tool else "verified legacy ZIP",
        "app_source": str(arguments.app.resolve()) if arguments.app else "published ZIP",
        "app_executable_sha256": sha256(arguments.app / "Contents/MacOS/iFanControl") if arguments.app else None,
        "app_version": version, "app_build": build, "package_version": package_version,
        "package_identifier": IDENTIFIER, "package": str(package), "sha256": checksum,
        "signed": False, "notarized": False, "minimum_os": "26.0", "architecture": "arm64",
        "verification": ["local App/tool inputs" if arguments.tool else "ZIP matches manifest", "payload hashes match selected App and tool",
                         "existing ad-hoc code signatures valid", "shell syntax valid", "system command paths executable", "sudoers syntax valid"],
        "installation_tested": False,
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"\nBuilt release package: {package}\nSHA256: {checksum}\nNo installation performed.")


if __name__ == "__main__":
    main()
