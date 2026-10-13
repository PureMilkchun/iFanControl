#!/usr/bin/env python3
"""Offline comparison of source declarations; never runs Swift or touches SMC.

This is a catalog audit, not a test of the app or of device compatibility.
The optional upstream directory must contain the exact pinned source files.
"""
import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "docs/development/stats"
HEADER = ["backend", "key", "name", "group", "platforms", "average", "source_line"]


def load_catalog():
    metadata = json.loads((DATA / "upstream.json").read_text())
    with (DATA / "temperature-catalog.csv").open(newline="") as file:
        reader = csv.DictReader(file)
        if reader.fieldnames != HEADER:
            raise ValueError("Unexpected snapshot columns")
        rows = list(reader)
    if len(rows) != metadata["temperature_row_count"]:
        raise ValueError("Incomplete snapshot")
    allowed = set(metadata["platform_sets"]["all"])
    identities = set()
    for row in rows:
        if row["backend"] not in {"SMC", "HID"} or row["average"] not in {"true", "false"}:
            raise ValueError(f"Invalid declaration: {row}")
        if row["backend"] == "SMC" and (len(row["key"]) != 4 or not row["key"].isascii()):
            raise ValueError(f"Invalid SMC key: {row['key']}")
        if not set(row["platforms"].split("|")) <= allowed:
            raise ValueError(f"Unknown platform: {row}")
        identity = (row["backend"], row["source_line"])
        if identity in identities or int(row["source_line"]) <= 0:
            raise ValueError(f"Duplicate/invalid source line: {row}")
        identities.add(identity)
    return metadata, rows


def verify_upstream(directory, metadata, rows):
    """Reject changed sources, then reconstruct all temperature declarations."""
    for name, expected in metadata["source_files"].items():
        digest = hashlib.sha256((directory / name).read_bytes()).hexdigest()
        if digest != expected:
            raise ValueError(f"Pinned source hash mismatch: {name}")
    system = (directory / "Kit/plugins/SystemKit.swift").read_text()
    platform_sets = {}
    for match in re.finditer(
        r"public static var (apple|m\dGen): \[Platform\] \{\s*return \[(.*?)\]", system, re.S
    ):
        platform_sets[match[1]] = re.findall(r"\.(\w+)", match[2])
    platform_sets["all"] = platform_sets["apple"] + ["intel"]
    if platform_sets != metadata["platform_sets"]:
        raise ValueError("Platform declarations differ from snapshot")
    reconstructed = []
    backend = None
    source = (directory / "Modules/Sensors/values.swift").read_text()
    for number, line in enumerate(source.splitlines(), 1):
        if "internal let SensorsList:" in line:
            backend = "SMC"
        if "internal let HIDSensorsList:" in line:
            backend = "HID"
        if "Sensor(key:" not in line or "type: .temperature" not in line:
            continue
        match = re.fullmatch(
            r'\s*Sensor\(key: "([^"]+)", name: "([^"]+)", group: \.(\w+), '
            r'type: \.temperature, platforms: (.*)\),?\s*', line
        )
        if not match:
            raise ValueError(f"Unparsed temperature declaration at {number}")
        key, name, group, tail = match.groups()
        selector = tail.removesuffix(", average: true")
        if selector.startswith("Platform.") and "[" not in selector:
            targets = platform_sets[selector.split(".")[1]]
        else:
            targets = re.findall(r"(?:Platform\.|\.)(\w+)", selector)
        reconstructed.append(dict(zip(HEADER, [
            backend, key, name, group, "|".join(targets),
            "true" if tail.endswith(", average: true") else "false", str(number)
        ])))
    if reconstructed != rows:
        raise ValueError("Extracted declarations differ from snapshot")


def compare(metadata, rows):
    path = ROOT / "Sources/MacFanControl/SensorCatalog.swift"
    source = path.read_text()
    start = source.index("static let appleSiliconTemperatureSensors:")
    end = source.index("static let appleSiliconTemperatureSensorsByKey:", start)
    block = source[start:end]
    pairs = re.findall(r'TemperatureSensorDefinition\(key: "([^"]+)", name: "([^"]+)"\)', block)
    if not pairs or len(pairs) != block.count("TemperatureSensorDefinition(key:"):
        raise ValueError("Catalog format changed; update the audit parser before use")
    counts = Counter(key for key, _ in pairs)
    duplicates = sorted(key for key, count in counts.items() if count > 1)
    # Match the current Swift lookup's first-definition-wins behavior.
    local = {}
    for key, name in pairs:
        local.setdefault(key, name)
    smc = [row for row in rows if row["backend"] == "SMC"]
    apple_platforms = set(metadata["platform_sets"]["apple"])
    variants = {}
    for platform in metadata["platform_sets"]["apple"]:
        eligible = [row for row in smc if platform in row["platforms"].split("|")]
        # Restrict coverage to platform-specific declarations. Common and wildcard
        # templates are reported separately, not counted as missing core sensors.
        specific = [row for row in eligible if not apple_platforms <= set(row["platforms"].split("|"))]
        names = []
        for row in specific:
            if row["key"] in local and local[row["key"]].casefold() != row["name"].casefold():
                names.append({"key": row["key"], "local": local[row["key"]], "upstream": row["name"],
                              "source_line": int(row["source_line"])})
        variants[platform] = {
            "specific_declaration_count": len(specific),
            "missing_specific_keys": sorted({row["key"] for row in specific} - local.keys()),
            "different_names": names,
        }
    shared = [row for row in smc if apple_platforms <= set(row["platforms"].split("|"))
              and "%" not in row["key"] and row["key"] not in local]
    collisions = []
    for key in sorted({row["key"] for row in smc}):
        definitions = [row for row in smc if row["key"] == key]
        if len({(row["name"].casefold(), row["group"], row["average"]) for row in definitions}) > 1:
            collisions.append({"key": key, "definitions": definitions})
    return {
        "evidence": "source declaration comparison only; no runtime/device test",
        "upstream_commit": metadata["commit"],
        "local_catalog_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "local_definition_count": len(pairs), "local_unique_key_count": len(local),
        "duplicate_local_keys": duplicates,
        "snapshot_counts": dict(Counter(row["backend"] for row in rows)),
        "platforms": variants,
        "missing_common_exact_templates": shared,
        "platform_dependent_keys": collisions,
        "tf_gpu_keys": [row["key"] for row in smc if row["group"] == "GPU" and row["key"].startswith("Tf")],
        "hid_templates": [row for row in rows if row["backend"] == "HID"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-upstream", type=Path, help="Verify an already downloaded pinned source tree")
    parser.add_argument("--output", type=Path, help="Write full comparison JSON to this path")
    args = parser.parse_args()
    metadata, rows = load_catalog()
    if args.verify_upstream:
        verify_upstream(args.verify_upstream, metadata, rows)
    result = compare(metadata, rows)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Pinned Stats {metadata['commit']}; {result['snapshot_counts']}; local keys={result['local_unique_key_count']}")
    for platform, value in result["platforms"].items():
        print(f"{platform}: specific={value['specific_declaration_count']}, missing={len(value['missing_specific_keys'])}, name differences={len(value['different_names'])}")
    print(f"Platform-dependent keys={len(result['platform_dependent_keys'])}; Tf GPU keys={len(result['tf_gpu_keys'])}")
    print("Audit completed. This does not verify Swift execution, fan control or real devices.")


if __name__ == "__main__":
    main()
