#!/usr/bin/env python3
"""Verify that Nunchuk-owned Release sources use the requested O2 level."""

import argparse
import json
import pathlib
import re
import sys


UNIX_OPTIMIZATION = re.compile(r"(?<!\S)-O(?:0|1|2|3|g|s|fast)(?=\s|$)")
MSVC_OPTIMIZATION = re.compile(
    r"(?<!\S)[/-]O(?:d|1|2|x)(?=\s|$)", re.IGNORECASE
)


def source_group(source: pathlib.Path, project_root: pathlib.Path) -> str | None:
    try:
        relative = source.resolve().relative_to(project_root.resolve())
    except ValueError:
        return None

    parts = relative.parts
    if not parts:
        return None
    if parts[0] == "contrib":
        if len(parts) >= 3 and parts[:3] in (
            ("contrib", "libnunchuk", "src"),
            ("contrib", "libnunchuk", "embedded"),
        ):
            return "libnunchuk"
        return None
    if parts[0] == "reproducible-builds" or parts[0].startswith("build"):
        return None
    return "desktop"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile-database", required=True, type=pathlib.Path)
    parser.add_argument("--project-root", required=True, type=pathlib.Path)
    parser.add_argument("--family", choices=("unix", "msvc"), required=True)
    args = parser.parse_args()

    with args.compile_database.open(encoding="utf-8-sig") as stream:
        entries = json.load(stream)

    pattern = UNIX_OPTIMIZATION if args.family == "unix" else MSVC_OPTIMIZATION
    expected = "-O2" if args.family == "unix" else "/O2"
    checked = {"desktop": 0, "libnunchuk": 0}
    failures: list[str] = []

    for entry in entries:
        source = pathlib.Path(entry["file"])
        group = source_group(source, args.project_root)
        if group is None:
            continue
        checked[group] += 1
        command = entry.get("command")
        if command is None:
            command = " ".join(entry.get("arguments", []))
        flags = pattern.findall(command)
        effective = flags[-1] if flags else "missing"
        matches = (
            effective == expected
            if args.family == "unix"
            else effective.lower() == expected.lower()
        )
        if not matches:
            failures.append(f"{source}: effective optimization is {effective}")

    for group, count in checked.items():
        if count == 0:
            failures.append(f"compile database has no {group} source entries")

    if failures:
        for failure in failures[:50]:
            print(f"optimization verification failed: {failure}", file=sys.stderr)
        if len(failures) > 50:
            print(f"... and {len(failures) - 50} more failures", file=sys.stderr)
        return 1

    print(
        f"Release optimization {expected}: PASS "
        f"({checked['desktop']} desktop, {checked['libnunchuk']} libnunchuk sources)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
