"""Launch the bundled Talos tools without depending on a Python ABI."""

import os
import subprocess
import sys


def _run(tool):
    if os.name == "nt":
        tool += ".exe"
    executable = os.path.join(os.path.dirname(__file__), "bin", tool)
    arguments = [executable] + sys.argv[1:]
    if os.name == "nt":
        return subprocess.call(arguments)
    os.execv(executable, arguments)


def main():
    return _run("talos")


def coverage():
    return _run("talos-cov")
