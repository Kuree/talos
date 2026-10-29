#!/usr/bin/env python3
"""Set VERSION using the original CI run's Unix timestamp."""

import argparse
from pathlib import Path
import re


def development_version(version, number):
    match = re.fullmatch(r"(\d+\.\d+\.\d+)(?:\.dev\d+)?", version.strip())
    if not match or number < 1:
        raise ValueError("Expected X.Y.Z[.devN] and a positive Unix timestamp")
    return "{}.dev{}".format(match[1], number)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("number", type=int, help="Unix timestamp of the original CI run")
    parser.add_argument("--file", type=Path, default=Path("VERSION"))
    args = parser.parse_args()
    version = development_version(args.file.read_text(), args.number)
    args.file.write_text(version + "\n")
    print(version)


if __name__ == "__main__":
    main()
