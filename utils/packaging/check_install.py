#!/usr/bin/env python3
"""Check a wheel or native archive from outside the source and build trees."""

import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile


def check_windows_binary(stream, machine=None):
    header = stream.read(64)
    if header[:2] != b"MZ":
        raise ValueError("Expected a Windows executable")
    stream.seek(struct.unpack_from("<I", header, 0x3C)[0])
    pe = stream.read(24)
    if pe[:4] != b"PE\0\0" or (machine is not None and
                                struct.unpack_from("<H", pe, 4)[0] != machine):
        raise ValueError("Windows executable architecture disagrees with wheel tag")
    if struct.unpack_from("<II", pe, 12) != (0, 0):
        raise ValueError("Windows executable must be stripped before packaging")


def check_windows_dlls(paths):
    for path in paths:
        name = Path(path).name.lower()
        if name.startswith("icu") and name.endswith(".dll"):
            raise ValueError("Windows packages must use the libxml2 build without ICU")


def run(*command, cwd=None):
    result = subprocess.run(command, check=True, text=True, capture_output=True, cwd=cwd)
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", type=Path, help="Check an unpacked native archive")
    args = parser.parse_args()
    if args.prefix:
        package = args.prefix.resolve()
        expected = (package / "share/talos/VERSION").read_text().strip()
        suffix = ".exe" if os.name == "nt" else ""
        driver = str(package / "bin" / ("talos" + suffix))
        coverage = str(package / "bin" / ("talos-cov" + suffix))
        for tool in ("talos-opt", "talos-translate"):
            run(str(package / "bin" / (tool + suffix)), "--help")
    else:
        from importlib.metadata import version
        import talos_sv
        package = Path(talos_sv.__file__).resolve().parent
        expected = version("talos-sv")
        driver, coverage = "talos", "talos-cov"
    if os.name == "nt":
        check_windows_dlls((package / "bin").glob("*.dll"))
        binaries = [*(package / "bin").glob("talos*.exe"),
                    *(package / "bin").glob("*.dll")]
        for binary in binaries:
            with binary.open("rb") as stream:
                check_windows_binary(stream)
    # An installed compiler must find its own headers rather than succeeding
    # accidentally through the absolute resource path in the build tree.
    with tempfile.TemporaryDirectory(prefix="talos-wheel-check-") as temporary:
        workdir = Path(temporary)
        reported = run(driver, "--version", cwd=workdir)
        assert reported.splitlines()[0] == "talos version " + expected, reported
        rejected = subprocess.run([driver, "--talos-wheel-invalid-option"], cwd=workdir,
                                  capture_output=True, text=True)
        assert rejected.returncode != 0, "Launcher did not preserve a failing tool's exit code"
        resource = Path(run(driver, "--print-resource-dir", cwd=workdir)).resolve()
        assert resource == package / "lib/talos", resource
        for header in ("svdpi.h", "vpi_user.h", "sv_vpi_user.h"):
            assert (resource / "include" / header).is_file(), header
        for notice in ("slang-LICENSE", "z3-LICENSE.txt", "fmt-LICENSE",
                       "BS-thread-pool-LICENSE.txt", "llvm-LICENSE.TXT", "zstd-LICENSE"):
            assert (package / "share/talos/licenses" / notice).is_file(), notice
        run(coverage, "report", "--help", cwd=workdir)
        source = workdir / "smoke.sv"
        source.write_text('module top; initial begin '
                          '$display("wheel simulation passed"); $finish; end endmodule\n')
        # Both native-object and Full-LTO runtime archives must survive the
        # move from the build tree to site-packages.
        for flags in (("-O0",), ("-O3", "-flto")):
            output_name = "simulation.exe" if os.name == "nt" else "simulation"
            executable = workdir / output_name
            run(driver, *flags, "--compile-threads=2", str(source), "-o", str(executable),
                cwd=workdir)
            output = run(str(executable), cwd=workdir)
            assert "wheel simulation passed" in output, output
        print("Installed tools report {} and compile/run native and LTO simulations".format(expected))


if __name__ == "__main__":
    main()
