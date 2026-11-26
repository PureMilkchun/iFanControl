#!/usr/bin/env python3
"""Load real brand views from packaged resources with development fallback disabled."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='ifan-packaged-brand-') as directory:
    out = Path(directory)
    app = out / 'BrandResources.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    shutil.copytree(args.app / 'Contents/Resources', app / 'Contents/Resources')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'com.ifancontrol.packaged-brand-test',
        'CFBundleExecutable': 'BrandResources', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    }))
    (out / 'main.swift').write_text('''import AppKit
extension Bundle {
    static nonisolated let module: Bundle = { fatalError("Development resource fallback must not be used") }()
}
@MainActor enum NativeInterface {
    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        return field
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
for style in [BrandIdentity.Wordmark.horizontal, .stacked] {
    let view = BrandIdentity.wordmark(style, width: 200)
    precondition(view is NSImageView, "Packaged wordmark must load instead of falling back to text")
    precondition((view as! NSImageView).image != nil)
}
print("PASS: both real brand views load from packaged resources without development fallback")
''')
    binary = app / 'Contents/MacOS/BrandResources'
    subprocess.run(['swiftc', '-swift-version', '6', '-D', 'SWIFT_PACKAGE',
                    str(ROOT / 'Sources/MacFanControl/BrandIdentity.swift'), str(out / 'main.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
