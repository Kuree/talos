#ifndef TALOS_UPF_SUPPLYRELATIONS_H
#define TALOS_UPF_SUPPLYRELATIONS_H
#include "mlir/IR/BuiltinOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/StringMap.h"

namespace talos {
// Electrical, functional and interchangeable predicates are separate. An
// explicit non-interchangeability constraint stays at its declared granularity;
// one such edge must not poison an entire functional equivalence component.
class SupplyRelations {
public:
  using Kind = upf::SupplyEquivalenceKind;
  explicit SupplyRelations(mlir::ModuleOp module) : module(module) {}
  mlir::LogicalResult initialize();
  bool matches(mlir::FlatSymbolRefAttr a, mlir::FlatSymbolRefAttr b, Kind kind,
               bool pgOnly) const;
  llvm::ArrayRef<upf::UPFSupplyOp> supplies() const { return roots; }
  unsigned electricalLeader(unsigned index) const {
    return electrical.findLeader(index);
  }

private:
  mlir::ModuleOp module;
  llvm::SmallVector<upf::UPFSupplyOp> roots;
  llvm::StringMap<unsigned> indices;
  llvm::StringMap<upf::UPFSupplySetOp> sets;
  llvm::StringMap<unsigned> setIndices;
  llvm::IntEqClasses electrical, interchangeable, functional;
  llvm::IntEqClasses setElectrical, setInterchangeable, setFunctional;
  size_t work = 0;
  bool charge(size_t count = 1);
  unsigned root(mlir::Attribute reference) const;
  const llvm::IntEqClasses &classes(Kind kind) const;
};
} // namespace talos
#endif
