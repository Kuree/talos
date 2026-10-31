// Standalone entry for linking the same unit-test probe to wasm32 runtime.
#include "EventSnapshotSmoke.h"
#include <cstring>

int main(int argc, char **argv) {
  bool bytecode = argc > 1 && std::strcmp(argv[1], "bytecode") == 0;
  int result = talos::test::runEventSnapshotSmoke(bytecode);
  if (!result)
    std::printf("event snapshot %s passed pointer=%u\n",
                bytecode ? "bytecode" : "native",
                static_cast<unsigned>(sizeof(void *) * 8));
  return result;
}
