"""Render two clause tables from source metadata and direct test reports."""

from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from compiler_resources import fingerprint_resources


PASSED = {"pass", "xpass"}


def status(records):
    if records and all(row["status"] == "skip" and row.get("reason") == "Requires native-elf"
                       for row in records):
        return '<span class="status-muted">Excluded</span>'
    if not records or any(row["status"] not in PASSED for row in records):
        return "No"
    versions = {row.get("supported_since") for row in records}
    if len(versions) != 1 or not all(versions):
        raise ValueError("A supported clause needs one shared // SINCE: version")
    return versions.pop()


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ")


def clause_files(directory):
    def order(path):
        return tuple((0, int(part)) if part.isdigit() else (1, part)
                     for part in path.stem.split("."))
    for path in sorted(directory.glob("*.sv"), key=order):
        fields = defaultdict(list)
        for key, value in re.findall(
                r"^[ \t]*//[ \t]*(CLAUSE|REFERENCE|SKIP|SINCE)[ \t]*:[ \t]*(.*?)[ \t]*$",
                path.read_text(), re.M):
            fields[key].append(value)
        metadata = {key: " ".join(values) for key, values in fields.items()}
        if len(fields["CLAUSE"]) != 1 or metadata.get("CLAUSE", "").lower() in ("", "reference notes"):
            raise ValueError(f"A specific // CLAUSE: description is required in {path}")
        yield path, metadata


def validate(records, path, label, metadata):
    tiers = [row.get("tier") for row in records]
    if len(tiers) != 2 or set(tiers) != {"native", "bytecode"}:
        raise ValueError(f"Expected one native and one bytecode {label} report for {path.parent.name}/{path.name}")
    files = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()}
    helper = path.parent / "Inputs" / path.stem
    files.update({"Inputs/" + path.stem + "/" + item.relative_to(helper).as_posix():
                  hashlib.sha256(item.read_bytes()).hexdigest()
                  for item in sorted(helper.rglob("*")) if item.is_file()})
    expected = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    since = metadata.get("SINCE") or None
    for row in records:
        if row.get("source_sha256") != expected:
            issue = "Stale" if row.get("source_sha256") else "Missing source fingerprint in"
            raise ValueError(f"{issue} {label} report for {path.parent.name}/{path.name}; rerun conformance")
        if "supported_since" not in row or row["supported_since"] != since:
            raise ValueError(f"Mismatched SINCE in {label} report for {path.parent.name}/{path.name}; rerun conformance")


def load_report(report, compiler):
    data = json.loads(report.read_text())
    expected = hashlib.sha256(compiler.read_bytes()).hexdigest()
    if data.get("compiler_sha256") != expected:
        raise ValueError(f"Stale conformance report for {compiler}; rerun conformance")
    resources = subprocess.check_output([str(compiler), "--print-resource-dir"], text=True).strip()
    if data.get("resource_sha256") != fingerprint_resources(resources):
        raise ValueError(f"Stale compiler resources in conformance report for {compiler}; rerun conformance")
    for row in data["results"]:
        if row["status"] == "error":
            raise ValueError(f"Conformance setup failed for IEEE{row['standard']}/{row['clause']}: {row['reason']}")
    return data


def render_support_pages(source, output, write, data):
    records = defaultdict(list)
    for row in data["results"]:
        records[str(row["standard"]), str(row["clause"])].append(row)
    pages = []
    for standard in ("1800", "1801"):
        title = f"IEEE {standard} support"
        columns = ["Clause", "Feature", "Supported since"]
        lines = [f"# {title}", "",
                  "```{container} conformance-table", "",
                  "| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
        for path, metadata in clause_files(source / "test/Conformance" / ("IEEE" + standard)):
            key = standard, path.stem
            validate(records[key], path, "current", metadata)
            if metadata.get("REFERENCE"):
                level = '<span class="status-muted">Reference</span>'
            elif metadata.get("SKIP"):
                level = '<span class="status-muted">Excluded</span>'
            else:
                level = status(records[key])
            label = "Annex " + path.stem if path.stem.isalpha() else path.stem
            if "." not in path.stem:
                label = "**" + label + "**"
            lines.append("| " + " | ".join(map(cell, [label, metadata["CLAUSE"], level])) + " |")
        lines += ["", "```", ""]
        relative = f"conformance/ieee-{standard}.md"
        write(output / relative, "\n".join(lines))
        pages.append({"path": relative, "kind": "conformance", "name": title})
    return pages
