#!/usr/bin/env python3
"""Compile real native controllers with isolated config/defaults and external-effect seams."""
from pathlib import Path
import subprocess, tempfile, plistlib, uuid
from native_test_bridge import compile_test_bridge
ROOT=Path(__file__).resolve().parents[2]
expr='FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MacFanControl")'
with tempfile.TemporaryDirectory(prefix='ifan-ui-tests-') as d:
    out=Path(d); config=out/'config'; replacement='URL(fileURLWithPath: "'+str(config)+'", isDirectory:true)'
    bridge_map,bridge_object=compile_test_bridge(out)
    app=out/'UITests.app';(app/'Contents/MacOS').mkdir(parents=True)
    domain='com.ifancontrol.ui-regression.'+str(uuid.uuid4())
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':domain,'CFBundleExecutable':'UITests','CFBundlePackageType':'APPL','CFBundleShortVersionString':'2.9.10','CFBundleVersion':'64'}))
    curve=(ROOT/'Sources/FanCurveEditor/FanCurveWindow.swift').read_text().replace(expr,replacement).replace('NSAlert()','NativeUITestAlert()')
    curve+='''\n@MainActor enum UIRegressionPaths { static let config = '''+replacement+''' }
@MainActor class NativeUITestAlert: NSAlert {
    static var lastMessage = ""
    override func runModal() -> NSApplication.ModalResponse { Self.lastMessage=messageText;return .alertFirstButtonReturn }
}
'''+(ROOT/'packaging/pkg/test_curve_ui.swift').read_text()
    (out/'FanCurveWindow.swift').write_text(curve)
    module=out/'libFanCurveEditor.dylib'
    subprocess.run(['swiftc','-swift-version','6','-emit-library','-emit-module','-emit-module-path',str(out/'FanCurveEditor.swiftmodule'),'-module-name','FanCurveEditor',str(ROOT/'Sources/FanCurveEditor/FanCurveView.swift'),str(out/'FanCurveWindow.swift'),'-o',str(module)],check=True)
    s=(ROOT/'Sources/MacFanControl/main.swift').read_text().split('// 主函数')[0].replace(expr,replacement)
    a=s.index('    private init() {',s.index('final class PowerTelemetryReader'));b=s.index('    var snapshot:',a)
    s=s[:a]+'    private init() {}\n\n'+s[b:]
    a=s.index('    func sendFeedback(content: String, email: String) async -> Bool {');b=s.index('\n}\n\n@MainActor\nclass SafetyFloorWindowController',a)
    s=s[:a]+'''    func sendFeedback(content: String, email: String) async -> Bool {
        try? await Task.sleep(for:.milliseconds(20));return !content.contains("fail")
    }
'''+s[b:]
    s+='\n'+(ROOT/'packaging/pkg/test_ui.swift').read_text()+'''
let application=NSApplication.shared
application.setActivationPolicy(.accessory)
Task { @MainActor in
    let domain=Bundle.main.bundleIdentifier!
    precondition(domain.hasPrefix("com.ifancontrol.ui-regression."))
    UserDefaults.standard.removePersistentDomain(forName:domain)
    do {
        try FanCurvePresetWindowController.runUIRegression()
        DisplaySettingsWindowController.runUIRegression()
        PowerConsumptionWindowController.runUIRegression()
        HelpWindowController.runUIRegression()
        try await FeedbackWindowController.runUIRegression()
        UserDefaults.standard.removePersistentDomain(forName:domain)
        print("PASS: isolated native UI controller regressions")
        exit(0)
    } catch { print("FAIL: \\(error)");UserDefaults.standard.removePersistentDomain(forName:domain);exit(1) }
}
application.run()
'''
    (out/'main.swift').write_text(s)
    files=[str(out/'main.swift')]+[str(p) for p in (ROOT/'Sources/MacFanControl').glob('*.swift') if p.name!='main.swift']
    subprocess.run(['swiftc','-swift-version','6','-I',str(out),'-L',str(out),'-lFanCurveEditor','-Xcc','-fmodule-map-file='+str(bridge_map),str(bridge_object),*files,'-framework','AppKit','-framework','ServiceManagement','-lIOReport','-o',str(app/'Contents/MacOS/UITests')],check=True)
    subprocess.run([str(app/'Contents/MacOS/UITests'),'-ifancontrol.ui.language','en'],check=True,timeout=20)
