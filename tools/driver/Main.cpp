//===- Main.cpp - Production Talos driver entry point ------------------===//

#include "DriverMain.h"

#include "llvm/Support/InitLLVM.h"

#if defined(__linux__) && defined(__GLIBC__)
#include <climits>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

namespace {

// A compile walks gigabytes of pointer-linked IR, so 4 KiB heap pages cost
// about 14% of wall clock in TLB misses and page faults on a large design.
// glibc reads its allocator tunables only at startup and has no call to set
// them, so the driver runs itself once with them in the environment.
//   hugetlb: madvise heap growth of at least one huge page.
//   top_pad: grow a thread heap by whole 64 MiB, or its small steps never
//            reach that minimum and thread arenas keep 4 KiB pages.
//   mmap_threshold: top_pad alone would pin this at 128 KiB, sending every
//            large buffer through a fresh mapping.
//   trim_threshold: keep freed pages rather than fault them back in.
constexpr char kHeapTunables[] =
    "glibc.malloc.hugetlb=1:glibc.malloc.top_pad=67108864:"
    "glibc.malloc.mmap_threshold=33554432:"
    "glibc.malloc.trim_threshold=268435456";

void useHugePageHeap(char **argv) {
  if (const char *tunables = std::getenv("GLIBC_TUNABLES")) {
    // Children such as the simulation under --run keep their usual allocator.
    if (std::strcmp(tunables, kHeapTunables) == 0)
      unsetenv("GLIBC_TUNABLES");
    return;
  }
  char path[PATH_MAX];
  ssize_t length = readlink("/proc/self/exe", path, sizeof(path) - 1);
  if (length <= 0)
    return;
  path[length] = '\0';
  if (setenv("GLIBC_TUNABLES", kHeapTunables, /*overwrite=*/1) != 0)
    return;
  execv(path, argv);
  // No /proc or an unlinked executable: the default heap still works.
  unsetenv("GLIBC_TUNABLES");
}

} // namespace
#endif

int main(int argc, char **argv) {
#if defined(__linux__) && defined(__GLIBC__)
  useHugePageHeap(argv);
#endif
  llvm::InitLLVM initLLVM(argc, argv);
  return talos::driver::runTalosDriver(argc, argv);
}
