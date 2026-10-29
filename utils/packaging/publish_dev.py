#!/usr/bin/env python3
"""Publish development wheels and native archives to one rolling GitHub release."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from packaging.utils import parse_wheel_filename
from packaging.version import Version


def gh(*args):
    return subprocess.check_output(["gh", *map(str, args)], text=True)


def validate_wheels(wheels, required_platforms, development=True):
    versions, platforms = set(), set()
    for wheel in wheels:
        name, version, _, tags = parse_wheel_filename(wheel.name)
        if name != "talos-sv" or (development and not version.is_devrelease):
            raise ValueError("Unexpected Talos wheel name/version: " + wheel.name)
        if {tag.interpreter for tag in tags} != {"py2", "py3"}:
            raise ValueError("Expected py2.py3 wheel: " + wheel.name)
        if {tag.abi for tag in tags} != {"none"}:
            raise ValueError("Expected a Python-independent ABI: " + wheel.name)
        wheel_platforms = {tag.platform for tag in tags}
        if any(not platform.startswith(("manylinux_", "macosx_", "win_"))
               for platform in wheel_platforms):
            raise ValueError("Expected a supported platform wheel: " + wheel.name)
        if platforms & wheel_platforms:
            raise ValueError("More than one wheel for the same platform")
        platforms.update(wheel_platforms)
        versions.add(str(version))
    if len(versions) != 1 or not set(required_platforms) <= platforms:
        raise ValueError("Provide one version and every required platform")
    return versions.pop()


def validate_archives(archives, version, required_targets):
    targets = set()
    for archive in archives:
        match = re.fullmatch(r"talos-sv-" + re.escape(version)
                             + r"-([\w.]+(?:-[\w.]+)+)(\.tar\.gz|\.zip)", archive.name)
        if not match:
            raise ValueError("Archive must match the wheel version: " + archive.name)
        target, extension = match.groups()
        if ("-windows-" in target) != (extension == ".zip"):
            raise ValueError("Windows archives use zip; other hosts use tar.gz")
        if target in targets:
            raise ValueError("More than one archive for the same target")
        targets.add(target)
    if not set(required_targets) <= targets:
        raise ValueError("Missing required native archives")


def publish(repo, commit, wheels, required_platforms=(), archives=(), required_targets=()):
    # Validate every input before changing the release or deleting any asset.
    version = validate_wheels(wheels, required_platforms)
    validate_archives(archives, version, required_targets)
    assets = [*wheels, *archives]
    releases = json.loads(gh("api", "--paginate", "--slurp", "repos/{}/releases".format(repo)))
    release = next((release for page in releases for release in page
                    if release["tag_name"] == "dev"), None)
    if release and (release.get("immutable") or not release["prerelease"]):
        raise ValueError("The dev release must be a mutable prerelease")
    if release:
        for asset in release.get("assets", []):
            name = asset["name"]
            if name.startswith("talos_sv-") and name.endswith(".whl"):
                _, current_version, _, _ = parse_wheel_filename(name)
                if current_version > Version(version):
                    raise ValueError("Refusing to replace a newer development release")

    install = ("python -m pip install --upgrade --pre --no-index --find-links "
               "https://github.com/{}/releases/expanded_assets/dev talos-sv".format(repo))
    notes = ("Development binaries for `{}` from commit `{}`.\n\n"
             "```sh\n{}\n```\n\n"
             "Wheels contain `talos` and `talos-cov`. Native `.tar.gz` "
             "and Windows `.zip` archives contain all four tools, headers, runtime "
             "archives, and license notices. Extract an archive and add its `bin` "
             "directory to PATH.\n\n"
             "Linux requires glibc 2.39+ and libc development files "
             "(`libc6-dev` or `glibc-devel`). macOS requires macOS 15+ on ARM64. "
             "Windows simulation links require Visual C++ Build Tools and a Windows SDK.\n\n"
             "This rolling prerelease retains only the current assets for each platform.\n").format(
                 version, commit, install)
    with tempfile.TemporaryDirectory(prefix="talos-release-") as temporary:
        notes_path = Path(temporary) / "notes.md"
        notes_path.write_text(notes)
        if release is None:
            # Drafts allow all assets to be uploaded before initial publication.
            gh("release", "create", "dev", "--repo", repo, "--target", commit,
               "--draft", "--prerelease", "--latest=false", "--title", "Development binaries",
               "--notes-file", notes_path)
        gh("release", "upload", "dev", *assets, "--repo", repo, "--clobber")

        # Upload new filenames before pruning the previous version. --clobber
        # replaces identical names on reruns; explicit pruning handles the
        # .devN filenames that changed between runs.
        current = json.loads(gh("release", "view", "dev", "--repo", repo,
                                "--json", "assets"))
        keep = {asset.name for asset in assets}
        for asset in current["assets"]:
            name = asset["name"]
            managed = (name.startswith("talos_sv-") and name.endswith(".whl")) or (
                name.startswith("talos-sv-") and name.endswith((".tar.gz", ".zip")))
            if managed and name not in keep:
                gh("release", "delete-asset", "dev", name, "--repo", repo, "--yes")

        # Publishing a new draft creates its tag. For an existing release move
        # the rolling tag as well as target_commitish so source archives agree.
        if release is not None and not release.get("draft"):
            gh("api", "--method", "PATCH", "repos/{}/git/refs/tags/dev".format(repo),
               "-f", "sha=" + commit, "-F", "force=true")
        gh("release", "edit", "dev", "--repo", repo, "--target", commit,
           "--draft=false", "--prerelease", "--latest=false",
           "--title", "Development binaries", "--notes-file", notes_path)
    print(install)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--wheel-dir", type=Path, required=True)
    parser.add_argument("--archive-dir", type=Path)
    parser.add_argument("--require-platform", action="append", default=[])
    parser.add_argument("--require-target", action="append", default=[])
    args = parser.parse_args()
    archives = [] if args.archive_dir is None else sorted(
        [*args.archive_dir.glob("*.tar.gz"), *args.archive_dir.glob("*.zip")])
    publish(args.repo, args.commit, sorted(args.wheel_dir.glob("*.whl")), args.require_platform,
            archives, args.require_target)


if __name__ == "__main__":
    main()
