#!/usr/bin/env python3
"""Compile the actual updater with only network/UI/Installer/quit test seams; never install or control fans."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "Sources/MacFanControl/main.swift").read_text()
service = source.split("// 自动更新服务\n", 1)[1].split("// 菜单栏管理\n", 1)[0]
assert service.count("URLSession.shared") == 1
assert service.count("NSApp.terminate(nil)") == 1
service = service.replace("URLSession.shared", "updateFixtureSession")
service = service.replace("UpdatePackageDownloader()", "UpdatePackageDownloader(configuration: updateFixtureSession.configuration)")
service = service.replace("NSAlert()", "UpdateFixtureAlert()")
service = service.replace("NSWorkspace.shared.open", "UpdateFixtureUI.open")
service = service.replace("NSApp.terminate(nil)", "UpdateFixtureUI.terminate()")
# Completion counters observe the existing task boundaries, removing timing-dependent assertions.
service = service.replace("isChecking = true", "isChecking = true\n        UpdateFixtureUI.checksInFlight += 1")
service = service.replace("defer { isChecking = false; checkTask = nil }", "defer { isChecking = false; checkTask = nil; UpdateFixtureUI.checksInFlight -= 1 }")
service = service.replace("isDownloading = true", "isDownloading = true\n        UpdateFixtureUI.downloadsInFlight += 1")
service = service.replace("defer { isDownloading = false; isTransferring = false; downloader = nil; downloadTask = nil }", "defer { isDownloading = false; isTransferring = false; downloader = nil; downloadTask = nil; UpdateFixtureUI.downloadsInFlight -= 1 }")
with tempfile.TemporaryDirectory(prefix="ifan-service-tests-") as temp:
    work = Path(temp)
    app = work / "UpdaterTests.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    info = {"CFBundleIdentifier": "com.ifancontrol.update-service-test." + str(uuid.uuid4()),
            "CFBundleExecutable": "UpdaterTests", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "2.9.10", "CFBundleVersion": "62"}
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    generated = work / "UpdateService.swift"
    generated.write_text('import AppKit\nimport Foundation\nimport OSLog\n'
                         'private let appSubsystem = "com.ifancontrol.update-service-tests"\n'
                         'private func appL10n(_ zh: String, _ en: String) -> String { zh }\n' + service)
    executable = app / "Contents/MacOS/UpdaterTests"
    subprocess.run(["swiftc", "-swift-version", "6", str(generated),
                    str(ROOT / "Sources/MacFanControl/UpdateManifest.swift"),
                    str(ROOT / "Sources/MacFanControl/UpdatePreferences.swift"),
                    str(ROOT / "Sources/MacFanControl/UpdatePackageDownloader.swift"),
                    str(ROOT / "packaging/pkg/test_update_service.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)
