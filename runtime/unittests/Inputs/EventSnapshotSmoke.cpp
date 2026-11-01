// Standalone entry for linking the same unit-test probe to wasm32 runtime.
#include "EventSnapshotSmoke.h"
#include <cstring>

int main(int argc, char **argv) {
  bool bytecode = argc > 1 && std::strcmp(argv[1], "bytecode") == 0;
  bool maskedNBA = argc > 2;
  bool assign = maskedNBA && std::strcmp(argv[2], "assign-nba") == 0;
  bool twoStateRHS = argc > 3;
  int result = talos::test::runEventSnapshotSmoke(bytecode, maskedNBA, assign,
                                                  twoStateRHS);
  if (!result)
    std::printf("event snapshot %s passed pointer=%u\n",
                bytecode ? "bytecode" : "native",
                static_cast<unsigned>(sizeof(void *) * 8));
  return result;
}
