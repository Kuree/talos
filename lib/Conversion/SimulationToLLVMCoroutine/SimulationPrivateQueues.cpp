//===- SimulationPrivateQueues.cpp - Native access to owned queues -------===//

#include "SimulationPrivateQueues.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "talos/Analysis/ActivationPhaseAnalysis.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Analysis/SimulationEffectAnalysis.h"
#include "talos/Dialect/DPI/DPIDialect.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/ContainerLayout.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/LLVMContext.h"
#include <functional>

using namespace mlir;
namespace talos::detail {

// Only generate field offsets when the compiler's C layout also describes
// the target's ordinary pointers, uint32_t and uint64_t.
bool hasNativeQueueLayout(ModuleOp module) {
  bool queueLayout = false;
  if (auto layout = module->getAttrOfType<StringAttr>("llvm.data_layout")) {
    llvm::DataLayout target(layout.getValue());
    llvm::LLVMContext context;
    queueLayout =
        sizeof(void *) == 8 && target.getPointerSize() == sizeof(void *) &&
        target.getPointerABIAlignment(0).value() == alignof(void *) &&
        target.getABITypeAlign(llvm::Type::getInt64Ty(context)).value() ==
            alignof(uint64_t) &&
        target.getABITypeAlign(llvm::Type::getInt32Ty(context)).value() ==
            alignof(uint32_t);
  }
  return queueLayout;
}

bool isPlainUnboundedQueue(Type type) {
  auto q = dyn_cast<sim::QueueType>(type);
  if (!q || q.getBound() || !analysis::isPlainValueType(q.getElementType()))
    return false;
  return sim::getPackedWidth(q.getElementType()).value_or(0) != 0;
}

unsigned PrivateQueueUses::apply() const {
  for (Operation *load : propertyLoads)
    native::mark<native::PrivateClassField>(load);
  for (Operation *access : accesses)
    native::mark<native::PrivateQueue>(access);
  return accesses.size();
}

// Each actual handle must originate in this property or in a fresh typed
// allocation. A queue escaping to a ref, watcher, other property, foreign
// call or another process keeps its ordinary managed accesses (7.10.3,
// 8.12, 13.5.2). Trace both directions of a CFG join: a local incoming
// value can share the join with an externally supplied queue.
PrivateQueueUses analyzePrivateQueue(ArrayRef<Value> references,
                                     bool staticSlot) {
  DenseSet<Value> fields(references.begin(), references.end());
  llvm::SetVector<Value> handles;
  SmallVector<Operation *> loads;
  for (Value field : references)
    for (Operation *use : field.getUsers()) {
      if (auto load = dyn_cast<sim::SimManagedLoadOp>(use)) {
        loads.push_back(load);
        handles.insert(load.getResult());
      } else if (auto store = dyn_cast<sim::SimManagedStoreOp>(use)) {
        handles.insert(store.getValue());
      } else if (auto load = dyn_cast<sim::SimRefLoadOp>(use)) {
        handles.insert(load.getResult());
      } else if (auto store = dyn_cast<sim::SimRefStoreOp>(use)) {
        handles.insert(store.getValue());
      } else if (!staticSlot)
        return {};
    }
  llvm::SetVector<Operation *> accesses;
  auto plainAllocation = [](sim::SimContainerCreateOp create) {
    if (!create || create.getContainerKind() != sim::ContainerKind::Queue ||
        !create.getTraceOffsets().empty())
      return false;
    auto queue = dyn_cast<sim::QueueType>(create.getType());
    if (!queue || queue.getBound())
      return false;
    Type element = queue.getElementType();
    auto width = sim::getPackedWidth(element);
    return width && *width &&
           create.getValueSize() == (uint64_t(*width) + 7) / 8 &&
           bool(uint32_t(create.getElementFlags()) &
                TALOS_RT_ELEMENT_FOUR_STATE) ==
               sim::containsFourStateLeaf(element) &&
           (create.getElementKind() == sim::ElementKind::Bits ||
            create.getElementKind() == sim::ElementKind::Logic);
  };
  bool allocated = false;
  for (unsigned i = 0; i != handles.size(); ++i) {
    Value handle = handles[i];
    if (auto arg = dyn_cast<BlockArgument>(handle)) {
      Block *block = arg.getOwner();
      if (block->hasNoPredecessors())
        return {};
      for (Block *pred : block->getPredecessors()) {
        auto branch = dyn_cast<BranchOpInterface>(pred->getTerminator());
        if (!branch ||
            !isa<cf::BranchOp, cf::CondBranchOp>(pred->getTerminator()))
          return {};
        for (unsigned n = 0; n < pred->getNumSuccessors(); ++n) {
          if (pred->getSuccessor(n) != block)
            continue;
          auto operands = branch.getSuccessorOperands(n);
          if (arg.getArgNumber() >= operands.size() ||
              !operands[arg.getArgNumber()])
            return {};
          handles.insert(operands[arg.getArgNumber()]);
        }
      }
    } else if (auto load = handle.getDefiningOp<sim::SimRefLoadOp>()) {
      if (!staticSlot || !fields.contains(load.getReference()))
        return {};
    } else if (auto load = handle.getDefiningOp<sim::SimManagedLoadOp>()) {
      if (!fields.contains(load.getReference()))
        return {};
    } else if (auto create =
                   handle.getDefiningOp<sim::SimContainerCreateOp>()) {
      if (!plainAllocation(create))
        return {};
      allocated = true;
    } else if (auto clone = handle.getDefiningOp<sim::SimContainerCloneOp>()) {
      // A queue assignment copies the elements and gives the new queue its
      // own backing storage (7.10.3). The input itself may have other
      // users. Keep descriptor-dispatched mailbox identities out of this
      // proof, even though the runtime implements them with a queue.
      Value input = clone.getInput();
      if (plainAllocation(input.getDefiningOp<sim::SimContainerCreateOp>()))
        allocated = true;
      else if (!input.getDefiningOp<sim::SimManagedNullOp>())
        return {};
    } else if (handle.getDefiningOp<sim::SimManagedNullOp>()) {
      continue;
    } else
      return {};
    for (OpOperand &use : handle.getUses()) {
      Operation *op = use.getOwner();
      if (isa<cf::BranchOp, cf::CondBranchOp>(op)) {
        auto arg = cast<BranchOpInterface>(op).getSuccessorBlockArgument(
            use.getOperandNumber());
        if (!arg)
          return {};
        handles.insert(*arg);
      } else if (auto store = dyn_cast<sim::SimManagedStoreOp>(op)) {
        if (store.getValue() != handle ||
            !fields.contains(store.getReference()))
          return {};
      } else if (auto store = dyn_cast<sim::SimRefStoreOp>(op)) {
        if (!staticSlot || store.getValue() != handle ||
            !fields.contains(store.getReference()))
          return {};
      } else if (isa<sim::SimManagedIsNullOp, sim::SimContainerCloneOp>(op)) {
        continue;
      } else if (use.getOperandNumber() == 0 &&
                 isa<sim::SimContainerSizeOp, sim::SimContainerReadOp,
                     sim::SimQueuePopOp, sim::SimQueuePushBackOp>(op)) {
        accesses.insert(op);
      } else if (use.getOperandNumber() != 0 ||
                 !isa<sim::SimQueueDeleteOp, sim::SimQueueInsertOp,
                      sim::SimContainerDeleteOp, sim::SimContainerWriteOp>(op))
        return {};
    }
  }
  if (!allocated || accesses.empty())
    return {};
  return {std::move(loads), accesses.takeVector()};
}

// A named queue may use the same representation when all its references
// are bounded and all live accesses belong to one logical process. Follow
// calls synchronously, including a task that suspends and later resumes in
// its caller. A second process, watch, unbound access or external observer
// leaves the canonical managed operation in place (9.2, 9.3, 13.5).
unsigned specializeSingleProcessQueues(sim::SimDesignOp design) {
  auto graph = design.getComputeGraphAttr();
  if (!graph || graph.getVpi() != schedule::ComputeVPIMode::Off)
    return 0;
  struct Slot {
    Type type;
    Operation *owner = nullptr;
    bool admitted = true;
    llvm::SetVector<Value> references;
  };
  DenseMap<uint64_t, Slot> slots;
  DenseSet<Type> queueTypes;
  for (auto decl : design.getOps<sim::SimStorageDeclOp>()) {
    if (decl.getLifetime() != sim::Lifetime::Design)
      continue;
    Type type = decl.getType();
    if (isPlainUnboundedQueue(type)) {
      slots[decl.getId()].type = type;
      queueTypes.insert(type);
    }
  }
  auto module = design->getParentOfType<ModuleOp>();
  if (slots.empty() ||
      runtime::bitEnumContainsAny(runtime::getExecutionFlags(module),
                                  runtime::ExecutionFlags::DPIExports))
    return 0;
  SymbolTable symbols(design);
  // The graph supplies the logical owner; its effects are aggregated by
  // block. Bind the individual source accesses as well, so an opaque read
  // or write cannot reach a named queue through a different address family.
  auto opaque = [&](Operation *op) {
    if (isa<sim::SimDumpVarsOp, sim::SimDumpAllOp, sim::SimDumpControlOp,
            sim::SimDumpFlushOp, sim::SimDumpPortsOp,
            sim::SimDumpPortsControlOp, sim::SimDPICallOp, sim::SimOverrideOp,
            sim::SimReleaseOverrideOp, sim::SimDynamicOverrideOp,
            sim::SimSupplyControlOp, sim::SimPowerCancelNBAOp,
            sim::SimPowerNBAOp, sim::SimPowerNBAViewOp>(op))
      return true;
    if (!op->getParentOfType<sim::SimFuncOp>())
      return false;
    auto effects = dyn_cast<MemoryEffectOpInterface>(op);
    if (!effects)
      return !isMemoryEffectFree(op) &&
             !op->hasTrait<OpTrait::HasRecursiveMemoryEffects>();
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    bool canonical = llvm::any_of(instances, [](const auto &effect) {
      return isa<sim::StorageResource>(effect.getResource()) &&
             isa<MemoryEffects::Read, MemoryEffects::Write>(effect.getEffect());
    });
    // A bind only captures its operands. A sampled read takes its explicit
    // reference's Preponed value (1800-2023 16.5.1). The event-pending query
    // reads an already latched process event, including retention (1801 9.7.3).
    if (!canonical ||
        isa<sim::SimRefLoadOp, sim::SimRefStoreOp, sim::SimRefCopyOp,
            sim::SimNBAEnqueueOp, sim::SimRefAllocOp, sim::SimDisplayOp,
            sim::SimObserverBindOp, sim::SimSpawnOp, sim::SimSampledReadOp,
            sim::SimProcessEventPendingOp>(op))
      return false;
    sim::SimFuncOp body;
    if (auto call = dyn_cast<sim::SimCallOp>(op))
      body = symbols.lookup<sim::SimFuncOp>(call.getCallee());
    else if (auto call = dyn_cast<sim::SimTaskCallOp>(op))
      body = symbols.lookup<sim::SimFuncOp>(call.getCallee());
    return !body || body.isExternal();
  };
  if (design
          .walk([&](Operation *op) {
            if (!opaque(op))
              return WalkResult::advance();
            if (native::has<native::DebugTiming>(module))
              llvm::errs() << "talos queue ownership boundary: "
                           << op->getName() << '\n';
            return WalkResult::interrupt();
          })
          .wasInterrupted())
    return 0;
  auto uses = analysis::getSymbolUsesConcurrently(&design.getBody());
  if (!uses)
    return 0;
  DenseMap<StringAttr, SmallVector<Operation *>> users;
  for (const auto &use : *uses)
    users[use.getSymbolRef().getRootReference()].push_back(use.getUser());
  DenseMap<Operation *, Operation *> owners;
  std::function<Operation *(sim::SimFuncOp)> ownerOf =
      [&](sim::SimFuncOp fn) -> Operation * {
    if (!fn || !fn.isPrivate() || fn.isExternal() ||
        dpi::has<dpi::Export>(fn) || sim::has<sim::metadata::ClassMethod>(fn))
      return nullptr;
    if (auto found = owners.find(fn); found != owners.end())
      return found->second;
    owners[fn] = nullptr;
    auto sites = users.find(fn.getSymNameAttr());
    if (sites == users.end() || sites->second.empty())
      return nullptr;
    Operation *owner = nullptr;
    for (Operation *site : sites->second) {
      unsigned references = 0;
      for (NamedAttribute attr : site->getAttrs())
        attr.getValue().walk([&](SymbolRefAttr reference) {
          references += reference.getRootReference() == fn.getSymNameAttr();
        });
      if (references != 1)
        return nullptr;
      auto parent = site->getParentOfType<sim::SimFuncOp>();
      Operation *next = nullptr;
      if (!parent)
        return nullptr;
      if (auto spawn = dyn_cast<sim::SimSpawnOp>(site)) {
        if (sites->second.size() != 1 || spawn.getCallee() != fn.getSymName() ||
            parent.getEntryKind() != sim::EntryKind::RootInitializer ||
            site->getBlock() != &parent.getBody().front())
          return nullptr;
        next = fn;
      } else if (auto call = dyn_cast<sim::SimCallOp>(site)) {
        if (call.getCallee() != fn.getSymName() ||
            fn.getEntryKind() != sim::EntryKind::Function)
          return nullptr;
        next = ownerOf(parent);
      } else if (auto call = dyn_cast<sim::SimTaskCallOp>(site)) {
        if (call.getCallee() != fn.getSymName() ||
            fn.getEntryKind() != sim::EntryKind::Task)
          return nullptr;
        next = ownerOf(parent);
      }
      if (!next || (owner && next != owner))
        return nullptr;
      owner = next;
    }
    return owners[fn] = owner;
  };
  analysis::HandleDataflowAnalysis provenance(design);
  analysis::ActivationPhaseAnalysis phases(design, provenance);
  if (!phases.isValid())
    return 0;
  for (Attribute attr : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attr);
    if (!fragment)
      continue;
    StringAttr name = fragment.getFunction().getAttr();
    auto fn = symbols.lookup<sim::SimFuncOp>(name);
    if (!fn || fn.getEntryKind() == sim::EntryKind::Function)
      continue;
    for (auto effect :
         fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getResource() == schedule::ComputeResourceKind::Unknown &&
          effect.getTarget() == schedule::ComputeTargetKind::Unknown &&
          (effect.getEffect() == schedule::ComputeEffectKind::Read ||
           effect.getEffect() == schedule::ComputeEffectKind::Write ||
           effect.getEffect() == schedule::ComputeEffectKind::NBA ||
           effect.getEffect() == schedule::ComputeEffectKind::Watch))
        return 0;
      if (effect.getResource() != schedule::ComputeResourceKind::Storage ||
          effect.getTarget() == schedule::ComputeTargetKind::Local)
        continue;
      auto roots = phases.getEffectRoots(name, effect);
      if (!roots)
        return 0;
      for (uint64_t id : *roots) {
        auto found = slots.find(id);
        if (found == slots.end())
          continue;
        Slot &slot = found->second;
        if (effect.getEffect() != schedule::ComputeEffectKind::Read &&
            effect.getEffect() != schedule::ComputeEffectKind::Write) {
          slot.admitted = false;
          continue;
        }
        if (fn.getEntryKind() == sim::EntryKind::RootInitializer)
          continue;
        Operation *owner = ownerOf(fn);
        if (!owner || (slot.owner && slot.owner != owner))
          slot.admitted = false;
        else
          slot.owner = owner;
      }
    }
  }
  DenseSet<Type> unbounded;
  auto queueReference = [](Value value) -> Type {
    auto ref = dyn_cast<sim::RefType>(value.getType());
    return ref && isa<sim::QueueType>(ref.getElementType())
               ? ref.getElementType()
               : Type{};
  };
  for (auto fn : design.getOps<sim::SimFuncOp>()) {
    if (fn.isExternal())
      continue;
    std::optional<analysis::HandleFacts> facts;
    fn.walk([&](Operation *op) {
      for (OpOperand &use : op->getOpOperands()) {
        Value reference = use.get();
        Type type = queueReference(reference);
        if (!type || !queueTypes.contains(type))
          continue;
        // Branches and explicit synchronous bindings only transport an
        // address. Its actual accesses are inventoried in the callee.
        if (auto branch = dyn_cast<BranchOpInterface>(op))
          if (branch.getSuccessorBlockArgument(use.getOperandNumber()))
            continue;
        if (!facts)
          facts = provenance.derive(fn);
        auto target = facts->find(reference);
        if (target != facts->end() &&
            target->second.resource == schedule::ComputeResourceKind::Local)
          continue;
        if (target == facts->end() || !target->second.descriptor ||
            target->second.resource != schedule::ComputeResourceKind::Storage) {
          unbounded.insert(type);
          continue;
        }
        auto found = slots.find(*target->second.descriptor);
        if (found == slots.end())
          continue;
        auto &slot = found->second;
        if (slot.type != type || target->second.dynamic || target->second.low ||
            !target->second.width ||
            target->second.width != target->second.rootWidth) {
          slot.admitted = false;
          continue;
        }
        if (auto spawn = dyn_cast<sim::SimSpawnOp>(op)) {
          auto child = symbols.lookup<sim::SimFuncOp>(spawn.getCallee());
          unsigned arg = use.getOperandNumber();
          if (!child || child.isExternal() || arg >= child.getNumArguments()) {
            slot.admitted = false;
            continue;
          }
          auto binding = child.getArgAttrOfType<IntegerAttr>(
              arg, sim::metadata::DescriptorId::getNameStr());
          auto kind = child.getArgAttrOfType<sim::CaptureKindAttr>(
              arg, sim::metadata::CaptureKind::getNameStr());
          if (!binding || binding.getUInt() != *target->second.descriptor ||
              !kind || kind.getValue() != sim::CaptureKind::Storage)
            slot.admitted = false;
          continue;
        }
        Value address;
        if (auto load = dyn_cast<sim::SimRefLoadOp>(op))
          address = load.getReference();
        if (auto store = dyn_cast<sim::SimRefStoreOp>(op))
          address = store.getReference();
        if (address != reference) {
          slot.admitted = false;
          continue;
        }
        if (fn.getEntryKind() != sim::EntryKind::RootInitializer &&
            (!slot.owner || ownerOf(fn) != slot.owner)) {
          slot.admitted = false;
          continue;
        }
        slot.references.insert(reference);
      }
    });
  }
  unsigned count = 0;
  for (auto &[id, slot] : slots)
    if (slot.admitted && slot.owner && !unbounded.contains(slot.type))
      count += analyzePrivateQueue(slot.references.getArrayRef(),
                                   /*staticSlot=*/true)
                   .apply();
  return count;
}

