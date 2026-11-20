//===- SimulationPrivateClassFields.cpp - Private instance properties -----===//

#include "SimulationPrivateQueues.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Analysis/SimulationEffectAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace talos::detail {
namespace {

struct ReceiverUses {
  SmallVector<Operation *> fields;
  SmallVector<Operation *> queues;
  SmallVector<std::pair<sim::SimCallOp, sim::SimFuncOp>> calls;
};

// IEEE 1800-2023 8.4, 8.12: assignments and argument passing can make more
// handles to the same instance. Follow only direct receiver calls. A saved
// handle, a property watch, a ref argument or a deferred write exposes the
// object or its property to another activation and ends this proof.
std::optional<ReceiverUses> inspectReceiver(Value receiver,
                                            SymbolTable &symbols) {
  ReceiverUses uses;
  for (OpOperand &use : receiver.getUses()) {
    if (auto field = dyn_cast<sim::SimClassFieldRefOp>(use.getOwner())) {
      if (isPlainUnboundedQueue(field.getType().getElementType())) {
        auto property =
            symbols.lookup<sim::SimClassFieldDeclOp>(field.getField());
        if (property && !property.getIsStatic() && !property.getIsWeak())
          uses.queues.push_back(field);
      }
      for (Operation *user : field.getResult().getUsers()) {
        if (auto store = dyn_cast<sim::SimManagedStoreOp>(user)) {
          if (store.getReference() != field.getResult())
            return std::nullopt;
        } else if (!isa<sim::SimManagedLoadOp>(user)) {
          return std::nullopt;
        }
        // Stores that carry a managed word retain heap validation. The
        // receiver itself remains a real rooted allocation.
        if (analysis::isPlainValueType(field.getType().getElementType()))
          uses.fields.push_back(user);
      }
      continue;
    }
    auto call = dyn_cast<sim::SimCallOp>(use.getOwner());
    if (!call || use.getOperandNumber() != 1 ||
        sim::has<sim::metadata::VpiResolutionNet>(call))
      return std::nullopt;
    auto callee = symbols.lookup<sim::SimFuncOp>(call.getCallee());
    if (!callee || callee.isExternal() || !callee.isPrivate() ||
        callee.getEntryKind() != sim::EntryKind::Function ||
        callee.getNumArguments() < 2 ||
        callee.getArgument(1).getType() != receiver.getType())
      return std::nullopt;
    uses.calls.emplace_back(call, callee);
  }
  return uses;
}

using QueueFields = llvm::MapVector<StringAttr, SmallVector<Value>>;
void addQueueFields(const ReceiverUses &uses, QueueFields &queues) {
  for (Operation *op : uses.queues) {
    auto field = cast<sim::SimClassFieldRefOp>(op);
    queues[field.getFieldAttr().getAttr()].push_back(field.getResult());
  }
}

void specializeDesign(sim::SimDesignOp design, unsigned &allocations,
                      unsigned &methods, unsigned &fields, bool queueLayout) {
  auto graph = design.getComputeGraphAttr();
  if (!graph || graph.getVpi() != schedule::ComputeVPIMode::Off)
    return;
  SmallVector<sim::SimClassAllocOp> objects;
  design.walk([&](sim::SimClassAllocOp object) { objects.push_back(object); });
  if (objects.empty())
    return;
  SymbolTable symbols(design);
  DenseMap<Operation *, std::optional<ReceiverUses>> summaries;
  SmallVector<ReceiverUses> roots;
  llvm::SetVector<Operation *> selected;
  auto examine = [&](sim::SimClassAllocOp alloc) {
    auto root = inspectReceiver(alloc.getResult(), symbols);
    if (!root)
      return;
    llvm::SetVector<Operation *> reachable;
    for (auto [call, callee] : root->calls)
      reachable.insert(callee);
    bool hasFields = !root->fields.empty();
    for (size_t i = 0; i < reachable.size(); ++i) {
      auto method = cast<sim::SimFuncOp>(reachable[i]);
      auto [it, inserted] = summaries.try_emplace(method);
      if (inserted &&
          !method
               .walk([](Operation *op) {
                 return sim::isSuspensionOp(op) ||
                                isa<sim::SimSpawnOp, schedule::NativeSpawnOp>(
                                    op)
                            ? WalkResult::interrupt()
                            : WalkResult::advance();
               })
               .wasInterrupted())
        it->second = inspectReceiver(method.getArgument(1), symbols);
      if (!it->second)
        return;
      hasFields |= !it->second->fields.empty();
      for (auto [call, callee] : it->second->calls)
        reachable.insert(callee);
    }
    if (!hasFields && queueLayout) {
      QueueFields candidates;
      addQueueFields(*root, candidates);
      for (Operation *op : reachable)
        addQueueFields(*summaries.find(op)->second, candidates);
      hasFields = llvm::any_of(candidates, [](const auto &candidate) {
        return !analyzePrivateQueue(candidate.second).accesses.empty();
      });
    }
    if (hasFields) {
      roots.push_back(std::move(*root));
      selected.insert(reachable.begin(), reachable.end());
    }
  };
  for (auto object : objects)
    examine(object);
  if (roots.empty())
    return;

  // Each physical helper has its own code unit. Keep the original methods,
  // descriptors and checked ABI for calls on other instances of this class.
  DenseMap<uint64_t, uint64_t> scopes;
  for (auto unit : design.getOps<sim::SimCodeUnitDeclOp>())
    scopes.try_emplace(unit.getId(), unit.getScopeId());
  uint64_t nextID = 1;
  OpBuilder builder = OpBuilder::atBlockEnd(&design.getBody().front());
  DenseMap<Operation *, sim::SimFuncOp> bodies;
  SmallVector<ReceiverUses> privateUses(std::move(roots));
  allocations += privateUses.size();
  for (Operation *op : selected) {
    const ReceiverUses &uses = *summaries.find(op)->second;
    if (uses.fields.empty() && uses.queues.empty() && uses.calls.empty())
      continue;
    auto source = cast<sim::SimFuncOp>(op);
    IRMapping mapping;
    auto body = cast<sim::SimFuncOp>(source->clone(mapping));
    body.setSymName((source.getSymName() + ".__talos_private_receiver").str());
    while (scopes.contains(nextID))
      ++nextID;
    body.setCodeUnitIdAttr(builder.getI64IntegerAttr(nextID));
    sim::remove<sim::metadata::ClassMethod>(body);
    runtime::remove<runtime::BytecodeFunction>(body);
    runtime::remove<runtime::BytecodeSynchronousTask>(body);
    runtime::remove<runtime::BytecodeNativeMethod>(body);
    runtime::remove<runtime::BytecodeScratchSize>(body);
    runtime::remove<runtime::BytecodeScratchAlignment>(body);
    runtime::remove<runtime::BytecodeTwoStateLogicRegisters>(body);
    symbols.insert(body);
    sim::SimCodeUnitDeclOp::create(
        builder, source.getLoc(), nextID++,
        scopes.lookup(source.getCodeUnitId().value_or(0)),
        sim::EntryKind::Function, body.getSymNameAttr(),
        builder.getStringAttr("native private receiver"),
        builder.getUnitAttr());
    bodies.try_emplace(source, body);
    ReceiverUses &cloned = privateUses.emplace_back();
    for (Operation *field : uses.fields)
      cloned.fields.push_back(mapping.lookup(field));
    for (Operation *field : uses.queues)
      cloned.queues.push_back(mapping.lookup(field));
    for (auto [call, callee] : uses.calls)
      cloned.calls.emplace_back(
          cast<sim::SimCallOp>(mapping.lookup(call.getOperation())), callee);
  }
  QueueFields queues;
  for (const ReceiverUses &uses : privateUses) {
    addQueueFields(uses, queues);
    for (Operation *field : uses.fields)
      native::mark<native::PrivateClassField>(field);
    for (auto [call, callee] : uses.calls)
      if (auto body = bodies.lookup(callee)) {
        // The frozen source descriptor names the original method. This
        // VPI-off native call now targets a private physical code unit.
        sim::remove<sim::metadata::VpiCallSite>(call);
        call.setCalleeAttr(FlatSymbolRefAttr::get(body));
      }
    fields += uses.fields.size();
  }
  if (queueLayout) {
    unsigned accesses = 0;
    for (auto &[name, refs] : queues)
      accesses += analyzePrivateQueue(refs).apply();
    if (accesses &&
        native::has<native::DebugTiming>(design->getParentOfType<ModuleOp>()))
      llvm::errs() << "talos private queues: accesses=" << accesses << '\n';
  }
  methods += bodies.size();
}
} // namespace

