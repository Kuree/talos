//===- SimulationSynchronousTasks.cpp - Ordinary native task bodies -----===//

#include "talos/Analysis/NativeMethodEligibilityAnalysis.h"
#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringMap.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_PREPARESYNCHRONOUSNATIVETASKSPASS
#include "talos/Conversion/Passes.h.inc"

namespace {
LogicalResult prepareTasks(sim::SimDesignOp design) {
  llvm::StringMap<sim::SimFuncOp> functions;
  DenseMap<uint64_t, SmallVector<sim::SimFuncOp>> families;
  SmallVector<sim::SimClassMethodDeclOp> methods;
  for (auto method : design.getOps<sim::SimClassMethodDeclOp>())
    if (method.getIsTask() && method.getImplementation())
      methods.push_back(method);
  if (methods.empty())
    return success();
  for (auto function : design.getOps<sim::SimFuncOp>())
    functions.try_emplace(function.getSymName(), function);
  SmallVector<sim::SimFuncOp> pending;
  for (auto method : methods) {
    auto body = functions.lookup(*method.getImplementation());
    if (!body)
      continue;
    if (method.getIsVirtual())
      families[method.getSignatureId().value_or(0)].push_back(body);
    if (runtime::has<runtime::BytecodeSynchronousTask>(body) &&
        !native::get<native::SynchronousTaskBody>(body))
      pending.push_back(body);
  }
  if (pending.empty())
    return success();

  analysis::NativeMethodEligibilityAnalysis eligibility(design);
  llvm::SetVector<Operation *> selected;
  DenseSet<uint64_t> expanded;
  while (!pending.empty()) {
    auto body = pending.pop_back_val();
    if (!body || body.getEntryKind() != sim::EntryKind::Task ||
        !eligibility.canInvoke(body) || !selected.insert(body))
      continue;
    body.walk([&](Operation *operation) {
      if (auto call = dyn_cast<sim::SimTaskCallOp>(operation))
        pending.push_back(functions.lookup(call.getCallee()));
      else if (auto call = dyn_cast<sim::SimClassVirtualTaskCallOp>(operation))
        if (expanded.insert(call.getSignatureId()).second)
          llvm::append_range(pending, families[call.getSignatureId()]);
    });
  }
  if (selected.empty())
    return success();

  // IEEE 1800-2023 8.6/13.3: these remain automatic task invocations.
  // Function entry kind describes the compiler's ordinary native calling
  // convention, not a source-language task-to-function transformation.
  // Keep every original activation untouched for bytecode and observation.
  DenseMap<uint64_t, uint64_t> scopes;
  uint64_t nextID = 1;
  for (auto unit : design.getOps<sim::SimCodeUnitDeclOp>()) {
    if (unit.getId() == UINT64_MAX)
      return unit.emitError("no code-unit ID available for native task body");
    nextID = std::max(nextID, unit.getId() + 1);
    scopes[unit.getId()] = unit.getScopeId();
  }
  SymbolTable symbols(design);
  DenseMap<Operation *, sim::SimFuncOp> bodies;
  OpBuilder builder(design.getContext());
  for (Operation *operation : selected) {
    auto original = cast<sim::SimFuncOp>(operation);
    if (!nextID)
      return original.emitError("native task code-unit ID overflow");
    auto body = cast<sim::SimFuncOp>(original->clone());
    body.setSymName((original.getSymName() + ".__talos_synchronous").str());
    body.setEntryKind(sim::EntryKind::Function);
    body.setCodeUnitIdAttr(builder.getI64IntegerAttr(nextID));
    runtime::remove<runtime::BytecodeFunction>(body);
    runtime::remove<runtime::BytecodeNativeMethod>(body);
    runtime::remove<runtime::BytecodeSynchronousTask>(body);
    runtime::remove<runtime::BytecodeScratchSize>(body);
    runtime::remove<runtime::BytecodeScratchAlignment>(body);
    runtime::remove<runtime::BytecodeTwoStateLogicRegisters>(body);
    body->removeAttr("simulation.class_method");
    symbols.insert(body);
    builder.setInsertionPointToEnd(&design.getBody().front());
    sim::SimCodeUnitDeclOp::create(
        builder, original.getLoc(), nextID++,
        scopes.lookup(original.getCodeUnitId().value_or(0)),
        sim::EntryKind::Function, builder.getStringAttr(body.getSymName()),
        builder.getStringAttr("synchronous native task"),
        builder.getUnitAttr());
    bodies[original] = body;
    native::set<native::SynchronousTaskBody>(original,
                                             FlatSymbolRefAttr::get(body));
  }
  for (auto method : methods)
    if (auto body =
            bodies.lookup(functions.lookup(*method.getImplementation())))
      native::set<native::SynchronousTaskBody>(method,
                                               FlatSymbolRefAttr::get(body));

  for (auto [original, body] : bodies) {
    SmallVector<Operation *> calls;
    body.walk([&](Operation *operation) {
      if (isa<sim::SimTaskCallOp, sim::SimClassVirtualTaskCallOp>(operation))
        calls.push_back(operation);
    });
    for (Operation *operation : calls) {
      builder.setInsertionPoint(operation);
      if (auto call = dyn_cast<sim::SimTaskCallOp>(operation)) {
        auto target = bodies.lookup(functions.lookup(call.getCallee()));
        if (!target)
          return call.emitError(
              "synchronous task closure lost a direct target");
        sim::SimCallOp::create(builder, call.getLoc(), TypeRange{},
                               FlatSymbolRefAttr::get(target),
                               call.getArguments(), ArrayAttr{}, ArrayAttr{});
        cf::BranchOp::create(builder, call.getLoc(), call.getContinuation(),
                             call.getContinuationOperands());
      } else {
        auto virtualCall = cast<sim::SimClassVirtualTaskCallOp>(operation);
        schedule::NativeSynchronousClassCallOp::create(
            builder, virtualCall.getLoc(), virtualCall.getReceiver(),
            virtualCall.getMethodAttr(), virtualCall.getSlotAttr(),
            virtualCall.getSignatureIdAttr(), virtualCall.getArguments());
        cf::BranchOp::create(builder, virtualCall.getLoc(),
                             virtualCall.getContinuation(),
                             virtualCall.getContinuationOperands());
      }
      operation->erase();
    }
  }
  return success();
}

class PrepareSynchronousNativeTasksPass final
    : public impl::PrepareSynchronousNativeTasksPassBase<
          PrepareSynchronousNativeTasksPass> {
  void runOnOperation() override {
    auto module = getOperation();
    // A VPI client can inspect the frame and scope of a running task (IEEE
    // 1800-2023 37.12, 37.43); a native copy has neither.
    runtime::ExecutionFlags flags = runtime::getExecutionFlags(module);
    if (runtime::bitEnumContainsAny(flags,
                                    runtime::ExecutionFlags::RequireBytecode |
                                        runtime::ExecutionFlags::VPIRead |
                                        runtime::ExecutionFlags::VPIWrite))
      return;
    for (auto design : module.getOps<sim::SimDesignOp>())
      if (failed(prepareTasks(design)))
        return signalPassFailure();
  }
};
} // namespace
} // namespace talos
