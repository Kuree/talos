#!/usr/bin/env python3
r"""Count retired host instructions between post-reset cycle limits in RSD TestMain.

Example (all executables must use the same RTL configuration):
  python3 benchmark/scheduler/rsd_postreset.py --source-root /path/to/Processor/Src \
    --llvm-bin /path/to/llvm/bin --cpu 7 --event armv8_pmuv3_1/inst_retired/u \
    --sim before=/path/to/before --sim after=/path/to/after --sim verilator=/path/to/sim

The built-in RV32IM image includes a checksum and terminates at RSD's PC goal.
Use --image and --caps for other programs; each cap used in the slope must
precede the goal, and the core must commit instructions in every interval.
Counters cover user space and must run for the full interval.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile


def build_image(work, llvm):
    source = Path(__file__).with_name("rsd-mix.S")
    subprocess.run([llvm / "clang", "--target=riscv32", "-march=rv32im", "-mabi=ilp32",
                    "-nostdlib", "-Wl,--image-base=0,-Ttext=0x1000", "-fuse-ld=lld",
                    source, "-o", work / "mix.elf"], check=True)
    subprocess.run([llvm / "llvm-objcopy", "-O", "binary", "--only-section=.text",
                    work / "mix.elf", work / "mix.bin"], check=True)
    image = bytes(0x1000) + (work / "mix.bin").read_bytes()
    if len(image) > 65536:
        raise ValueError("program exceeds the RSD ROM")
    image = image.ljust(65536, b"\0")
    return "".join(image[i:i + 16][::-1].hex() + "\n"
                   for i in range(0, len(image), 16)).encode()


def measure(exe, work, dummy, cap, cpu, event):
    cmd = ["taskset", "-c", str(cpu), "perf", "stat", "--no-big-num", "-x", ",",
           "-e", event, "-o", "perf.csv", "--", exe, f"+TEST_CODE={work}",
           f"+DUMMY_DATA_FILE={dummy}", f"+MAX_TEST_CYCLES={cap}",
           "+SHOW_SERIAL_OUT=1", "+ENABLE_PC_GOAL=1"]
    # Some simulators leave an existing dump in place on a failed run.
    for name in ("reg.out.hex", "serial.out.txt"):
        (work / name).unlink(missing_ok=True)
    result = subprocess.run(cmd, cwd=work, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=dict(os.environ, LC_ALL="C"))
    log = result.stdout.decode(errors="replace")
    cycles = re.search(r"Elapsed cycles:\s*(\d+)", log)
    committed = re.search(r"Num of committed RISC-V-ops:\s*(\d+)", log)
    if result.returncode or not cycles or not committed:
        raise RuntimeError(f"{exe} at cap {cap}\n{log[-2000:]}")
    counters = [s.split(",") for s in (work / "perf.csv").read_text().splitlines()
                if s.strip() and not s.startswith("#")]
    if (len(counters) != 1 or len(counters[0]) < 5 or
            not counters[0][0].isdigit() or float(counters[0][4]) != 100):
        raise RuntimeError(f"expected one pinned, unmultiplexed PMU event: {counters}")
    regs = (work / "reg.out.hex").read_bytes()
    serial = (work / "serial.out.txt").read_bytes()
    return int(counters[0][0]), (int(cycles[1]), int(committed[1]), regs, serial,
                                 "PC reached PC_GOAL:" in log)


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source-root", required=True, type=Path)
    p.add_argument("--sim", action="append", required=True, metavar="NAME=PATH")
    p.add_argument("--image", type=Path)
    p.add_argument("--llvm-bin", type=Path, help="directory containing clang, ld.lld, llvm-objcopy")
    p.add_argument("--event", default="instructions:u",
                   help="user-space retired instructions, optionally on a named CPU PMU")
    p.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    p.add_argument("--caps", type=int, nargs="+", default=[1000, 2000, 4000, 10000, 40000, 180000])
    p.add_argument("--repeats", type=int, default=3)
    args = p.parse_args()
    if (args.repeats < 1 or len(args.caps) < 2 or args.caps[0] < 0 or
            args.caps != sorted(set(args.caps)) or args.cpu not in os.sched_getaffinity(0)):
        p.error("use increasing nonnegative caps, positive repeats and an available CPU")
    if not re.fullmatch(r"instructions:u|[\w.-]+/(?:inst_retired|instructions)/u", args.event):
        p.error("--event must count retired user-space instructions")
    if not args.image and not args.llvm_bin:
        p.error("--llvm-bin is required to assemble the built-in workload")
    sims = {}
    for entry in args.sim:
        label, sep, value = entry.partition("=")
        if not sep or not label or not value or label in sims:
            p.error("each --sim must specify a distinct NAME=PATH")
        sims[label] = Path(value).resolve()
    dummy = (args.source_root / "Verification/DummyData.hex").resolve()
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        image = args.image.read_bytes() if args.image else build_image(work, args.llvm_bin.resolve())
        (work / "code.hex").write_bytes(image)
        full_cap = 500000
        reference = {}
        guest_ops = {}
        samples = {label: [] for label in sims}
        for repeat in range(args.repeats):
            order = list(sims) if repeat % 2 == 0 else list(reversed(sims))
            for label in order:
                counts = []
                caps = args.caps + ([full_cap] if repeat == 0 and not args.image else [])
                for index, cap in enumerate(caps):
                    insns, state = measure(sims[label], work, dummy, cap, args.cpu, args.event)
                    cycles, committed, regs, _, goal = state
                    if index == len(args.caps):
                        # Independent RV32 reference result after all three passes.
                        if not goal or regs.splitlines()[10:12] != [b"0xe69b54c7", b"0xa4db685a"]:
                            raise RuntimeError(f"{label} failed the workload checksum or PC goal")
                    elif cycles != cap or goal:
                        raise RuntimeError(f"{label} did not stop at the requested cap {cap}")
                    elif index:
                        lo = args.caps[index - 1]
                        delta = committed - reference[lo][1]
                        if delta <= 0:
                            raise RuntimeError(f"no RISC-V retirement progress between cycles {lo} and {cap}")
                        guest_ops[f"{lo}-{cap}"] = delta
                    if reference.setdefault(cap, state) != state:
                        raise RuntimeError(f"architectural output differs for {label} at cap {cap}")
                    counts.append(insns)
                samples[label].append(counts[:len(args.caps)])
        slopes = {}
        for label, runs in samples.items():
            slopes[label] = {
                f"{lo}-{hi}": statistics.median((r[i + 1] - r[i]) / (hi - lo) for r in runs)
                for i, (lo, hi) in enumerate(zip(args.caps, args.caps[1:]))
            }
        executables = {
            label: {"path": str(exe), "sha256": hashlib.sha256(exe.read_bytes()).hexdigest()}
            for label, exe in sims.items()
        }
        results = {
            "executables": executables,
            "image_sha256": hashlib.sha256(image).hexdigest(),
            "cpu": args.cpu,
            "event": args.event,
            "caps": args.caps,
            "retired_instructions": samples,
            "insns_per_simulated_cycle": slopes,
            "committed_riscv_ops_per_window": guest_ops,
            "checkpoints": [
                {"cycles": cycles, "committed": committed, "goal": goal,
                 "register_sha256": hashlib.sha256(regs).hexdigest(),
                 "serial_sha256": hashlib.sha256(serial).hexdigest()}
                for cycles, committed, regs, serial, goal in reference.values()
            ],
        }
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
