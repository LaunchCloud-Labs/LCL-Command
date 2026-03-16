#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIST_DIR = ROOT / "dist"
NPM_DIST_DIR = DIST_DIR / "npm"
PYTHON_DIST_DIR = DIST_DIR / "python"
FORMULA_PATH = ROOT / "packaging" / "homebrew" / "lcl-command.rb"
PYTHON_PACKAGE_DIR = ROOT / "packaging" / "python"


def run(cmd: list[str], cwd: Path | None = None, capture_output: bool = False) -> str:
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=True,
        text=True,
        capture_output=capture_output,
    )
    return result.stdout if capture_output else ""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_version() -> str:
    package_json = json.loads((ROOT / "package.json").read_text())
    return str(package_json["version"])


def clean_python_cache(root: Path) -> None:
    for cache_dir in root.rglob("__pycache__"):
        shutil.rmtree(cache_dir, ignore_errors=True)
    for pyc_file in root.rglob("*.pyc"):
        pyc_file.unlink(missing_ok=True)


def clean_python_packaging_artifacts() -> None:
    shutil.rmtree(PYTHON_PACKAGE_DIR / "build", ignore_errors=True)
    for egg_info in (PYTHON_PACKAGE_DIR / "src").glob("*.egg-info"):
        shutil.rmtree(egg_info, ignore_errors=True)


def update_formula(version: str, sha256: str) -> None:
    formula = FORMULA_PATH.read_text()
    formula = re.sub(
        r'url "https://registry\.npmjs\.org/lcl-command/-/lcl-command-[^"]+\.tgz"',
        f'url "https://registry.npmjs.org/lcl-command/-/lcl-command-{version}.tgz"',
        formula,
    )
    formula = re.sub(r'sha256 "[^"]+"', f'sha256 "{sha256}"', formula)
    FORMULA_PATH.write_text(formula)


def main() -> None:
    DIST_DIR.mkdir(exist_ok=True)
    NPM_DIST_DIR.mkdir(exist_ok=True)
    PYTHON_DIST_DIR.mkdir(exist_ok=True)

    clean_python_cache(ROOT / "src")
    clean_python_cache(PYTHON_PACKAGE_DIR / "src")
    clean_python_packaging_artifacts()
    run([sys.executable, "scripts/sync_python_vendor.py"], cwd=ROOT)
    run(["npm", "run", "check"], cwd=ROOT)

    version = package_version()

    npm_output = run(["npm", "pack"], cwd=ROOT, capture_output=True)
    tarball_name = npm_output.strip().splitlines()[-1].strip()
    tarball_path = ROOT / tarball_name
    npm_target = NPM_DIST_DIR / tarball_name
    if npm_target.exists():
        npm_target.unlink()
    shutil.move(str(tarball_path), npm_target)
    npm_sha256 = sha256_file(npm_target)

    for artifact in PYTHON_DIST_DIR.glob("*"):
        if artifact.is_file():
            artifact.unlink()
    run(
        [
            sys.executable,
            "-m",
            "pip",
            "wheel",
            ".",
            "--no-deps",
            "--wheel-dir",
            str(PYTHON_DIST_DIR),
        ],
        cwd=PYTHON_PACKAGE_DIR,
    )

    update_formula(version, npm_sha256)

    manifest = {
        "version": version,
        "npm_tarball": str(npm_target.relative_to(ROOT)),
        "npm_sha256": npm_sha256,
        "python_wheels": sorted(str(path.relative_to(ROOT)) for path in PYTHON_DIST_DIR.glob("*.whl")),
        "homebrew_formula": str(FORMULA_PATH.relative_to(ROOT)),
    }
    (DIST_DIR / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
