#!/usr/bin/env python3
"""Exercise the real menu with isolated preferences, config and simulated telemetry."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

from native_test_bridge import compile_test_bridge

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_app import verify_linked_sdk

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--case', choices=['zh-light', 'zh-dark', 'en-light', 'en-dark'])
parser.add_argument('--built-app', type=Path, help='Require matching SDK and deployment target with the packaged App')
args = parser.parse_args()
target = None
compiler_flags = []
artifact = None
sdk_version = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip()
if args.built_app:
    executable = args.built_app.resolve() / 'Contents/MacOS/iFanControl'
    artifact = verify_linked_sdk(executable, sdk_version)
    artifact['executable_sha256'] = hashlib.sha256(executable.read_bytes()).hexdigest()
    target = f"{platform.machine()}-apple-macosx{artifact['minimum_os']}"
    compiler_flags = ['-target', target, '-sdk', subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
expr = 'FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")'
with tempfile.TemporaryDirectory(prefix='ifan-menu-speed-') as temp:
    out = Path(temp)
    replacement = 'URL(fileURLWithPath: "' + str(out / 'config') + '", isDirectory: true)'
    bridge_map, bridge_object = compile_test_bridge(out, target=target)
    app = out / 'MenuSpeedTests.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    shutil.copytree(ROOT / 'Sources/MacFanControl/Resources/Brand', app / 'Contents/Resources/Brand')
    info = plistlib.loads((ROOT / 'packaging/app/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='com.ifancontrol.menu-speed-test.' + str(uuid.uuid4()), CFBundleExecutable='MenuSpeedTests')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    curve = (ROOT / 'Sources/FanCurveEditor/FanCurveWindow.swift').read_text().replace(expr, replacement)
    (out / 'FanCurveWindow.swift').write_text(curve)
    subprocess.run(['swiftc', *compiler_flags, '-swift-version', '6', '-emit-library', '-emit-module', '-emit-module-path', str(out / 'FanCurveEditor.swiftmodule'), '-module-name', 'FanCurveEditor', str(ROOT / 'Sources/FanCurveEditor/FanCurveView.swift'), str(out / 'FanCurveWindow.swift'), '-o', str(out / 'libFanCurveEditor.dylib')], check=True)
    source = (ROOT / 'Sources/MacFanControl/main.swift').read_text().split('// 主函数')[0].replace(expr, replacement)
    needle = '    func availableTemperatureReadings() -> [TemperatureReading] {\n        refreshTelemetry()'
    assert source.count(needle) == 1
    source = source.replace(needle, '    func availableTemperatureReadings() -> [TemperatureReading] {')
    start = source.index('    private init() {', source.index('final class PowerTelemetryReader'))
    end = source.index('    var snapshot:', start)
    source = source[:start] + '    private init() {}\n\n' + source[end:]
    log_base = '''let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("iFanControl")'''
    assert source.count(log_base) == 1
    source = source.replace(log_base, 'let base = URL(fileURLWithPath: "' + str(out / 'logs') + '", isDirectory: true)')
    source += '\n@MainActor enum MenuTestPaths { static let configDirectory = ' + replacement + ' }\n'
    source += '\n' + (ROOT / 'packaging/pkg/test_menu_speed.swift').read_text()
    (out / 'main.swift').write_text(source)
    files = [str(out / 'main.swift')] + [str(p) for p in (ROOT / 'Sources/MacFanControl').glob('*.swift') if p.name != 'main.swift']
    subprocess.run(['swiftc', *compiler_flags, '-swift-version', '6', '-I', str(out), '-L', str(out), '-lFanCurveEditor', '-Xcc', '-fmodule-map-file=' + str(bridge_map), str(bridge_object), *files, '-framework', 'AppKit', '-framework', 'ServiceManagement', '-lIOReport', '-o', str(app / 'Contents/MacOS/MenuSpeedTests')], check=True)
    fixture_version = verify_linked_sdk(app / 'Contents/MacOS/MenuSpeedTests', sdk_version)
    cases = [tuple(args.case.split('-'))] if args.case else [('zh', 'light'), ('zh', 'dark'), ('en', 'light'), ('en', 'dark')]
    for language, theme in cases:
        subprocess.run([str(app / 'Contents/MacOS/MenuSpeedTests'), '-ifancontrol.ui.language', language], env={**os.environ, 'IFAN_MENU_TEST_OUTPUT': str(output), 'IFAN_MENU_TEST_THEME': theme}, check=True, timeout=20)
        result_path = output / f'{language}-{theme}-results.json'
        result = json.loads(result_path.read_text())
        result['fixture_build_version'] = fixture_version
        result['verified_built_app'] = artifact
        result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
