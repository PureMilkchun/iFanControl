#!/usr/bin/env python3
"""Verify a committed release record against current files or a Git revision."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('record', type=Path)
    parser.add_argument('--ref', help='Git commit or release tag; otherwise checks working files')
    args = parser.parse_args()
    record = json.loads(args.record.read_text())
    for name, expected in record['source_hashes'].items():
        data = subprocess.check_output(['git', 'show', f'{args.ref}:{name}'], cwd=ROOT) if args.ref else (ROOT / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit(f'Release source differs: {name}')
    print(f"PASS: {record['tag']} / {len(record['source_hashes'])} tracked inputs match recorded release")


if __name__ == '__main__':
    main()
