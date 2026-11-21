"""Keep native runtime entry names in their catalog.

Compiler sources name a runtime entry through NativeRuntimeEntries.def, so its
prototype and facts live in one row. A string literal that spells a complete
runtime symbol elsewhere in lib/ bypasses the catalog.
"""

from pathlib import Path
import re
import sys


source = Path(sys.argv[1])
symbol = re.compile(r'"(talos_rt_v[0-9]+_[a-z0-9_]*[a-z0-9])"')
# Files that may still spell a symbol, with the reason.
allowed = {
    # RuntimeToLLVM declares its entries from RuntimeABI.def.
    "lib/Conversion/RuntimeToLLVM/RuntimeToLLVMPatterns.cpp",
}
errors = []
for path in sorted((source / "lib").rglob("*")):
    if path.suffix not in {".cpp", ".h", ".def", ".td"}:
        continue
    relative = path.relative_to(source).as_posix()
    if relative in allowed:
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for match in symbol.finditer(line):
            errors.append(f"{relative}:{number}: runtime symbol "
                          f"'{match.group(1)}' outside NativeRuntimeEntries.def")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("runtime symbols: every lib/ reference goes through the catalog")
