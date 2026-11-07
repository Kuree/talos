#ifndef TALOS_UPF_PORTSUPPLY_H
#define TALOS_UPF_PORTSUPPLY_H
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringMap.h"
#include <map>

namespace talos {
// Immutable port identity and supply facts for source-independent preflight
// and lowering. Domain facts outlive individual domain rewrites/erasures.
class PortSupplyAnalysis {
public:
  PortSupplyAnalysis(mlir::ModuleOp module, sim::SimDesignOp design);
  mlir::LogicalResult initialize();
  bool usesBindings() const {
    return !actors.empty() || hasSupplies || hasOpaque;
  }
  sim::SimPortDeclOp portForActor(uint64_t actor) const;
  bool publicationIsProven(uint64_t actor) const {
    return provenPublications.contains(actor);
  }
  bool inputControl(llvm::StringRef path,
                    llvm::ArrayRef<llvm::StringRef> boundaries) const;
  mlir::FailureOr<bool> isolate(upf::UPFDomainOp domain,
                                sim::SimPortDeclOp port);
  mlir::LogicalResult
  checkIsolationOutputs(upf::UPFDomainOp domain,
                        llvm::ArrayRef<llvm::StringRef> boundaries);

private:
  struct Domain {
    mlir::ArrayAttr included, excluded;
    mlir::FlatSymbolRefAttr primary;
    bool retainedOutput = false;
    bool contains(llvm::StringRef path) const;
  };
  struct Root {
    uint64_t scope, width;
  };
  struct Writers {
    llvm::SmallVector<uint64_t> scopes;
    bool unknown = false;
  };
  using Properties =
      std::map<std::string, llvm::SmallVector<upf::UPFPortAttributesOp>>;
  mlir::ModuleOp module;
  sim::SimDesignOp design;
  llvm::StringMap<sim::SimPortDeclOp> paths;
  llvm::DenseMap<uint64_t, sim::SimPortDeclOp> actors;
  llvm::DenseMap<uint64_t, uint64_t> formalActors;
  llvm::DenseSet<uint64_t> provenPublications;
  llvm::DenseMap<uint64_t, sim::SimScopeDeclOp> scopes;
  llvm::StringMap<bool> semanticScopes;
  llvm::StringMap<upf::UPFSupplySetOp> sets;
  llvm::StringMap<Properties> annotations;
  std::map<std::pair<bool, uint64_t>, Root> roots;
  llvm::DenseMap<uint64_t, Writers> writers;
  llvm::SmallVector<uint64_t> opaqueOutputs;
  llvm::SmallVector<Domain> domains;
  bool hasSupplies = false;
  bool hasOpaque = false;
  size_t work = 0;
  bool charge(size_t count = 1);
  llvm::StringRef owner(sim::SimPortDeclOp port) const;
  mlir::FailureOr<const Domain *> domain(llvm::StringRef path);
  mlir::FailureOr<mlir::FlatSymbolRefAttr> driver(sim::SimPortDeclOp port);
  bool equal(mlir::FlatSymbolRefAttr a, mlir::FlatSymbolRefAttr b,
             bool pgOnly) const;
};
} // namespace talos
#endif
