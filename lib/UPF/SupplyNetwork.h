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
struct SupplyObject {
  enum Kind { Net, Port, Function } kind;
  std::string path, scope;
  bool operator==(const SupplyObject &other) const {
    return kind == other.kind && path == other.path;
  }
  bool operator!=(const SupplyObject &other) const { return !(*this == other); }
};
using SupplyPorts = std::map<std::string, SupplyPort>;
// The Boolean selects HighConn; LowConn and HighConn are independent sides.
using SupplyBindings = std::map<std::pair<std::string, bool>, SupplyObject>;
using SupplyFunctions = std::map<std::string, std::string>;
using SupplyEquivalences = std::vector<std::pair<SupplyObject, SupplyObject>>;
struct SupplyRoot {
  bool writable = true, ground = false;
};
struct ResolvedSupplies {
  std::vector<SupplyRoot> roots;
  std::map<std::string, unsigned> nets, ports, functions, handles;
};
std::string absoluteSupplyHandle(llvm::StringRef path);
mlir::LogicalResult bindSupply(
    const SupplyObject &net, llvm::StringRef port, SupplyBindings &bindings,
    llvm::function_ref<void(const llvm::Twine &)> report,
    llvm::function_ref<bool(const SupplyObject &, const SupplyObject &)> same =
        {});
mlir::FailureOr<ResolvedSupplies>
resolveSupplies(const std::set<std::string> &nets, const SupplyPorts &ports,
                const SupplyFunctions &functions,
                const SupplyBindings &bindings,
                const SupplyEquivalences &equivalences,
                llvm::function_ref<void(const llvm::Twine &)> report);
} // namespace talos
#endif
