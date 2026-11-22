"""Keep native runtime entry names in their catalog.

Compiler sources name a runtime entry through NativeRuntimeEntries.def, so its
prototype and facts live in one row. A string literal that spells a complete
runtime symbol elsewhere in lib/, include/ or tools/ bypasses the catalog.
"""

from pathlib import Path
import re
import sys


source = Path(sys.argv[1])
symbol = re.compile(r'"(talos_rt_v[0-9]+_[a-z0-9_]*[a-z0-9])"')
catalog = "include/talos/Dialect/Native/NativeRuntimeEntries.def"
# Literals that name a runtime symbol generated code does not call, with the
# reason: (file, symbol).
allowed = {
    # The driver exports this runtime query to VPI applications; generated
    # code never calls it.
    ("tools/driver/TargetBackend.cpp", "talos_rt_v1_vpi_object_model"),
}
errors = []
for directory in ("lib", "include", "tools"):
    for path in sorted((source / directory).rglob("*")):
        if path.suffix not in {".cpp", ".h", ".def", ".td"}:
            continue
        relative = path.relative_to(source).as_posix()
        if relative == catalog:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            for match in symbol.finditer(line):
                if (relative, match.group(1)) in allowed:
                    continue
                errors.append(f"{relative}:{number}: runtime symbol "
                              f"'{match.group(1)}' outside {catalog}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("runtime symbols: every lib/, include/ and tools/ reference goes "
      "through the catalog")
