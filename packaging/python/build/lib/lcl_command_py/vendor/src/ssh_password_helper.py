#!/usr/bin/env python3
from __future__ import annotations

import os
import pty
import select
import signal
import sys
import termios
import tty


PASSWORD_PROMPT = "password:"
HOSTKEY_PROMPT = "are you sure you want to continue connecting"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: ssh_password_helper.py <user@host>", file=sys.stderr)
        return 2

    password = os.environ.get("LCL_COMMAND_SSH_PASSWORD", "")
    if not password:
        print("Error: missing LCL_COMMAND_SSH_PASSWORD for SSH helper.", file=sys.stderr)
        return 1

    target = sys.argv[1]
    old_tty = None
    if sys.stdin.isatty():
        old_tty = termios.tcgetattr(sys.stdin.fileno())
        tty.setraw(sys.stdin.fileno())

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(
            "ssh",
            [
                "ssh",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "NumberOfPasswordPrompts=1",
                "--",
                target,
            ],
        )

    password_sent = False
    recent_output = ""
    exit_code = 0

    def restore_tty() -> None:
        if old_tty is not None:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_tty)

    def handle_signal(signum: int, _frame) -> None:
        try:
            os.kill(pid, signum)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    try:
        while True:
            readers = [fd]
            if sys.stdin.isatty():
                readers.append(sys.stdin.fileno())
            ready, _, _ = select.select(readers, [], [])

            if fd in ready:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                os.write(sys.stdout.fileno(), data)
                recent_output = (recent_output + data.decode("utf-8", errors="ignore"))[-4096:].lower()

                if HOSTKEY_PROMPT in recent_output:
                    os.write(fd, b"yes\n")
                    recent_output = ""
                elif not password_sent and PASSWORD_PROMPT in recent_output:
                    os.write(fd, password.encode("utf-8") + b"\n")
                    password_sent = True
                    recent_output = ""

            if sys.stdin.isatty() and sys.stdin.fileno() in ready:
                chunk = os.read(sys.stdin.fileno(), 1024)
                if not chunk:
                    break
                os.write(fd, chunk)

        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            exit_code = os.WEXITSTATUS(status)
        elif os.WIFSIGNALED(status):
            exit_code = 128 + os.WTERMSIG(status)
    finally:
        restore_tty()

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
