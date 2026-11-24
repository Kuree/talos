#!/usr/bin/env python3
"""Build a separate native eval inventory/replay driver from an existing Ninja build.

The generated driver uses TALOS_EVAL_CONTRACT to export the physical graph.
With TALOS_EVAL_ORDER it also installs a solver order bound to that graph's
SHA-256. Use --mlir-timing for the emitted ownership and dataflow inventory.
The ordinary Talos driver and its build objects are left intact.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shlex
import subprocess


def insert_once(source, marker, inserted):
    if source.count(marker) != 1:
        raise ValueError(
            f"could not locate unique compiler integration point: {marker}"
        )
    return source.replace(marker, inserted + marker)


def instrument(path):
    source = path.read_text()
    if path.name == "NativeEvalPlanning.cpp":
        header = '#include <fstream>\n#include "llvm/Support/SHA256.h"\n#include "llvm/ADT/StringExtras.h"\n'
        hook = Path(__file__).with_name("native_eval_order.inc").read_text()
        return header + insert_once(
            source, "  // Events from executors outside the pure graph", hook + "\n"
        )
    return insert_once(
        source,
        "        if (after) {\n          cf::BranchOp::create(builder, loc, after);",
        """
        if (std::getenv("TALOS_EVAL_CONTRACT") && part.size() > 1 &&
            llvm::any_of(part, [&](const auto *member) {
              return llvm::is_contained(unconditional, static_cast<int32_t>(member->owner));
            })) {
          llvm::errs() << "RF eval chain";
          for (const auto *member : part)
            llvm::errs() << " " << plan.fourStateExecutors[member->owner] << "="
                         << llvm::is_contained(unconditional, static_cast<int32_t>(member->owner));
          llvm::errs() << "\\n";
        }
""",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    args = parser.parse_args()
    build = args.build.resolve()
    work = build / "tools/talos-rank/eval-probe"
    work.mkdir(exist_ok=True, parents=True)
    entries = json.loads((build / "compile_commands.json").read_text())
    names = {"NativeEvalPlanning.cpp", "SimulationRankedGroupMaterialization.cpp"}
    units = [entry for entry in entries if Path(entry["file"]).name in names]
    if len(units) != len(names):
        raise ValueError("native compile commands are missing or ambiguous")

    def compile_unit(entry):
        src = Path(entry["file"])
        copy = work / src.name
        obj = copy.with_suffix(".o")
        copy.write_text(instrument(src))
        cmd = shlex.split(entry["command"])
        cmd[cmd.index("-c") + 1] = str(copy)
        cmd[cmd.index("-o") + 1] = str(obj)
        subprocess.run(
            [*cmd, "-iquote", str(src.parent)], cwd=entry["directory"], check=True
        )
        return str(obj)

    with ThreadPoolExecutor(max_workers=2) as pool:
        objects = list(pool.map(compile_unit, units))
    command = subprocess.check_output(
        ["ninja", "-t", "commands", "tools/driver/talos"], cwd=build, text=True
    ).splitlines()[-1]
    cmd = shlex.split(command)
    if cmd[:2] != [":", "&&"] or cmd[-2:] != ["&&", ":"]:
        raise ValueError("unexpected Ninja linker command")
    cmd = cmd[2:-2]
    index = cmd.index("-o")
    output = build / "tools/driver/talos-eval-rank-probe"
    cmd[index + 1] = str(output)
    cmd[index:index] = objects
    subprocess.run(cmd, cwd=build, check=True)
    print(output)


if __name__ == "__main__":
    main()
