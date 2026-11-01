"""Fingerprint the active files in a compiler resource directory."""

import hashlib
import os
from pathlib import Path


def fingerprint_resources(directory):
    root = Path(directory).absolute()
    if not root.is_dir():
        raise ValueError(f"Compiler resource directory is missing: {root}")
    result = hashlib.sha256()
    for current, directories, files in os.walk(root, followlinks=True):
        if Path(current) == root / "targets":
            # Inactive installations live here; the active target is a symlink.
            directories[:] = [name for name in directories if not name.endswith(".versions")]
        directories.sort()
        for name in sorted(files):
            path = Path(current) / name
            result.update(path.relative_to(root).as_posix().encode() + b"\0")
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            result.update(digest.digest())
    return result.hexdigest()
