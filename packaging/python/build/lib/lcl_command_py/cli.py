from __future__ import annotations

import os
import shutil
import subprocess
import sys
from importlib.resources import as_file, files

from . import __version__


def _resolve_node() -> str:
    node = os.environ.get("LCL_COMMAND_NODE") or shutil.which("node")
    if not node:
        raise SystemExit(
            "Error: Node.js is required to run lcl-command. "
            "Install Node 18+ or set LCL_COMMAND_NODE to the node binary."
        )
    return node


def main() -> None:
    node = _resolve_node()
    script_resource = files("lcl_command_py").joinpath("vendor", "bin", "lcl-command.js")
    env = os.environ.copy()
    env.setdefault("LCL_COMMAND_VERSION", __version__)
    with as_file(script_resource) as script_path:
        result = subprocess.run([node, str(script_path), *sys.argv[1:]], check=False, env=env)
    raise SystemExit(result.returncode)
