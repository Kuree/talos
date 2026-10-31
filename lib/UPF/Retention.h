#ifndef TALOS_UPF_RETENTION_H
#define TALOS_UPF_RETENTION_H
#include "ControlValue.h"
#include "llvm/ADT/DenseSet.h"
#include <functional>
namespace talos {
struct RetentionLoweringOptions {
  sim::SimDesignOp design;
  upf::UPFDomainOp domain;
  sim::SimFuncOp root;
  const llvm::StringMap<upf_detail::Descriptor> &descriptors, &supplies;
  upf_detail::Descriptor domainEpoch;
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
};
struct RetentionLoweringResult {
  llvm::DenseSet<uint64_t> storage;
  llvm::SmallVector<mlir::FlatSymbolRefAttr> updates;
};
// IEEE 1801-2018 5.7.3/5.9.3/6.50/9.7: resolve effective strategies before
// validating their writers, then preserve separate backing and output state.
mlir::LogicalResult lowerRetentions(const RetentionLoweringOptions &options,
                                    RetentionLoweringResult &result);
} // namespace talos
#endif
