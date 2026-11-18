#!/usr/bin/env python3
"""Create a Beta-only return installer from the published stable package and manifest."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

PACKAGE_ID = 'com.ifancontrol.pkg'
BUNDLE_ID = 'com.ifancontrol.app'
COMPONENT = 'iFanControl-component.pkg'
ORIGIN = 'https://ifan-59w.pages.dev'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_xml(tree, path):
    ET.indent(tree)
    tree.write(path, encoding='utf-8', xml_declaration=True)


def remove_version_gate(root):
    for gate in root.findall('bundle-version'):
        root.remove(gate)


def prepare_scripts(scripts, version, build):
    preinstall = scripts / 'preinstall'
    postinstall = scripts / 'postinstall'
    # Run after the original root, startup volume and running-app checks.
    preinstall.write_text(preinstall.read_text().rstrip() + f'''

# This package is only for returning from an installed iFanControl Beta.
BETA_APP="/Applications/iFanControl.app"
BETA_INFO="$BETA_APP/Contents/Info.plist"
if [ ! -d "$BETA_APP" ] || [ -L "$BETA_APP" ] || [ -L "$BETA_APP/Contents" ] || [ ! -f "$BETA_INFO" ] || [ -L "$BETA_INFO" ]; then
    echo "iFanControl: 找不到可回退的 Beta 应用 / No installed Beta app to replace." >&2
    exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BETA_INFO" 2>/dev/null || true)
BUNDLE_CHANNEL=$(/usr/libexec/PlistBuddy -c 'Print :IFanControlReleaseChannel' "$BETA_INFO" 2>/dev/null || true)
BUNDLE_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BETA_INFO" 2>/dev/null || true)
if [ "$BUNDLE_ID" != "{BUNDLE_ID}" ] || [ "$BUNDLE_CHANNEL" != "beta" ]; then
    echo "iFanControl: 回退包仅用于 Beta / This installer requires an installed iFanControl Beta." >&2
    exit 1
fi
case "$BUNDLE_BUILD" in
    ''|*[!0-9]*) exit 1 ;;
esac
if ! [ "$BUNDLE_BUILD" -ge {build} ]; then
    echo "iFanControl: 请使用普通正式版安装包 / Use the standard installer for a newer stable release." >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$BETA_APP"
''')
    postinstall.write_text(postinstall.read_text().rstrip() + f'''

# Ensure Installer really replaced the newer bundle, before reporting success.
RESTORED_INFO="/Applications/iFanControl.app/Contents/Info.plist"
RESTORED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$RESTORED_INFO")
RESTORED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$RESTORED_INFO")
RESTORED_CHANNEL=$(/usr/libexec/PlistBuddy -c 'Print :IFanControlReleaseChannel' "$RESTORED_INFO" 2>/dev/null || true)
if [ "$RESTORED_VERSION" != "{version}" ] || [ "$RESTORED_BUILD" != "{build}" ] || [ "$RESTORED_CHANNEL" = "beta" ]; then
    echo "iFanControl: 未确认正式版已安装 / Could not confirm installation of the stable app." >&2
    exit 1
fi
''')
    for script in (preinstall, postinstall):
        run('/bin/bash', '-n', script)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stable-package', required=True, type=Path)
    parser.add_argument('--stable-manifest', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    stable = json.loads(args.stable_manifest.read_bytes())
    version, build = stable['latest_version'], stable['latest_build']
    require(stable.get('release_channel') == 'stable', 'Expected the stable update feed')
    require(isinstance(version, str) and re.fullmatch(r'\d+\.\d+\.\d+', version), 'Invalid stable version')
    require(type(build) is int and 0 < build <= 2_147_483_647, 'Invalid stable build')
    source_hash = sha256(args.stable_package)
    require(source_hash == stable['assets']['pkg_sha256'].lower(), 'Stable package does not match the live manifest')
    args.output.mkdir(parents=True, exist_ok=True)
    package = args.output / f'iFanControl-stable-restore-{version}-{build}-{source_hash[:12]}.pkg'

    with tempfile.TemporaryDirectory(prefix='ifan-stable-restore-') as folder:
        work = Path(folder)
        source = work / 'source'
        run('/usr/sbin/pkgutil', '--expand', args.stable_package, source)
        component = source / COMPONENT
        info = ET.parse(component / 'PackageInfo')
        root = info.getroot()
        require(root.attrib['identifier'] == PACKAGE_ID and root.attrib['version'] == f'{version}.{build}', 'Wrong package receipt')
        require(root.find(f"upgrade-bundle/bundle[@id='{BUNDLE_ID}']") is not None, 'Expected atomic bundle replacement')
        require(root.find(f"strict-identifier/bundle[@id='{BUNDLE_ID}']") is not None, 'Expected strict bundle identity')
        require(root.find('relocate/bundle') is None, 'The recovery installer must target Applications')
        require(root.find('bundle-version') is not None, 'Expected bundle version guard in source package')
        original_layers = {name: sha256(component / name) for name in ('Payload', 'Bom')}
        remove_version_gate(root)
        write_xml(info, component / 'PackageInfo')
        prepare_scripts(component / 'Scripts', version, build)

        distribution = ET.parse(source / 'Distribution')
        for ref in distribution.getroot().findall(f"pkg-ref[@id='{PACKAGE_ID}']"):
            remove_version_gate(ref)
        write_xml(distribution, source / 'Distribution')
        staged = work / package.name
        run('/usr/sbin/pkgutil', '--flatten', source, staged)

        verify = work / 'verify'
        run('/usr/sbin/pkgutil', '--expand-full', staged, verify)
        installed = verify / COMPONENT / 'Payload/Applications/iFanControl.app'
        plist = plistlib.loads((installed / 'Contents/Info.plist').read_bytes())
        require(plist.get('CFBundleIdentifier') == BUNDLE_ID, 'Unexpected stable payload bundle')
        require(plist.get('CFBundleShortVersionString') == version and str(plist.get('CFBundleVersion')) == str(build), 'Wrong stable payload version')
        require(plist.get('IFanControlReleaseChannel', 'stable') == 'stable', 'Refusing to publish a Beta payload as stable')
        run('/usr/bin/codesign', '--verify', '--strict', installed)
        run('/usr/bin/codesign', '--verify', verify / COMPONENT / 'Payload/usr/local/bin/kentsmc')
        # Check raw compressed payload and BOM round-trip, including all app and tool bytes.
        raw = work / 'raw'
        run('/usr/sbin/pkgutil', '--expand', staged, raw)
        require(all(sha256(raw / COMPONENT / name) == digest for name, digest in original_layers.items()), 'Installer payload changed during the rewrite')
        require(ET.parse(raw / COMPONENT / 'PackageInfo').getroot().find('bundle-version') is None, 'Bundle version check still present')
        require(ET.parse(raw / 'Distribution').getroot().find('.//bundle-version') is None, 'Distribution still compares bundle version')
        package.write_bytes(staged.read_bytes())

    manifest = {
        'latest_version': version,
        'latest_build': build,
        'release_channel': 'stable',
        'published_at': datetime.now(timezone.utc).isoformat(),
        'stable_package_sha256': source_hash,
        'assets': {'macos_arm64_pkg_url': f'{ORIGIN}/{package.name}', 'pkg_sha256': sha256(package)},
    }
    (args.output / 'update-manifest-stable-restore.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Built {package.name} from verified stable build {build}. No installation performed.')


if __name__ == '__main__':
    main()
