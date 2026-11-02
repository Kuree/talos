//===- PrepareExpressions.h - Immutable source expression relations -------===//

#ifndef TALOS_LIB_CONVERSION_TALOSTOSIMULATION_PREPAREEXPRESSIONS_H
#define TALOS_LIB_CONVERSION_TALOSTOSIMULATION_PREPAREEXPRESSIONS_H

#include "PrepareTopology.h"
#include "PrepareUnits.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/StringSet.h"
#include <optional>

namespace talos::simlowering {
struct VPIExpressionEndpoint {
  sim::VPIObjectRefAttr reference;
  uint32_t kind;
};

/// Resolve a whole declaration use without replacing a selected, converted,
/// or computed expression with its underlying storage. The source symbol and
/// retained declaration metadata are authoritative, including local variables
/// whose immutable declaration has no design-lifetime value.
class VPIExpressionResolver {
public:
  VPIExpressionResolver(sim::SimDesignOp design,
                        const llvm::StringMap<DescriptorInfo> &descriptors);
  std::optional<VPIExpressionEndpoint> resolve(mlir::Operation *expression);

private:
  sim::SimDesignOp design;
  mlir::ModuleOp module;
  const llvm::StringMap<DescriptorInfo> &descriptors;
  mlir::SymbolTableCollection symbols;
  llvm::StringMap<sim::SimVPINetIdentityDeclOp> netIdentities;
  llvm::DenseMap<uint64_t, sim::SimStorageDeclOp> storages;
  llvm::DenseMap<uint64_t, sim::SimNetDeclOp> nets;
};

/// Retain an exact expression occurrence in an existing owner's relation slot.
/// Planning is atomic: unsupported syntax returns no endpoint and emits no
/// partial inventory. Declaration leaves keep their canonical identities.
class VPIExpressionMaterializer {
public:
  VPIExpressionMaterializer(sim::SimDesignOp design,
                            const llvm::StringMap<DescriptorInfo> &descriptors,
                            mlir::OpBuilder &builder);
  mlir::FailureOr<std::optional<VPIExpressionEndpoint>>
  resolve(mlir::Operation *expression, sim::VPIObjectRefAttr owner,
          uint32_t ownerKind, uint64_t scope, uint32_t selector,
          sim::VPIRelationMode mode = sim::VPIRelationMode::Handle,
          uint64_t ordinal = 0);

  /// Validate every expression before emitting an iterated relation group.
  /// Unsupported labels leave the entire group unavailable, without gaps.
  mlir::FailureOr<std::optional<mlir::SmallVector<VPIExpressionEndpoint>>>
  resolveGroup(mlir::ArrayRef<mlir::Operation *> expressions,
               sim::VPIObjectRefAttr owner, uint32_t ownerKind, uint64_t scope,
               uint32_t selector);

private:
  mlir::FailureOr<std::optional<VPIExpressionEndpoint>>
  resolveImpl(mlir::Operation *expression, sim::VPIObjectRefAttr owner,
              uint32_t ownerKind, uint64_t scope, uint32_t selector,
              sim::VPIRelationMode mode, uint64_t ordinal, bool materialize);
  sim::SimDesignOp design;
  VPIExpressionResolver declarations;
  mlir::OpBuilder &builder;
  uint64_t nextID = 0;
  /// Source declarations referenced by expression leaves; the source tree is
  /// not modified while relations are materialized.
  mlir::SymbolTableCollection sourceSymbols;
  /// Symbol names in the design, including the expressions created so far.
  llvm::StringSet<> designSymbols;
};

/// Materialize exact direct declaration operands after statement and local
/// inventories exist, before source expressions are lowered or optimized.
mlir::LogicalResult materializeProceduralExpressionRelations(
    sim::SimDesignOp design, const PreparedUnits &units,
    const llvm::StringMap<DescriptorInfo> &descriptors,
    mlir::OpBuilder &builder);
/// The descriptor path that names the delayed copy of the timing-check signal at
/// `sourcePath`.
std::string getExplicitDelayedSignalPath(llvm::StringRef sourcePath);

/// IEEE 1800-2023 31.9.1: an explicit delayed_reference or delayed_data of a
/// negative timing check carries the delayed copy of its signal. Add a
/// continuous assignment of that copy to each one, and report the signals whose
/// delayed copies need a name.
mlir::LogicalResult
synthesizeExplicitDelayedDrivers(semantic::SVRootSymbolOp root,
                                 mlir::Builder &builder,
                                 llvm::StringSet<> &delayedSources);

/// IEEE 1800-2023 17.3: give the assertions of a procedural checker instance
/// the clock of their instantiation, ahead of resolveInferredAssertionQueries.
void bindProceduralCheckerClocks(semantic::SVRootSymbolOp root,
                                 mlir::Builder &builder);

/// IEEE 1800-2023 17.3: the static assertions of a procedural checker instance
/// are procedural assertions at its instantiation. Its variables and procedures
/// stay where they are, as they exist at every time step. Runs after
/// synthesizeFreeCheckerVariables, whose assume sets exist at every step too.
void synthesizeProceduralCheckers(semantic::SVRootSymbolOp root,
                                  llvm::StringMap<mlir::Operation *> &symbols,
                                  mlir::Builder &builder);

/// IEEE 1800-2023 17.7.2: give each free variable of a static checker its
/// initial random value, and for each assume set clock event add a process that
/// solves the active variables before the Observed region.
mlir::LogicalResult
synthesizeFreeCheckerVariables(semantic::SVRootSymbolOp root,
                               mlir::Builder &builder);

/// IEEE 1800-2023 16.10, F.6.1: local variables flow out of `T(V).triggered`
/// when it is a maximal Boolean. For a T of fixed length that assigns each
/// output once from design state, what flows out on an end point is `$past` of
/// that state, so `T(V).triggered` becomes `(T.triggered, V = $past(expression,
/// k))` over a T without local variables. Any other form is left to be
/// rejected.
void rewriteTriggeredLocalOutputs(semantic::SVRootSymbolOp root,
                                  mlir::Builder &builder);

/// IEEE 1800-2023 16.13.5, F.6.1: `@(c)(T.matched)` is true at the first tick of
/// c after an end point of T. For each use add a process recording the end
/// points of T and one recording the ticks of c, numbered by `trackers`, and drop
/// the operand so that the use only reads those records.
mlir::LogicalResult synthesizeMatchedTrackers(semantic::SVRootSymbolOp root,
                                              mlir::Builder &builder,
                                              unsigned &trackers);

/// IEEE 1800-2023 16.14.7: replace each $inferred_clock and $inferred_disable
/// reached through a concurrent assertion's property with the event from clock
/// flow to that point, or the scope's default disable condition or 1'b0.
mlir::LogicalResult
resolveInferredAssertionQueries(semantic::SVRootSymbolOp root,
                                mlir::Builder &builder);

/// IEEE 1800-2023 13.5.3: a default argument is evaluated in the scope of the
/// subroutine's declaration. A call through a virtual interface selects that
/// scope at run time, so replace each read of an interface member in such a
/// default with a member access through the call's receiver.
mlir::LogicalResult rebindVirtualInterfaceCallDefaults(
    semantic::SVRootSymbolOp root,
    const llvm::StringMap<mlir::Operation *> &symbols, mlir::Builder &builder);

} // namespace talos::simlowering
#endif
