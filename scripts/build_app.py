#!/usr/bin/env python3
"""Build an ad-hoc signed App from tracked inputs; never launch or install it."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


def macho_build_version(executable):
    output = subprocess.check_output(['otool', '-l', str(executable)], text=True)
    match = re.search(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \d+\s+minos ([\d.]+)\s+sdk ([\d.]+)', output)
    if not match:
        raise SystemExit(f'Missing Mach-O build version: {executable}')
    return {'minimum_os': match[1], 'sdk': match[2]}


def verify_linked_sdk(executable, expected_sdk):
    version = macho_build_version(executable)
    components = lambda value: tuple(int(part) for part in (value.split('.') + ['0', '0'])[:3])
    if components(version['sdk']) != components(expected_sdk):
        raise SystemExit(f"Refusing mismatched linked SDK {version['sdk']} (expected {expected_sdk}): {executable}")
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/iFanControl.app')
    parser.add_argument('--version')
    parser.add_argument('--build', type=int)
    parser.add_argument('--channel', choices=['stable', 'beta'])
    args = parser.parse_args()
    output = args.output.resolve()
    if output.name != 'iFanControl.app' or not output.is_relative_to(ROOT / 'build'):
        parser.error('--output must be an iFanControl.app inside this checkout\'s build/ directory')
    template = ROOT / 'packaging/app/Info.plist'
    info = plistlib.loads(template.read_bytes())
    if args.version:
        if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
            parser.error('--version must be X.Y.Z')
        info['CFBundleShortVersionString'] = args.version
    if args.build is not None:
        if args.build < 1:
            parser.error('--build must be positive')
        info['CFBundleVersion'] = str(args.build)
    if args.channel == 'beta':
        info['IFanControlReleaseChannel'] = 'beta'
    elif args.channel == 'stable':
        info.pop('IFanControlReleaseChannel', None)
    sdk_path = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    sdk_version = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip()
    # Swift 6.4's swiftbuild engine records the deployment target as the linked
    # SDK (13.0 here), which makes AppKit use its pre-Liquid Glass controls.
    # The native engine preserves the real SDK; check the executable as well.
    build_command = ['swift', 'build', '-c', 'release', '--build-system', 'native', '--sdk', sdk_path]
    run(*build_command)
    bin_path = Path(subprocess.check_output([*build_command, '--show-bin-path'], cwd=ROOT, text=True).strip())
    build_version = verify_linked_sdk(bin_path / 'MacFanControl', sdk_version)
    if output.exists():
        shutil.rmtree(output)  # Only this generated bundle under build/ is replaced.
    (output / 'Contents/MacOS').mkdir(parents=True)
    (output / 'Contents/Resources').mkdir()
    shutil.copy2(bin_path / 'MacFanControl', output / 'Contents/MacOS/iFanControl')
    shutil.copy2(ROOT / 'icon.png', output / 'Contents/Resources/icon.png')
    resources = bin_path / 'MacFanControl_MacFanControl.bundle'
    shutil.copytree(resources, output / 'Contents/Resources' / resources.name)
    if args.version is None and args.build is None and args.channel is None:
        shutil.copy2(template, output / 'Contents/Info.plist')
    else:
        (output / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('codesign', '--force', '--sign', '-', output)
    run('codesign', '--verify', '--strict', output)
    verify_linked_sdk(output / 'Contents/MacOS/iFanControl', sdk_version)
    record = {
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)),
        'version': info['CFBundleShortVersionString'],
        'build': int(info['CFBundleVersion']),
        'channel': info.get('IFanControlReleaseChannel', 'stable'),
        'build_system': 'native',
        'sdk_path': sdk_path,
        'sdk_version': sdk_version,
        'macho_build_version': build_version,
        'app': str(output.relative_to(ROOT)),
        'executable_sha256': hashlib.sha256((output / 'Contents/MacOS/iFanControl').read_bytes()).hexdigest(),
        'info_plist_sha256': hashlib.sha256((output / 'Contents/Info.plist').read_bytes()).hexdigest(),
        'icon_sha256': hashlib.sha256((ROOT / 'icon.png').read_bytes()).hexdigest(),
        'brand_assets_sha256': {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / 'Sources/MacFanControl/Resources/Brand').glob('*.pdf'))
        },
    }
    (output.parent / 'app-build.json').write_text(json.dumps(record, indent=2) + '\n')
    print(f"Built {record['version']} / {record['channel']} / build {record['build']}: {output}")
    print('No application launched or installed.')


if __name__ == '__main__':
    main()
