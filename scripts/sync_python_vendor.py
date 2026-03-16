#!/usr/bin/env python3
from __future__ import annotations

import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VENDOR_ROOT = ROOT / "packaging" / "python" / "src" / "lcl_command_py" / "vendor"


def sync_tree(source_dir: Path, target_dir: Path, patterns: tuple[str, ...]) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    for pattern in patterns:
        for source_file in source_dir.glob(pattern):
            shutil.copy2(source_file, target_dir / source_file.name)


def main() -> None:
    sync_tree(ROOT / "bin", VENDOR_ROOT / "bin", ("*.js",))
    sync_tree(ROOT / "src", VENDOR_ROOT / "src", ("*.js", "*.py"))
    print(f"Synced Python wrapper vendor files into {VENDOR_ROOT}")


if __name__ == "__main__":
    main()
