#!/usr/bin/env python3
"""Build and check a complete native archive, using zip on Windows."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


def cache_value(build, name):
    for line in (build / "CMakeCache.txt").read_text().splitlines():
        if line.startswith(name + ":"):
            return line.split("=", 1)[1]
    raise ValueError("Missing CMake cache entry " + name)


def bundle_dependencies(build, root):
    licenses = root / "share/talos/licenses"
    if sys.platform == "win32":
        # micromamba records the extracted package cache for each SDK package.
        # Carry its original notices along with the bundled dependent DLLs.
        sdk = Path(cache_value(build, "TALOS_LLVM_TOOLS_DIR")).parent.parent
        for metadata in (sdk / "conda-meta").glob("*.json"):
            data = json.loads(metadata.read_text())
            source = Path(data["link"]["source"]) / "info/licenses"
            if source.is_dir():
                shutil.copytree(source, licenses / "windows-sdk" / metadata.stem,
                                dirs_exist_ok=True)
    elif sys.platform == "darwin":
        from delocate.delocating import delocate_path

        copied = delocate_path(str(root), str(root / "lib"),
                               lib_filt_func=lambda p: Path(p).suffix == ".dylib"
                               or Path(p).parent == root / "bin",
                               sanitize_rpaths=True)
        # Homebrew dependencies carry their license files at the keg root.
        for dependency in copied:
            keg = Path(dependency).resolve().parent.parent
            destination = licenses / "macos-libraries" / Path(dependency).name
            for pattern in ("LICENSE*", "COPYING*", "COPYRIGHT*"):
                for notice in keg.glob(pattern):
                    if notice.is_file():
                        destination.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(notice, destination / notice.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--bundle-only", type=Path)
    args = parser.parse_args()
    build = args.build.resolve()
    if args.bundle_only:
        bundle_dependencies(build, args.bundle_only.resolve())
        return
    if args.output_dir is None:
        parser.error("--output-dir is required when creating an archive")
    source = Path(__file__).resolve().parents[2]
    version = (source / "VERSION").read_text().strip()
    target = cache_value(build, "TALOS_TARGET_TRIPLE")
    if not re.fullmatch(r"[\w.]+(?:-[\w.]+)+", target):
        raise ValueError("Unexpected target triple: " + target)
    name = "talos-sv-{}-{}".format(version, target)
    archive_format = "zip" if sys.platform == "win32" else "gztar"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output = args.output_dir.resolve() / name
    with tempfile.TemporaryDirectory(prefix="talos-package-") as temporary:
        root = Path(temporary) / name
        for component in ("talos", "talos-dev"):
            command = ["cmake", "--install", str(build), "--prefix", str(root),
                       "--config", "Release", "--component", component]
            if sys.platform != "win32":
                command.append("--strip")
            subprocess.run(command, check=True)
        bundle_dependencies(build, root)
        archive = Path(shutil.make_archive(str(output), archive_format, temporary, name))
    # Check the extracted archive, after its original staging tree is gone.
    with tempfile.TemporaryDirectory(prefix="talos-extracted-") as extracted:
        shutil.unpack_archive(str(archive), extracted)
        if archive_format == "zip":
            with zipfile.ZipFile(archive) as zipped:
                if zipped.testzip() is not None:
                    raise ValueError("Corrupt zip archive")
        subprocess.run([sys.executable, str(source / "utils/packaging/check_install.py"),
                        "--prefix", str(Path(extracted) / name)], check=True)
    print("{} ({:.1f} MiB)".format(archive, archive.stat().st_size / 2**20))


if __name__ == "__main__":
    main()
