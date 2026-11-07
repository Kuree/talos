#ifndef TALOS_UPF_RETENTIONSELECTION_H
#define TALOS_UPF_RETENTIONSELECTION_H
#include "Retention.h"
#include "llvm/ADT/StringSet.h"

namespace talos {
// Compiler-only effective-list projection. A member retains both the selected
// hierarchy object and the aggregate selector that gives it precedence.
class RetentionSelection {
public:
  explicit RetentionSelection(sim::SimDesignOp design);
  mlir::LogicalResult initialize();
  upf::UPFDomainOp domain(llvm::StringRef path) const;
  const llvm::StringSet<> &processes() const { return requestedProcesses; }
  unsigned rank(upf::RetentionAttr strategy, const RetentionRegister &reg,
                bool &partial);
  void record(const RetentionRegister &reg);
  mlir::LogicalResult validateContext(const RetentionRegister &reg);
  mlir::LogicalResult validate();

private:
  struct Scope {
    llvm::StringRef path;
    std::optional<uint64_t> parent;
    bool instance;
  };
  struct Member {
    upf::RetentionElementAttr element, origin;
  };
  struct Group {
    upf::UPFRetentionElementsOp declaration;
    llvm::SmallVector<Member> members;
    llvm::SmallVector<const RetentionRegister *> states;
  };
  sim::SimDesignOp design;
  mlir::ModuleOp module;
  llvm::DenseMap<uint64_t, Scope> scopes;
  llvm::StringMap<uint64_t> scopeIDs;
  std::map<llvm::StringRef, uint64_t, upf::InstancePathLess> scopePaths;
  llvm::DenseMap<uint64_t, uint64_t> storageScopes;
  llvm::DenseMap<uint64_t, std::pair<size_t, size_t>> intervals;
  llvm::DenseMap<uint64_t, uint64_t> owners;
  llvm::DenseMap<uint64_t, unsigned> depths;
  llvm::DenseMap<uint64_t, llvm::SmallVector<uint64_t>> children;
  llvm::DenseMap<mlir::Attribute, upf::UPFDesignAttributesOp> annotations;
  llvm::DenseMap<mlir::Attribute, unsigned> groupIDs;
  llvm::SmallVector<upf::UPFDomainOp> domains;
  llvm::SmallVector<Group, 0> groups;
  llvm::SmallVector<RetentionRegister, 0> states;
  llvm::StringSet<> requestedProcesses;
  mlir::SymbolTableCollection symbols;
  llvm::DenseMap<mlir::Attribute, mlir::ArrayAttr> supplyKeys;
  llvm::DenseMap<mlir::Operation *, mlir::ArrayAttr> domainKeys;
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Operation *>, mlir::ArrayAttr>
      storageKeys;
  size_t work = 0;
  bool exceeded = false;
  bool charge(size_t count = 1);
  bool within(uint64_t scope, uint64_t root) const;
  unsigned specificity(upf::RetentionElementAttr element) const;
  bool matches(upf::RetentionElementAttr element, const RetentionRegister &reg,
               bool direct = false, bool domainOnly = false) const;
  bool filter(upf::RetentionElementAttr element,
              std::optional<upf::RetentionFilter> choice) const;
  unsigned groupRank(Group &group, const RetentionRegister &reg, bool &partial);
  mlir::LogicalResult expand(Group &group);
  uint64_t lexicalScope(llvm::StringRef path, uint64_t fallback);
  mlir::ArrayAttr policyKey(mlir::FlatSymbolRefAttr ref);
  mlir::ArrayAttr domainKey(upf::UPFDomainOp domain);
  mlir::ArrayAttr storageKey(const RetentionRegister &reg);
  bool equivalent(const RetentionRegister &a, const RetentionRegister &b);
};
} // namespace talos
#endif
