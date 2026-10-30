#ifndef TALOS_UPF_SUPPLYNETWORK_H
#define TALOS_UPF_SUPPLYNETWORK_H
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include <map>
#include <set>
#include <string>
#include <vector>

namespace talos {
struct SupplyPort {
  enum Direction { In, Out, InOut } direction = In;
  bool switchOutput = false;
};
using SupplyPorts = std::map<std::string, SupplyPort>;
// The Boolean selects HighConn; LowConn and HighConn are independent sides.
using SupplyBindings = std::map<std::pair<std::string, bool>, std::string>;
struct SupplyRoot {
  bool writable = true, ground = false;
};
struct ResolvedSupplies {
  std::vector<SupplyRoot> roots;
  std::map<std::string, unsigned> nets, ports, handles;
};
std::string absoluteSupplyHandle(llvm::StringRef path);
mlir::LogicalResult
bindSupply(llvm::StringRef net, llvm::StringRef port, SupplyBindings &bindings,
           llvm::function_ref<void(const llvm::Twine &)> report);
mlir::FailureOr<ResolvedSupplies>
resolveSupplies(const std::set<std::string> &nets, const SupplyPorts &ports,
                const SupplyBindings &bindings,
                llvm::function_ref<void(const llvm::Twine &)> report);
} // namespace talos
#endif
