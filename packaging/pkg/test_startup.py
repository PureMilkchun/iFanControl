#!/usr/bin/env python3
"""Exercise actual launch ordering with isolated state and hardware/network seams."""
from pathlib import Path
import argparse
import plistlib
import subprocess
import tempfile
from native_test_bridge import compile_test_bridge

ROOT = Path(__file__).resolve().parents[2]


def replace_function(source, signature, body):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[:opening + 1] + "\n" + body + "\n    }" + source[end:]


def build(out):
    out.mkdir(parents=True, exist_ok=True)
    bridge_map, bridge_object = compile_test_bridge(out)
    expr = 'FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")'
    config = 'URL(fileURLWithPath: "' + str(out / 'fixture-config') + '", isDirectory: true)'
    curve = (ROOT / 'Sources/FanCurveEditor/FanCurveWindow.swift').read_text().replace(expr, config)
    (out / 'FanCurveWindow.swift').write_text(curve)
    subprocess.run(['swiftc', '-swift-version', '6', '-emit-library', '-emit-module', '-emit-module-path', str(out / 'FanCurveEditor.swiftmodule'), '-module-name', 'FanCurveEditor', str(ROOT / 'Sources/FanCurveEditor/FanCurveView.swift'), str(out / 'FanCurveWindow.swift'), '-o', str(out / 'libFanCurveEditor.dylib')], check=True)
    s = (ROOT / 'Sources/MacFanControl/main.swift').read_text().split('// 主函数')[0].replace(expr, config)
    s = s.replace('let base = FileManager.default.homeDirectoryForCurrentUser\n            .appendingPathComponent("Library")\n            .appendingPathComponent("Logs")\n            .appendingPathComponent("iFanControl")', 'let base = URL(fileURLWithPath: "' + str(out / 'fixture-logs') + '")')
    start = s.index('    private init() {', s.index('final class PowerTelemetryReader'))
    end = s.index('    var snapshot:', start)
    s = s[:start] + '    private init() {}\n\n' + s[end:]
    s = replace_function(s, '    private func executeCommand(args: [String])', '        return (args != ["--unlock-fans"] || !CommandLine.arguments.contains("--unlock-failure"), "", "Fixture failure")')
    s = replace_function(s, '    func refreshHardwareProfile()', '''        LaunchEffects.record("probe")
        precondition(LaunchEffects.loadingVisible)
        precondition(UserDefaults.standard.integer(forKey: "ifancontrol.update.pending_build") > 0)
        if CommandLine.arguments.contains("--slow") { Thread.sleep(forTimeInterval: 6) }
        fanCount = CommandLine.arguments.contains("--fanless") ? 0 : 1
        fans = fanCount == 0 ? [] : [FanInfo(index: 0, actualKey: "F0Ac", minRPM: 0, maxRPM: 4900)]
        availableTemperatureSensors = [TemperatureSensorDefinition(key: "Tp01", name: "CPU")]
        currentMaxRPM = 4900
        cachedTemperatures = ["Tp01": 65]; cachedFanRPMs = fanCount == 0 ? [:] : [0: 2400]
        hasProbedHardware = true
        BackgroundHardwareReader.shared.replaceSnapshotFromMainThread(temperatures: cachedTemperatures, fanRPMs: cachedFanRPMs, reason: "isolated launch fixture")''')
    s = replace_function(s, '    func refreshTelemetry(force: Bool = false)', '        // Fixture profile already seeds the cached telemetry.')
    s = replace_function(s, '    func refresh(sensors: [TemperatureSensorDefinition], fans: [FanInfo])', '        // Never read real hardware from this test.')
    s = s.replace('FanManager.shared.unlockFans()', 'LaunchEffects.record("unlock"); FanManager.shared.unlockFans()')
    s = s.replace('self.controlLoopTimer = timer', 'self.controlLoopTimer = timer\n        LaunchEffects.record("control_loop")')
    s = s.replace('func presentInstalledUpdateIfNeeded() {', 'func presentInstalledUpdateIfNeeded() {\n        LaunchEffects.record("receipt")\n        precondition(!LaunchEffects.loadingVisible)')
    s = s.replace('func maybeShowStartupGuidance() {', 'func maybeShowStartupGuidance() {\n        LaunchEffects.record("guidance")\n        precondition(!LaunchEffects.loadingVisible)\n        DispatchQueue.main.async { LaunchEffects.assertReady() }')
    for action in ['startup', 'shutdown', 'tick']:
        s = s.replace('PrivacyStatsService.shared.' + action + '()', 'LaunchEffects.stats()')
    s = s.replace('NSAlert()', 'LaunchFixtureAlert()')
    s += '\n' + (ROOT / 'packaging/pkg/test_startup.swift').read_text().replace('FIXTURE_OUTPUT', str(out))
    (out / 'main.swift').write_text(s)
    panel = (ROOT / 'Sources/MacFanControl/StartupProgressWindow.swift').read_text()
    panel = panel.replace('progress.startAnimation(nil)', 'progress.startAnimation(nil)\n        precondition(progress.isIndeterminate && progress.usesThreadedAnimation)\n        LaunchEffects.record("present")')
    panel = panel.replace('stageField.stringValue = stage.message', 'stageField.stringValue = stage.message\n        LaunchEffects.record("stage:" + String(describing: stage))')
    panel = panel.replace('window?.orderOut(nil)', 'window?.orderOut(nil)\n        LaunchEffects.record("dismiss")')
    panel = panel.replace('window?.displayIfNeeded()', 'window?.displayIfNeeded()\n        LaunchEffects.capture(window)')
    (out / 'StartupProgressWindow.swift').write_text(panel)
    app = out / 'LaunchValidation.app'
    (app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (app / 'Contents/Resources').mkdir(parents=True, exist_ok=True)
    (app / 'Contents/Resources/icon.png').write_bytes((ROOT / 'icon.png').read_bytes())
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.ifancontrol.startup-test.validation70', 'CFBundleExecutable': 'LaunchValidation', 'CFBundlePackageType': 'APPL', 'CFBundleName': 'iFanControl Startup Validation', 'CFBundleShortVersionString': '2.9.10', 'CFBundleVersion': '70', 'IFanControlReleaseChannel': 'beta'}))
    files = [str(out / 'main.swift'), str(out / 'StartupProgressWindow.swift')] + [str(p) for p in (ROOT / 'Sources/MacFanControl').glob('*.swift') if p.name not in ['main.swift', 'StartupProgressWindow.swift']]
    executable = app / 'Contents/MacOS/LaunchValidation'
    subprocess.run(['swiftc', '-swift-version', '6', '-I', str(out), '-L', str(out), '-lFanCurveEditor', '-Xcc', '-fmodule-map-file=' + str(bridge_map), str(bridge_object), *files, '-framework', 'AppKit', '-framework', 'ServiceManagement', '-lIOReport', '-o', str(executable)], check=True)
    return executable


def test(executable):
    for args in [[], ['--slow'], ['--fanless'], ['--unlock-failure'], ['--future-receipt'], ['--first-launch']]:
        subprocess.run([str(executable), *args], check=True, timeout=20)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    if args.output:
        executable = build(args.output.resolve())
        if not args.build_only:
            test(executable)
    else:
        with tempfile.TemporaryDirectory(prefix='ifan-launch-tests-') as temp:
            test(build(Path(temp)))
