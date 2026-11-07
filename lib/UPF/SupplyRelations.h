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
  enum class InitialValues { Check, Defer };
  explicit SupplyRelations(mlir::ModuleOp module) : module(module) {}
  // Only pre-propagation source snapshots may defer placeholder initial values.
  // Every final source/raw-IR consumer checks the actual resolved values.
  mlir::LogicalResult
  initialize(InitialValues initialValues = InitialValues::Check);
  bool matches(mlir::FlatSymbolRefAttr a, mlir::FlatSymbolRefAttr b, Kind kind,
               bool pgOnly) const;
  llvm::ArrayRef<upf::UPFSupplyOp> supplies() const { return roots; }
  unsigned electricalLeader(unsigned index) const {
    return electrical.findLeader(index);
  }
  unsigned interchangeableLeader(unsigned index) const {
    return interchangeable.findLeader(index);
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
mlir::LogicalResult
validateUPFCompositeDomains(mlir::ModuleOp module,
                            const SupplyRelations &relations);
} // namespace talos
#endif
