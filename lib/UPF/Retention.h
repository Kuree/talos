#ifndef TALOS_UPF_RETENTION_H
#define TALOS_UPF_RETENTION_H
#include "ControlValue.h"
#include "llvm/ADT/DenseSet.h"
#include <functional>
namespace talos {
namespace upf_detail {
class ClockSnapshots;
}
struct RetentionAlias {
  llvm::StringRef path;
  uint64_t scope;
  bool partial = false;
};
// An immutable plan over original physical state. All domains are planned and
// collective constraints validated before any writer or domain is rewritten.
struct RetentionRegister {
  sim::SimStorageDeclOp declaration;
  llvm::SmallVector<RetentionAlias> aliases;
  llvm::SmallVector<mlir::Operation *> writers;
  llvm::SmallVector<llvm::StringRef> processes;
  upf::UPFDomainOp domain;
  upf::RetentionAttr strategy;
  upf_detail::Descriptor visible{}, backing{};
};
using RetentionPlans =
    llvm::DenseMap<mlir::Operation *, llvm::SmallVector<RetentionRegister, 1>>;
mlir::LogicalResult
planRetentions(sim::SimDesignOp design, sim::SimFuncOp root,
               const llvm::StringMap<upf_detail::Descriptor> &descriptors,
               const llvm::StringMap<upf_detail::Descriptor> &supplies,
               RetentionPlans &plans);
struct RetentionLoweringOptions {
  sim::SimDesignOp design;
  upf::UPFDomainOp domain;
  sim::SimFuncOp root;
  const llvm::StringMap<upf_detail::Descriptor> &descriptors, &supplies;
  upf_detail::Descriptor domainEpoch;
  upf_detail::ClockSnapshots *clocks;
  llvm::ArrayRef<upf_detail::Descriptor> domainDependencies;
  std::function<upf_detail::Descriptor(mlir::Location, llvm::StringRef,
                                       mlir::Type)>
      storage;
  std::function<sim::SimFuncOp(mlir::Location, llvm::StringRef,
                               llvm::ArrayRef<mlir::Type>, sim::EntryKind)>
      function;
  std::function<mlir::Value(mlir::OpBuilder &, mlir::Location, mlir::Value)>
      domainNormal;
  std::function<mlir::Value(mlir::OpBuilder &, mlir::Location, mlir::Value,
                            mlir::FlatSymbolRefAttr)>
      readSupply;
  std::function<llvm::SmallVector<upf_detail::Descriptor>(
      mlir::FlatSymbolRefAttr)>
      supplyDependencies;
  llvm::ArrayRef<RetentionRegister> plan;
};
// Functional statement groups remain intact until all physical domain owners
// are known. The guard owns every N/Q publication, including both NBA paths
// for a dynamic-zero Balloon delay. Initial updates never enter this list.
struct RetentionWrite {
  upf_detail::Descriptor domainEpoch;
  mlir::Operation *guard;
  llvm::SmallVector<mlir::Operation *> enqueues;
};
struct RetentionLoweringResult {
  llvm::DenseSet<uint64_t> storage;
  llvm::DenseSet<mlir::Operation *> publishedProcesses;
  llvm::SmallVector<RetentionWrite> writes;
};
// IEEE 1801-2018 5.7.3/5.9.3/6.50/9.7: resolve effective strategies before
// validating their writers, then preserve separate backing and output state.
mlir::LogicalResult lowerRetentions(const RetentionLoweringOptions &options,
                                    RetentionLoweringResult &result);
} // namespace talos
#endif
