#!/usr/bin/env python3
"""Run the clause-named SystemVerilog conformance probes without extra indexes."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "utils"))
from compiler_resources import fingerprint_resources

DIRECTIVE = re.compile(r"^[ \t]*//[ \t]*(CLAUSE|RUN|XFAIL|REFERENCE|SKIP|REQUIRES|SINCE)[ \t]*:[ \t]*(.*?)[ \t]*$", re.M)
CHECK = re.compile(r"^[ \t]*//[ \t]*CHECK(?:-[A-Z0-9-]+)?[ \t]*:", re.M)
DIAGNOSTIC = re.compile(r"^[ \t]*//[ \t]*DIAG(?:-[A-Z0-9-]+)?[ \t]*:", re.M)
SIMULATION = re.compile(r"^\s*(?:%not\s+)?%t[^\s]*\.exe(?:\s|$)")
SIMULATOR_RESULT_FILE = re.compile(r"^\s*%FileCheck\s.*--check-prefix", re.M)
SOURCE_CHANGED = "Probe source or helpers changed; rerun conformance"
NOT_SIMULATED = ("A probe must run a simulation with %t.exe and compare its results "
                 "using CHECK on its output or a --check-prefix check of a file it wrote")
# Scratch that is not a result of the simulation.
NOT_A_RESULT = re.compile(r"(?:\.exe|\.o|\.d)$|^(?:run-\d+|check|diag|output)\.log$")
# Only the file's creation time may differ between two runs of one design.
DUMP_DATE = re.compile(rb"\$date\b.*?\$end", re.S)
# A coverage database also records its run's identity, so compare its report.
COVERAGE_DATABASE = b"OBCOV\r\n\x1a"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes(path, primary=None):
    """Hash the primary source and the optional fixed helper directory."""
    files = {path.name: hashlib.sha256(primary).hexdigest() if primary is not None else digest(path)}
    helper = path.parent / "Inputs" / path.stem
    if helper.is_dir():
        files.update({"Inputs/" + path.stem + "/" + p.relative_to(helper).as_posix(): digest(p)
                      for p in sorted(helper.rglob("*")) if p.is_file()})
    combined = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    return combined, files


def read_probe(path):
    primary = path.read_bytes()
    source_sha256, files = source_hashes(path, primary)
    source = primary.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    fields = {}
    for key, value in DIRECTIVE.findall(source):
        fields.setdefault(key, []).append(value)
    tokens = lambda key: set(re.split(r"[,\s]+", " ".join(fields.get(key, [])))) - {""}
    return {"path": path, "standard": path.parent.name[4:],
            "source_sha256": source_sha256, "source_files": files,
            "clause": path.stem, "description": " ".join(fields.get("CLAUSE", [])),
            "valid_clause": len(fields.get("CLAUSE", [])) == 1 and
                            fields["CLAUSE"][0].lower() not in ("", "reference notes"),
            "runs": fields.get("RUN", []), "checks": bool(CHECK.search(source)),
            "diagnostics": bool(DIAGNOSTIC.search(source)),
            "xfail": tokens("XFAIL"), "requires": tokens("REQUIRES"),
            "since": " ".join(fields.get("SINCE", [])),
            "reference": " ".join(fields.get("REFERENCE", [])),
            "skip": " ".join(fields.get("SKIP", []))}


def source_unchanged(probe):
    try:
        return source_hashes(probe["path"])[0] == probe["source_sha256"]
    except OSError:
        return False


def filecheck_input_missing(argv, work):
    inputs = []
    arguments = iter(argv[1:])
    for argument in arguments:
        if argument == "--input-file":
            inputs.append(next(arguments, None))
        elif argument.startswith("--input-file="):
            inputs.append(argument.split("=", 1)[1])
    return (len(inputs) == 1 and inputs[0] not in (None, "", "-")
            and not (work / inputs[0]).is_file())


def filecheck_setup_error(record, argv, work):
    return (bool(record.get("launch_error")) or record["timeout"] or record["rc"] < 0
            or (os.name == "nt" and record["rc"] >= 0x80000000)
            or (record["rc"] >= 2 and not filecheck_input_missing(argv, work)))


def execute(argv, cwd, timeout, log):
    started = time.monotonic()
    try:
        process = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=os.name != "nt")
    except OSError as error:
        log.write_text(str(error) + "\n")
        return {"argv": [str(arg) for arg in argv], "rc": 127,
                "stdout": str(error) + "\n", "stderr": "", "timeout": False,
                "duration": round(time.monotonic() - started, 3), "launch_error": True}
    expired = False
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        expired = True
        try:
            if os.name == "nt":
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(process.pid)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        output, _ = process.communicate()
    output = output.decode("utf-8", errors="replace")
    log.write_text(output)
    return {"argv": [str(arg) for arg in argv], "rc": process.returncode,
            "stdout": output, "stderr": "", "timeout": expired,
            "duration": round(time.monotonic() - started, 3)}


def simulates_and_compares(probe):
    """IEEE clauses are claimed from execution: elaboration alone proves nothing."""
    return (any(SIMULATION.match(command) for command in probe["runs"]) and
            (probe["checks"] or any(SIMULATOR_RESULT_FILE.match(command)
                                    for command in probe["runs"])))


def execution_results(work, inputs, simulator_output, statuses, coverage_tool):
    """The observable results of one tier, for comparison with the other tier."""
    results = {"stdout": simulator_output.replace(str(work), "<work>"), "status": statuses, "files": {}}
    for path in sorted(work.rglob("*")):
        relative = path.relative_to(work).as_posix()
        if not path.is_file() or NOT_A_RESULT.search(path.name):
            continue
        contents = path.read_bytes()
        if contents.startswith(COVERAGE_DATABASE):
            contents = subprocess.run([str(coverage_tool), "report", str(path)], stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, cwd=work, timeout=30).stdout
        contents = DUMP_DATE.sub(b"", contents.replace(str(work).encode(), b"<work>"))
        fingerprint = hashlib.sha256(contents).hexdigest()
        if inputs.get(relative) != digest(path):
            results["files"][relative] = fingerprint
    return results


def execution_difference(native, bytecode):
    if native["status"] != bytecode["status"]:
        return "exit status"
    if native["stdout"] != bytecode["stdout"]:
        return "standard output"
    if native["files"] != bytecode["files"]:
        names = set(native["files"]) ^ set(bytecode["files"])
        names |= {name for name in set(native["files"]) & set(bytecode["files"])
                  if native["files"][name] != bytecode["files"][name]}
        return "written files " + ", ".join(sorted(names))
    return None


def run_probe(probe, tier, args, features, resources):
    path = probe["path"]
    try:
        relative = path.relative_to(ROOT)
    except ValueError:
        relative = path.relative_to(args.tests)
    result = {"standard": probe["standard"], "clause": probe["clause"],
              "description": probe["description"], "file": relative.as_posix(),
              "tier": tier, "commands": [], "source_sha256": probe["source_sha256"],
              "source_files": probe["source_files"], "reason": "",
              "supported_since": probe["since"] or None}
    if not source_unchanged(probe):
        return {**result, "status": "error", "reason": SOURCE_CHANGED}
    if not probe["valid_clause"]:
        return {**result, "status": "error", "reason": "A probe needs one specific CLAUSE description"}
    if result["supported_since"] and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", result["supported_since"]):
        return {**result, "status": "error", "reason": "SINCE must contain a release version X.Y.Z"}
    if probe["requires"] - {"upf", "native-elf"} or probe["xfail"] - {"*", "native", "bytecode"}:
        return {**result, "status": "error", "reason": "Unknown REQUIRES or XFAIL token"}
    if sum(bool(probe[key]) for key in ("reference", "skip", "runs")) != 1:
        return {**result, "status": "error", "reason": "Use exactly one of RUN, REFERENCE, or SKIP"}
    for key, status in (("reference", "reference"), ("skip", "skip")):
        if probe[key]:
            return {**result, "status": status, "reason": probe[key]}
    if probe["runs"] and not simulates_and_compares(probe):
        return {**result, "status": "error", "reason": NOT_SIMULATED}
    missing = probe["requires"] - features
    if missing:
        return {**result, "status": "skip", "reason": "Requires " + ", ".join(sorted(missing))}
    with tempfile.TemporaryDirectory(prefix=probe["clause"] + "-" + tier + "-", dir=args.work) as temporary:
        return run_commands(probe, tier, args, resources, result, Path(temporary))


def run_commands(probe, tier, args, resources, result, work):
    path = probe["path"]
    helper = path.parent / "Inputs" / path.stem
    inputs = {}
    if helper.is_dir():
        shutil.copytree(helper, work, dirs_exist_ok=True)
        inputs = {item.relative_to(helper).as_posix(): digest(item)
                  for item in helper.rglob("*") if item.is_file()}
    substitutions = {"%talos": str(args.compiler), "%clang": str(args.clang),
                     "%FileCheck": str(args.filecheck),
                     "%resource_dir": resources, "%tier": tier, "%S": str(path.parent),
                     "%s": str(path), "%t": str(work / "probe")}
    pattern = re.compile("|".join(re.escape(key) for key in sorted(substitutions, key=len, reverse=True)))
    simulator_output = []
    tool_output = []
    simulator_statuses = []
    reason = ""
    setup_error = False
    for index, command in enumerate(probe["runs"], 1):
        negative = re.match(r"^\s*%not(?:\s|$)", command)
        child = command[negative.end():].lstrip() if negative else command
        expanded = pattern.sub(lambda match: shlex.quote(substitutions[match[0]]), child)
        timeout = 90 if "%talos" in command or "%clang" in command else 15
        try:
            argv = shlex.split(expanded)
        except ValueError as error:
            reason, setup_error = "Malformed RUN: " + str(error), True
            break
        if not argv or any(arg in {"|", ";", "&&", "||", ">", "<", "2>&1"} for arg in argv):
            reason, setup_error = "RUN must contain one command without shell operators", True
            break
        record = execute(argv, work, timeout, work / f"run-{index:02}.log")
        record.update(command=("%not " if negative else "") + expanded, negated=bool(negative))
        result["commands"].append(record)
        if SIMULATION.match(command):
            simulator_output.append(record["stdout"])
            simulator_statuses.append(record["rc"])
        else:
            tool_output.append(record["stdout"])
        is_filecheck = argv[0] == str(args.filecheck)
        setup_error = (filecheck_setup_error(record, argv, work) if is_filecheck
                       else bool(record.get("launch_error")))
        crashed = record["rc"] < 0 or (os.name == "nt" and record["rc"] >= 0x80000000)
        success = not setup_error and (record["rc"] > 0 and not crashed if negative else record["rc"] == 0)
        if is_filecheck and filecheck_input_missing(argv, work):
            success = False
        if record["timeout"] or not success:
            reason = f"RUN {index} timed out" if record["timeout"] else f"RUN {index} exited with status {record['rc']}"
            break
    # CHECK compares what the simulator printed. A diagnostic is not a result of
    # the simulation, so DIAG alone sees the compiler's output.
    for present, prefix, text, log in ((probe["checks"], "CHECK", simulator_output, "output.log"),
                                       (probe["diagnostics"], "DIAG", tool_output, "diag.log")):
        if reason or not present:
            continue
        combined = work / log
        combined.write_text("".join(text))
        checked = execute([str(args.filecheck), str(path), "--allow-empty", "--check-prefix=" + prefix,
                           "--input-file=" + str(combined)], work, 15, work / "check.log")
        result["commands"].append(checked)
        if checked["rc"] or checked["timeout"]:
            setup_error = filecheck_setup_error(checked, checked["argv"], work)
            reason = ("Output check timed out" if checked["timeout"]
                      else f"Output did not match {prefix} directives")
    if not reason and not setup_error:
        result["execution"] = execution_results(work, inputs, "".join(simulator_output), simulator_statuses,
                                                args.coverage)
    expected = bool(probe["xfail"] & {"*", tier})
    result["status"] = "error" if setup_error else (("xfail" if expected else "fail") if reason else ("xpass" if expected else "pass"))
    result["reason"] = reason or ("Expected failure now passes" if expected else "")
    return result


def main():
    started = time.monotonic()
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("compiler", "clang", "filecheck", "coverage", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--tests", type=Path, default=ROOT / "test/Conformance")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--standard", choices=("1800", "1801"))
    parser.add_argument("--only", nargs="+")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    for key in ("compiler", "clang", "filecheck", "coverage", "tests", "output"):
        setattr(args, key, getattr(args, key).resolve())
    for key in ("compiler", "clang", "filecheck", "coverage"):
        path = getattr(args, key)
        if not path.is_file() or not os.access(path, os.X_OK):
            parser.error(f"{key} is not executable: {path}")
    args.output.mkdir(parents=True, exist_ok=True)
    only = {item[:-3] if item.endswith(".sv") else item for item in args.only} if args.only else None
    probes = [read_probe(path) for standard in ("1800", "1801")
              if not args.standard or args.standard == standard
              for path in sorted((args.tests / ("IEEE" + standard)).glob("*.sv"))]
    if only:
        missing = only - {probe["clause"] for probe in probes}
        if missing:
            parser.error("Unknown clause probes: " + ", ".join(sorted(missing)))
        probes = [probe for probe in probes if probe["clause"] in only]
    if not probes:
        parser.error("No clause probes matched")
    compiler_sha256 = digest(args.compiler)
    version = subprocess.check_output([args.compiler, "--version"], text=True).strip()
    compiler_version = version.splitlines()[0].replace("talos version ", "", 1).strip()
    help_text = subprocess.check_output([args.compiler, "--help-hidden"], text=True)
    resources = subprocess.check_output([args.compiler, "--print-resource-dir"], text=True).strip()
    resource_sha256 = fingerprint_resources(resources)
    features = {"native-elf"} if sys.platform.startswith("linux") else set()
    if re.search(r"^\s*--upf(?:[=\s]|$)", help_text, re.M):
        features.add("upf")
    results = []
    with tempfile.TemporaryDirectory(prefix="work-", dir=args.output) as temporary:
        args.work = Path(temporary)
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(run_probe, probe, tier, args, features, resources)
                       for probe in probes for tier in ("native", "bytecode")]
            for future in as_completed(futures):
                record = future.result()
                results.append(record)
                if record["status"] in ("fail", "error", "xpass"):
                    print(record["status"].upper(), record["standard"], record["clause"],
                          record["tier"], record["reason"], flush=True)
    changed = {(probe["standard"], probe["clause"]) for probe in probes
               if not source_unchanged(probe)}
    for record in results:
        if (record["standard"], record["clause"]) in changed and record["reason"] != SOURCE_CHANGED:
            record.update(status="error", reason=SOURCE_CHANGED)
            print("ERROR", record["standard"], record["clause"], SOURCE_CHANGED, flush=True)
    tiers = {}
    for record in results:
        tiers.setdefault((record["standard"], record["clause"]), {})[record["tier"]] = record
    for pair in tiers.values():
        native, bytecode = pair.get("native"), pair.get("bytecode")
        if not native or not bytecode or "execution" not in native or "execution" not in bytecode:
            continue
        difference = execution_difference(native["execution"], bytecode["execution"])
        if difference:
            for record in (native, bytecode):
                record.update(status="fail", reason="Native and bytecode execution results differ: " + difference)
                print("FAIL", record["standard"], record["clause"], record["tier"], record["reason"], flush=True)
    if digest(args.compiler) != compiler_sha256:
        raise RuntimeError("The compiler changed during the run")
    if fingerprint_resources(resources) != resource_sha256:
        raise RuntimeError("Compiler resources changed during the run")
    report = {"compiler_sha256": compiler_sha256, "resource_sha256": resource_sha256, "version": version,
              "compiler_version": compiler_version,
              "seconds": round(time.monotonic() - started, 3),
              "date": datetime.now(timezone.utc).isoformat(timespec="seconds"),
              "results": sorted(results, key=lambda item: (item["standard"], item["clause"], item["tier"]))}
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(probes)} clauses:", dict(sorted(Counter(item["status"] for item in results).items())))
    passed = Counter((row["standard"], row["clause"]) for row in results
                     if row["status"] in ("pass", "xpass"))
    missing_since = [probe for probe in probes if passed[probe["standard"], probe["clause"]] == 2
                     and not probe["since"]]
    for probe in missing_since:
        print("MISSING SINCE", probe["standard"], probe["clause"], flush=True)
    return int(any(item["status"] == "error" for item in results) or
               (args.check and (bool(missing_since) or any(item["status"] in ("fail", "xpass") for item in results))))


if __name__ == "__main__":
    raise SystemExit(main())
