"""Validate wheel versions, tags, contents, and native CPU architectures."""

import argparse
from email.parser import BytesParser
from pathlib import Path
import struct
from zipfile import ZipFile

from packaging.tags import parse_tag

from utils.packaging.check_install import check_windows_binary, check_windows_dlls
from utils.packaging.publish_dev import validate_wheels


def check_binary(stream, platform):
    if platform.startswith("win_"):
        expected = 0xAA64 if platform == "win_arm64" else 0x8664
        check_windows_binary(stream, expected)
        return
    header = stream.read(64)
    if platform.startswith("manylinux_"):
        expected = 183 if platform.endswith("aarch64") else 62
        if header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != expected:
            raise ValueError("Linux executable architecture disagrees with wheel tag")
    elif platform.startswith("macosx_"):
        expected = 0x0100000C if platform.endswith("arm64") else 0x01000007
        if header[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", header, 4)[0] != expected:
            raise ValueError("macOS executable architecture disagrees with wheel tag")


def check_contents(wheel, expected_version):
    from packaging.utils import parse_wheel_filename

    _, _, _, tags = parse_wheel_filename(wheel.name)
    platforms = {tag.platform for tag in tags}
    if len(platforms) != 1:
        raise ValueError("Expected one platform per wheel")
    platform = platforms.pop()
    with ZipFile(wheel) as zipped:
        if platform.startswith("win_"):
            check_windows_dlls(zipped.namelist())
        metadata_path = next(name for name in zipped.namelist() if name.endswith(".dist-info/METADATA"))
        metadata = BytesParser().parsebytes(zipped.read(metadata_path))
        if metadata["Name"] != "talos-sv" or metadata["Version"] != expected_version:
            raise ValueError("Wheel metadata disagrees with VERSION")
        wheel_metadata_path = metadata_path.rsplit("/", 1)[0] + "/WHEEL"
        wheel_metadata = BytesParser().parsebytes(zipped.read(wheel_metadata_path))
        recorded_tags = set().union(*(parse_tag(tag) for tag in wheel_metadata.get_all("Tag", [])))
        if tags != recorded_tags:
            raise ValueError("Wheel filename disagrees with its recorded tags")
        suffix = ".exe" if platform.startswith("win_") else ""
        for tool in ("talos", "talos-cov"):
            with zipped.open("talos_sv/bin/" + tool + suffix) as stream:
                check_binary(stream, platform)
        if platform.startswith("win_"):
            for name in zipped.namelist():
                if name.startswith("talos_sv/bin/") and name.lower().endswith(".dll"):
                    with zipped.open(name) as stream:
                        check_windows_binary(stream)
        for tool in ("talos-opt", "talos-translate"):
            if "talos_sv/bin/" + tool + suffix in zipped.namelist():
                raise ValueError("Development tools must stay out of the wheel")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel-dir", type=Path, required=True)
    parser.add_argument("--version-file", type=Path, default=Path("VERSION"))
    parser.add_argument("--require-platform", action="append", default=[])
    parser.add_argument("--max-size-mib", type=float, default=100)
    args = parser.parse_args()
    wheels = sorted(args.wheel_dir.glob("*.whl"))
    version = validate_wheels(wheels, args.require_platform, development=False)
    if version != args.version_file.read_text().strip():
        raise ValueError("Wheel filenames disagree with VERSION")
    for wheel in wheels:
        check_contents(wheel, version)
        if wheel.stat().st_size > args.max_size_mib * 1024**2:
            raise ValueError("Wheel exceeds configured upload size limit: " + wheel.name)
        print("Verified " + wheel.name)


if __name__ == "__main__":
    main()