// These functions operate on the original queue and its backing buffer. The
// compiler has proved an exclusive, typed receiver and a closed set of
// queue uses. Growth, null and invalid-index semantics stay with the public
// operation. A fast append changes neither backing identity nor capacity
// and reaches no managed safepoint (1800-2023 7.10.2-3).
LLVM::LLVMFuncOp getPrivateQueueAccess(ModuleOp module, Location loc,
                                       PrivateQueueAction action,
                                       uint64_t bytes, bool four) {
  using namespace ::talos::runtime_detail;
  bool sizeOnly = action == PrivateQueueAction::Size;
  bool append = action == PrivateQueueAction::Append;
  bool pop = action == PrivateQueueAction::Pop;
  StringRef operation;
  switch (action) {
  case PrivateQueueAction::Size:
    operation = "size";
    break;
  case PrivateQueueAction::Read:
    operation = "read";
    break;
  case PrivateQueueAction::Append:
    operation = "append";
    break;
  case PrivateQueueAction::Pop:
    operation = "pop";
    break;
  }
  std::string name = (Twine("__talos_private_queue_") + operation + "_" +
                      Twine(bytes) + (four ? "_four" : "_two"))
                         .str();
  std::string base = name;
  unsigned suffix = 0;
  while (Operation *symbol = module.lookupSymbol(name)) {
    if (auto fn = dyn_cast<LLVM::LLVMFuncOp>(symbol);
        fn && !fn.isExternal() && native::has<native::PrivateQueue>(fn))
      return fn;
    name = (Twine(base) + "." + Twine(++suffix)).str();
  }
  OpBuilder b = OpBuilder::atBlockEnd(module.getBody());
  auto ptr = LLVM::LLVMPointerType::get(module.getContext());
  Type i32 = b.getI32Type(), i64 = b.getI64Type();
  SmallVector<Type> types;
  if (sizeOnly)
    types = {ptr};
  else if (append)
    types = {ptr, ptr, i32, ptr, ptr};
  else
    types = {ptr, i64, ptr, i64, ptr, i64};
  auto fn = LLVM::LLVMFuncOp::create(
      b, loc, name, LLVM::LLVMFunctionType::get(sizeOnly ? i64 : i32, types),
      LLVM::Linkage::Internal);
  native::mark<native::PrivateQueue>(fn);
  Block *entry = fn.addEntryBlock(b);
  auto block = [&] {
    auto *result = new Block;
    fn.getBody().push_back(result);
    return result;
  };
  Block *access = block(), *slow = block();
  b.setInsertionPointToStart(entry);
  Value q = entry->getArgument(append ? 1 : 0);
  Value null = LLVM::ZeroOp::create(b, loc, ptr);
  Value valid = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::ne, q, null);
  if (append) {
    Value hasLane = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::ne,
                                         entry->getArgument(0), null);
    valid = arith::AndIOp::create(b, loc, valid, hasLane);
  }
  cf::CondBranchOp::create(b, loc, valid, access, ValueRange{}, slow,
                           ValueRange{});
  b.setInsertionPointToStart(slow);
  if (sizeOnly) {
    LLVM::ReturnOp::create(b, loc, llvmConstant(b, loc, i64, 0));
  } else {
    StringRef callee =
        getNativeRuntimeSymbol(NativeRuntimeEntry::ContainerReadChecked);
    if (append)
      callee = getNativeRuntimeSymbol(NativeRuntimeEntry::QueuePush);
    else if (pop)
      callee =
          getNativeRuntimeSymbol(NativeRuntimeEntry::QueueReadDeleteChecked);
    auto status = LLVM::CallOp::create(b, loc, TypeRange{i32}, callee,
                                       entry->getArguments());
    LLVM::ReturnOp::create(b, loc, status.getResult());
  }
  b.setInsertionPointToStart(access);
  auto load = [&](Type type, uint64_t offset) -> Value {
    return LLVM::LoadOp::create(b, loc, type, byteGEP(b, loc, q, offset), 8);
  };
  Value size = load(i64, offsetof(ContainerHeader, size));
  if (sizeOnly) {
    LLVM::ReturnOp::create(b, loc, size);
    return fn;
  }
  Value capacity = load(i64, offsetof(ContainerHeader, capacity));
  Value index = append ? size : entry->getArgument(1);
  Value fits = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ult, index,
                                     append ? capacity : size);
  Value last, front;
  if (pop) {
    last = arith::SubIOp::create(b, loc, size, llvmConstant(b, loc, i64, 1));
    front = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, index,
                                  llvmConstant(b, loc, i64, 0));
    Value back =
        arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, index, last);
    fits = arith::AndIOp::create(b, loc, fits,
                                 arith::OrIOp::create(b, loc, front, back));
  }
  Block *slot = block();
  cf::CondBranchOp::create(b, loc, fits, slot, ValueRange{}, slow,
                           ValueRange{});
  b.setInsertionPointToStart(slot);
  Value head = load(i64, offsetof(ContainerHeader, head));
  Value physical = arith::AndIOp::create(
      b, loc, arith::AddIOp::create(b, loc, head, index),
      arith::SubIOp::create(b, loc, capacity, llvmConstant(b, loc, i64, 1)));
  Value buffer = load(ptr, offsetof(ContainerHeader, buffer));
  Value inlineData =
      byteGEP(b, loc, q, offsetof(ContainerHeader, inlineElements));
  Value contents = arith::SelectOp::create(
      b, loc,
      LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, buffer, null),
      inlineData, byteGEP(b, loc, buffer, sizeof(BufferHeader)));
  Value offset = arith::MulIOp::create(
      b, loc, physical, llvmConstant(b, loc, i64, bytes * (four ? 2 : 1)));
  Value address = LLVM::GEPOp::create(b, loc, ptr, b.getI8Type(), contents,
                                      ValueRange{offset});
  Value value = entry->getArgument(append ? 3 : 2);
  Value unknown = entry->getArgument(4);
  // Each native source or output is a separately captured stack value.
  // This also handles packed records that span several host words.
  auto copy = [&](Value from, Value to) {
    if (bytes <= 8) {
      Type word = b.getIntegerType(bytes * 8);
      Value data = LLVM::LoadOp::create(b, loc, word, from, 1);
      LLVM::StoreOp::create(b, loc, data, to, 1);
    } else {
      LLVM::MemcpyOp::create(b, loc, to, from, llvmConstant(b, loc, i64, bytes),
                             false);
    }
  };
  copy(append ? value : address, append ? address : value);
  if (four) {
    Value plane = byteGEP(b, loc, address, bytes);
    copy(append ? unknown : plane, append ? plane : unknown);
  }
  if (append || pop) {
    Value one = llvmConstant(b, loc, i64, 1);
    Value newSize = last;
    if (append) {
      newSize = arith::AddIOp::create(b, loc, size, one);
    } else {
      LLVM::MemsetOp::create(
          b, loc, address, llvmConstant(b, loc, b.getI8Type(), 0),
          llvmConstant(b, loc, i64, bytes * (four ? 2 : 1)), false);
      Value advance = arith::AndIOp::create(
          b, loc, front,
          arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ugt, size, one));
      Value nextHead = arith::AndIOp::create(
          b, loc, arith::AddIOp::create(b, loc, head, one),
          arith::SubIOp::create(b, loc, capacity, one));
      LLVM::StoreOp::create(
          b, loc, arith::SelectOp::create(b, loc, advance, nextHead, head),
          byteGEP(b, loc, q, offsetof(ContainerHeader, head)), 8);
    }
    LLVM::StoreOp::create(b, loc, newSize,
                          byteGEP(b, loc, q, offsetof(ContainerHeader, size)),
                          8);
    Value epoch = load(i64, offsetof(ContainerHeader, epoch));
    LLVM::StoreOp::create(b, loc, arith::AddIOp::create(b, loc, epoch, one),
                          byteGEP(b, loc, q, offsetof(ContainerHeader, epoch)),
                          8);
  }
  LLVM::ReturnOp::create(b, loc, llvmConstant(b, loc, i32, TALOS_RT_OK));
  return fn;
}

} // namespace talos::detail