void specializePrivateClassFields(ModuleOp module) {
  module.walk([](Operation *op) {
    if (isa<sim::SimContainerSizeOp, sim::SimContainerReadOp,
            sim::SimQueuePopOp, sim::SimQueuePushBackOp, LLVM::LLVMFuncOp>(op))
      native::remove<native::PrivateQueue>(op);
    if (isa<sim::SimManagedLoadOp, sim::SimManagedStoreOp>(op))
      native::remove<native::PrivateClassField>(op);
  });
  if (!native::has<native::ClosedExecutable>(module) ||
      sim::has<sim::metadata::SnapshotPublications>(module) ||
      runtime::bitEnumContainsAny(runtime::getExecutionFlags(module),
                                  runtime::ExecutionFlags::CoverageSchema))
    return;
  bool queueLayout = hasNativeQueueLayout(module);
  unsigned allocations = 0, methods = 0, fields = 0, slots = 0;
  module.walk([&](sim::SimDesignOp design) {
    if (queueLayout)
      slots += specializeSingleProcessQueues(design);
    specializeDesign(design, allocations, methods, fields, queueLayout);
  });
  if (slots && native::has<native::DebugTiming>(module))
    llvm::errs() << "talos single-process queue accesses: " << slots << '\n';
  if (native::has<native::DebugTiming>(module) && allocations)
    llvm::errs() << "talos private class fields: allocations=" << allocations
                 << " methods=" << methods << " accesses=" << fields << '\n';
}
} // namespace talos::detail
