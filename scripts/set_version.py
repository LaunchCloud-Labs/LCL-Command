#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_JSON = ROOT / "package.json"
PYPROJECT = ROOT / "packaging" / "python" / "pyproject.toml"
PY_INIT = ROOT / "packaging" / "python" / "src" / "lcl_command_py" / "__init__.py"
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


def replace_once(path: Path, pattern: str, replacement: str) -> None:
    content = path.read_text()
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Could not update version in {path}")
    path.write_text(updated)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 scripts/set_version.py <x.y.z>")

    version = sys.argv[1].strip()
    if not SEMVER_RE.match(version):
        raise SystemExit("version must match x.y.z")

    package = json.loads(PACKAGE_JSON.read_text())
    package["version"] = version
    PACKAGE_JSON.write_text(json.dumps(package, indent=2) + "\n")

    replace_once(PYPROJECT, r'^version = "[^"]+"$', f'version = "{version}"')
    replace_once(PY_INIT, r'^__version__ = "[^"]+"$', f'__version__ = "{version}"')

    print(version)


if __name__ == "__main__":
    main()
