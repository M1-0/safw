#!/usr/bin/env python3
"""Reject known private-data files and common credential formats from tracked public source.

This is a narrow publication guard, not a substitute for reviewing source and Git history.
Only tracked files are inspected; never print matched credential or health payload contents.
"""
import re
import subprocess
import sys
from pathlib import Path

PATTERNS = (
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    re.compile(rb"\bsk-proj-[A-Za-z0-9_-]{30,}\b"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
)


def violations(path, data):
    parts = Path(path).parts
    forbidden = any(part in {"PersonalWHOOP", "state", ".venv", "__pycache__"} for part in parts)
    forbidden |= any(part == ".env" or part.startswith(".env.") for part in parts)
    forbidden |= bool(re.search(r"\.(?:sqlite(?:-\w+)?|db|noopbak|ipa|p12|mobileprovision|csv)$", path, re.I))
    # The reviewed TSV files are localization maps; raw CSV exports have no place in this overlay.
    if forbidden:
        return ["private-data or generated-file path"]
    return ["credential-like content"] if any(pattern.search(data) for pattern in PATTERNS) else []


def main(root):
    paths = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"]).decode().split("\0")
    failures = []
    for name in filter(None, paths):
        target = root / name
        if target.is_symlink():
            failures.append((name, "unreviewed symbolic link"))
            continue
        for reason in violations(name, target.read_bytes()):
            failures.append((name, reason))
    for name, reason in failures:
        print(f"{name}: {reason}", file=sys.stderr)
    if failures:
        return 1
    print(f"Public-source boundary checked: {len(list(filter(None, paths)))} tracked files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
