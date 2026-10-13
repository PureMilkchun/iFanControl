"""Compile the tracked C bridge inside each isolated fixture, on either Mac arch."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def compile_test_bridge(out):
    module = out / 'IOReportBridge.modulemap'
    header = ROOT / 'Sources/IOReportBridge/include/bridge.h'
    module.write_text(f'module IOReportBridge {{ header "{header}" export * }}\n')
    obj = out / 'IOReportBridge.o'
    subprocess.run(['xcrun', 'clang', '-I', str(header.parent), '-c', str(ROOT / 'Sources/IOReportBridge/bridge.c'), '-o', str(obj)], check=True)
    return module, obj
