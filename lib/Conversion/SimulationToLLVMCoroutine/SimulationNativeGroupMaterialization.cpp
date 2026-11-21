//===- SimulationNativeGroupMaterialization.cpp - Native group bodies ----===//

#include "NativeStateAccess.h"
#include "NativeSymbolUses.h"
#include "SimulationAOTPlanning.h"
#include "SimulationEvalReadySet.h"
#include "SimulationNativeInlineCost.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/EvalRoles.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/Transforms/NativeTransforms.h"

#include "talos/Conversion/Passes.h"
#include "talos/Conversion/SimulationToLLVMCoroutine.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/Transforms/InlinerInterfaceImpl.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/InliningUtils.h"
#include "mlir/Transforms/Mem2Reg.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/GenericIteratedDominanceFrontier.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>
#include <map>

using namespace mlir;

namespace talos::detail {
namespace {

/// Promotes generated scalar slots to SSA. mlir::tryToPromoteMemorySlots
/// promotes one slot at a time and walks every operation of the region for
/// each, which on a fused group body costs its whole size per state word.
/// When every slot is an entry alloca used only by plain loads and stores of
/// its element type, this computes the same pruned merge points (live-in
/// blocks and iterated dominance frontiers), appends block arguments and
/// successor operands in slot order, and renames all slots in a single
/// dominator-tree walk, producing the IR mem2reg would. Other slots fall back
/// to mem2reg itself.
LogicalResult
promoteScalarSlots(ArrayRef<PromotableAllocationOpInterface> allocations,
                   OpBuilder &builder, const DataLayout &layout,
                   DominanceInfo &dominance) {
  SmallVector<LLVM::AllocaOp> slots;
  Region *region = nullptr;
  auto isPlain = [](auto access) {
    return !access.getVolatile_() &&
           access.getOrdering() == LLVM::AtomicOrdering::not_atomic;
  };
  bool direct = llvm::all_of(
      allocations, [&](PromotableAllocationOpInterface allocation) {
        auto alloca = dyn_cast<LLVM::AllocaOp>(allocation.getOperation());
        if (!alloca || !matchPattern(alloca.getArraySize(), m_One()) ||
            (region && alloca->getParentRegion() != region) ||
            alloca->getBlock() != &alloca->getParentRegion()->front())
          return false;
        region = alloca->getParentRegion();
        Type type = alloca.getElemType();
        for (OpOperand &use : alloca.getResult().getUses()) {
          Operation *user = use.getOwner();
          if (user->getParentRegion() != region)
            return false;
          if (auto load = dyn_cast<LLVM::LoadOp>(user)) {
            if (load.getType() != type || !isPlain(load))
              return false;
          } else if (auto store = dyn_cast<LLVM::StoreOp>(user)) {
            if (store.getAddr() != alloca.getResult() ||
                store.getValue() == alloca.getResult() ||
                store.getValue().getType() != type || !isPlain(store))
              return false;
          } else {
            return false;
          }
        }
        // mem2reg leaves an unused slot untouched.
        if (!alloca.getResult().use_empty())
          slots.push_back(alloca);
        return true;
      });
  if (!direct)
    return tryToPromoteMemorySlots(allocations, builder, layout, dominance);
  if (slots.empty())
    return failure();

  DenseMap<Value, unsigned> slotOf;
  for (auto [index, alloca] : llvm::enumerate(slots))
    slotOf.try_emplace(alloca.getResult(), index);
  // The slot an operation loads (true) or stores (false), if any.
  auto access = [&](Operation &op) -> std::optional<std::pair<unsigned, bool>> {
    Value address;
    bool load = isa<LLVM::LoadOp>(op);
    if (load)
      address = cast<LLVM::LoadOp>(op).getAddr();
    else if (auto store = dyn_cast<LLVM::StoreOp>(op))
      address = store.getAddr();
    else
      return std::nullopt;
    auto found = slotOf.find(address);
    if (found == slotOf.end())
      return std::nullopt;
    return std::make_pair(found->second, load);
  };

  // One pass finds, per slot, the blocks whose first access loads it (the
  // value is live-in there) and the blocks that store it.
  SmallVector<SmallVector<Block *>> upwardLoads(slots.size());
  SmallVector<SmallPtrSet<Block *, 16>> definitions(slots.size());
  DenseSet<std::pair<Block *, unsigned>> accessed;
  for (Block &block : *region)
    for (Operation &op : block)
      if (auto found = access(op)) {
        auto [slot, load] = *found;
        if (accessed.insert({&block, slot}).second && load)
          upwardLoads[slot].push_back(&block);
        if (!load)
          definitions[slot].insert(&block);
      }

  // Merge points exactly as MemorySlotPromotionAnalyzer computes them.
  DenseMap<Block *, SmallVector<unsigned>> mergeSlots;
  if (!region->hasOneBlock()) {
    auto &domTree = dominance.getDomTree(region);
    for (unsigned slot = 0; slot != slots.size(); ++slot) {
      SmallPtrSet<Block *, 16> liveIn;
      SmallVector<Block *> worklist(upwardLoads[slot]);
      while (!worklist.empty()) {
        Block *block = worklist.pop_back_val();
        if (!liveIn.insert(block).second)
          continue;
        for (Block *predecessor : block->getPredecessors())
          if (!definitions[slot].contains(predecessor))
            worklist.push_back(predecessor);
      }
      llvm::IDFCalculatorBase<Block, false> idf(domTree);
      idf.setLiveInBlocks(liveIn);
      idf.setDefiningBlocks(definitions[slot]);
      SmallVector<Block *> merges;
      idf.calculate(merges);
      for (Block *merge : merges)
        mergeSlots[merge].push_back(slot);
    }
  }

  // mem2reg creates each slot's default value at the start of the entry
  // block before promoting it, and erases it if nothing reads it.
  SmallVector<Value> defaults;
  for (LLVM::AllocaOp alloca : slots) {
    builder.setInsertionPointToStart(alloca->getBlock());
    MemorySlot slot{alloca.getResult(), alloca.getElemType()};
    defaults.push_back(
        cast<PromotableAllocationOpInterface>(alloca.getOperation())
            .getDefaultValue(slot, builder));
  }

  SmallVector<Operation *> accesses;
  auto renameBlock = [&](Block *block, SmallVectorImpl<Value> &reaching) {
    if (auto merges = mergeSlots.find(block); merges != mergeSlots.end())
      for (unsigned slot : merges->second)
        reaching[slot] =
            block->addArgument(slots[slot].getElemType(), slots[slot].getLoc());
    for (Operation &op : *block) {
      auto found = access(op);
      if (!found)
        continue;
      auto [slot, load] = *found;
      if (load)
        op.getResult(0).replaceAllUsesWith(reaching[slot]);
      else
        reaching[slot] = cast<LLVM::StoreOp>(op).getValue();
      accesses.push_back(&op);
    }
    if (auto terminator = dyn_cast<BranchOpInterface>(block->getTerminator()))
      for (BlockOperand &successor : terminator->getBlockOperands())
        if (auto merges = mergeSlots.find(successor.get());
            merges != mergeSlots.end())
          for (unsigned slot : merges->second)
            terminator.getSuccessorOperands(successor.getOperandNumber())
                .append(reaching[slot]);
  };
  if (region->hasOneBlock()) {
    SmallVector<Value> reaching(defaults);
    renameBlock(&region->front(), reaching);
  } else {
    struct Job {
      llvm::DomTreeNodeBase<Block> *node;
      SmallVector<Value> reaching;
    };
    SmallVector<Job> stack;
    stack.push_back(
        {dominance.getDomTree(region).getNode(&region->front()), defaults});
    while (!stack.empty()) {
      Job job = stack.pop_back_val();
      renameBlock(job.node->getBlock(), job.reaching);
      for (auto *child : job.node->children())
        stack.push_back({child, job.reaching});
    }
  }
  // Accesses in unreachable blocks lie outside every definition and read the
  // default value, as in mem2reg.
  DenseSet<Operation *> renamed(accesses.begin(), accesses.end());
  for (Block &block : *region)
    for (Operation &op : block)
      if (auto found = access(op); found && !renamed.contains(&op)) {
        if (found->second)
          op.getResult(0).replaceAllUsesWith(defaults[found->first]);
        accesses.push_back(&op);
      }
  for (Operation *op : accesses)
    op->erase();
  for (auto [alloca, initial] : llvm::zip_equal(slots, defaults)) {
    if (initial.use_empty())
      initial.getDefiningOp()->erase();
    alloca.erase();
  }
  return success();
}

using NativeByteFootprint = SmallVector<std::pair<uint64_t, uint64_t>, 2>;
struct NativeStateFootprint {
  bool exact = false;
  NativeByteFootprint value, unknown;
};

void normalizeNativeByteFootprint(NativeByteFootprint &ranges) {
  llvm::sort(ranges);
  NativeByteFootprint merged;
  for (auto range : ranges)
    if (!merged.empty() && range.first <= merged.back().second)
      merged.back().second = std::max(merged.back().second, range.second);
    else
      merged.push_back(range);
  ranges = std::move(merged);
}

// An outlined computation is not itself an observation boundary (LRM 4.3).
// Inventory its complete call closure without inlining it or changing the
// machine-IR growth budget. Unknown aliases and external calls remain cuts.
llvm::StringMap<NativeStateFootprint>
buildNativeStateFootprints(ModuleOp module,
                           const llvm::StringMap<Type> &globalTypes,
                           const llvm::StringSet<> &metadataOnly) {
  SmallVector<LLVM::LLVMFuncOp> functions;
  llvm::StringMap<unsigned> indices;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>())
    if (indices.try_emplace(function.getSymName(), functions.size()).second)
      functions.push_back(function);
  // A function's own accesses, and the functions it calls. Consumers only use
  // exact footprints, and exactness does not depend on traversal order: a
  // footprint is exact iff every access in the call closure has a static
  // state range and the closure is defined, direct and non-recursive.
  struct LocalFootprint {
    NativeStateFootprint accesses{true, {}, {}};
    SmallVector<StringRef> callees;
  };
  SmallVector<LocalFootprint> locals(functions.size());
  analysis::parallelForChunked(
      module.getContext(), functions.size(), [&](size_t index) {
        LLVM::LLVMFuncOp function = functions[index];
        if (function.isExternal() ||
            metadataOnly.contains(function.getSymName()))
          return;
        NativeStateFootprint &result = locals[index].accesses;
        auto memory = [&](const NativeAddress &access,
                          std::optional<uint64_t> bytes) {
          if (access.isLocal())
            return;
          if (!access.plane) {
            // Another global's bytes are no state; an address of unknown
            // origin may be.
            if (access.global.empty() || !globalTypes.contains(access.global))
              result.exact = false;
            return;
          }
          NativeByteFootprint &footprint =
              *access.plane == schedule::StatePlane::Value ? result.value
                                                           : result.unknown;
          if (!bytes) {
            result.exact = false;
            return;
          }
          auto offset = access.offset;
          auto array = dyn_cast<LLVM::LLVMArrayType>(globalTypes.lookup(
              schedule::getStatePlaneGlobalName(*access.plane)));
          DenseI64ArrayAttr interval = access.window;
          if (array && interval && interval.size() == 2 && interval[0] >= 0 &&
              interval[1] > interval[0]) {
            uint64_t begin = interval[0];
            uint64_t end =
                std::min(uint64_t(interval[1]), array.getNumElements());
            if (begin < end) {
              footprint.emplace_back(begin, end);
              return;
            }
          }
          if (!offset || !array || *offset > array.getNumElements() ||
              *bytes > array.getNumElements() - *offset) {
            result.exact = false;
            return;
          }
          if (*bytes)
            footprint.emplace_back(*offset, *offset + *bytes);
        };
        function.walk([&](Operation *operation) {
          if (!result.exact || operation == function.getOperation())
            return;
          if (auto call = dyn_cast<LLVM::CallOp>(operation)) {
            if (call.getCallee())
              locals[index].callees.push_back(*call.getCallee());
            else
              result.exact = false;
          } else if (auto access = getNativeMemoryAccess(operation)) {
            auto type = dyn_cast<IntegerType>(access->type);
            memory(*access, type && type.getWidth() % 8 == 0
                                ? std::optional<uint64_t>(type.getWidth() / 8)
                                : std::nullopt);
          } else if (isa<LLVM::MemcpyOp, LLVM::MemsetOp>(operation)) {
            Value length = isa<LLVM::MemcpyOp>(operation)
                               ? cast<LLVM::MemcpyOp>(operation).getLen()
                               : cast<LLVM::MemsetOp>(operation).getLen();
            APInt bytes;
            if (!matchPattern(length, m_ConstantInt(&bytes)) ||
                bytes.getActiveBits() > 64)
              result.exact = false;
            else if (auto copy = dyn_cast<LLVM::MemcpyOp>(operation)) {
              memory(describeNativeAddress(operation, copy.getDst()),
                     bytes.getZExtValue());
              memory(describeNativeAddress(operation, copy.getSrc()),
                     bytes.getZExtValue());
            } else
              memory(describeNativeAddress(
                         operation, cast<LLVM::MemsetOp>(operation).getDst()),
                     bytes.getZExtValue());
          } else if (!isa<LLVM::ReturnOp, LLVM::AllocaOp>(operation) &&
                     !isMemoryEffectFree(operation))
            result.exact = false;
        });
      });

  // Close over calls. A function reached again while its own closure is
  // still open is recursive, so it and every caller on the path are inexact.
  llvm::StringMap<NativeStateFootprint> results;
  enum class State : uint8_t { Unvisited, Open, Done };
  SmallVector<State> states(functions.size(), State::Unvisited);
  std::function<NativeStateFootprint(StringRef)> visit = [&](StringRef name) {
    if (metadataOnly.contains(name))
      return NativeStateFootprint{true, {}, {}};
    auto found = indices.find(name);
    if (found == indices.end())
      return NativeStateFootprint{};
    unsigned index = found->second;
    if (states[index] == State::Done)
      return results.find(name)->second;
    if (functions[index].isExternal() || states[index] == State::Open)
      return NativeStateFootprint{};
    states[index] = State::Open;
    NativeStateFootprint result = locals[index].accesses;
    for (StringRef callee : locals[index].callees) {
      NativeStateFootprint nested = visit(callee);
      result.exact &= nested.exact;
      llvm::append_range(result.value, nested.value);
      llvm::append_range(result.unknown, nested.unknown);
    }
    if (!result.exact)
      result = NativeStateFootprint{};
    normalizeNativeByteFootprint(result.value);
    normalizeNativeByteFootprint(result.unknown);
    states[index] = State::Done;
    results.try_emplace(name, result);
    return result;
  };
  for (auto function : functions)
    visit(function.getSymName());
  return results;
}

/// Forward exact physical state ranges between certified actors. Canonical
/// state is acquired at entry, including its X/Z plane; no initialization or
/// value-domain proof is inferred here. Original transition computations and
/// invalidation hooks still execute at each logical store. Only its physical
/// publication is deferred until the next boundary (LRM 4.3, 4.6, 4.10).
/// IEEE 1800-2023 4.3 permits this representation only with the same visible
/// updates; 4.6(a) retains source statement order and 4.9.3 makes subsequent
/// blocking reads see the updated current value. Opaque calls materialize
/// both planes so VPI reads/writes (38.15, 38.34) observe coherent state.
LogicalResult
promoteGroupState(LLVM::LLVMFuncOp function,
                  const llvm::StringMap<Type> &globalTypes,
                  schedule::StatePlane plane, uint64_t &budget,
                  const llvm::StringSet<> &metadataOnly,
                  const llvm::StringMap<NativeStateFootprint> &callFootprints) {
  auto array = dyn_cast_or_null<LLVM::LLVMArrayType>(
      globalTypes.lookup(schedule::getStatePlaneGlobalName(plane)));
  if (!array || !array.getElementType().isInteger(8))
    return success();
  struct Range {
    Type type;
    SmallVector<Operation *> operations;
    llvm::SmallDenseSet<uint32_t, 2> owners;
    bool read = false;
    bool written = false;
    unsigned stores = 0;
  };
  bool activation = schedule::has<schedule::Field::EvalRawCaptures>(function);
  std::map<std::pair<uint64_t, uint64_t>, Range> ranges;
  llvm::SetVector<Operation *> boundaries;
  using Footprint = SmallVector<std::pair<uint64_t, uint64_t>, 2>;
  DenseMap<Operation *, Footprint> boundaryFootprints;
  DenseMap<Operation *, uint64_t> operationOrder;
  uint64_t nextOperation = 0;
  auto accessFootprint = [&](const NativeAddress &access, uint64_t bytes,
                             Footprint &footprint) {
    if (access.isLocal())
      return true;
    // Other globals have no footprint in this plane; an address of unknown
    // origin may alias it.
    if (!access.plane)
      return !access.global.empty() && globalTypes.contains(access.global);
    if (*access.plane != plane)
      return true;
    auto offset = access.offset;
    if (!offset || *offset > array.getNumElements() ||
        bytes > array.getNumElements() - *offset)
      return false;
    if (bytes)
      footprint.emplace_back(*offset, *offset + bytes);
    return true;
  };
  bool supported = true;
  function.walk([&](Operation *operation) {
    operationOrder.try_emplace(operation, nextOperation++);
    if (operation == function.getOperation())
      return;
    if (auto call = dyn_cast<LLVM::CallOp>(operation)) {
      if (call.getCallee() && metadataOnly.contains(*call.getCallee()))
        return;
      if (call.getCallee())
        if (auto found = callFootprints.find(*call.getCallee());
            found != callFootprints.end() && found->second.exact) {
          auto &footprint = plane == schedule::StatePlane::Value
                                ? found->second.value
                                : found->second.unknown;
          if (!footprint.empty()) {
            boundaries.insert(operation);
            boundaryFootprints.try_emplace(operation, footprint);
          }
          return;
        }
      boundaries.insert(operation);
      return;
    }
    if (isa<LLVM::ReturnOp>(operation)) {
      boundaries.insert(operation);
      return;
    }
    if (isa<LLVM::InvokeOp, LLVM::InlineAsmOp>(operation))
      supported = false;
    std::optional<NativeMemoryAccess> access = getNativeMemoryAccess(operation);
    if (!access) {
      // Intrinsics and future memory operations must not silently bypass
      // publication. Unknown control effects cannot be resumed locally.
      // Local memory intrinsics cannot observe canonical state. Preserve
      // their original order, but do not flush unrelated state around them.
      if (isa<LLVM::MemsetOp, LLVM::MemcpyOp>(operation)) {
        Value length = isa<LLVM::MemsetOp>(operation)
                           ? cast<LLVM::MemsetOp>(operation).getLen()
                           : cast<LLVM::MemcpyOp>(operation).getLen();
        APInt bytes;
        Footprint footprint;
        bool exact = matchPattern(length, m_ConstantInt(&bytes)) &&
                     bytes.getActiveBits() <= 64;
        if (exact) {
          if (auto set = dyn_cast<LLVM::MemsetOp>(operation))
            exact = accessFootprint(describeNativeAddress(set, set.getDst()),
                                    bytes.getZExtValue(), footprint);
          else {
            auto copy = cast<LLVM::MemcpyOp>(operation);
            exact = accessFootprint(describeNativeAddress(copy, copy.getDst()),
                                    bytes.getZExtValue(), footprint) &&
                    accessFootprint(describeNativeAddress(copy, copy.getSrc()),
                                    bytes.getZExtValue(), footprint);
          }
        }
        if (!exact || !footprint.empty())
          boundaries.insert(operation);
        if (exact)
          boundaryFootprints.try_emplace(operation, std::move(footprint));
        return;
      }
      if (!isa<LLVM::AllocaOp>(operation) && !isMemoryEffectFree(operation)) {
        if (operation->getNumRegions() ||
            operation->hasTrait<OpTrait::IsTerminator>())
          supported = false;
        else
          boundaries.insert(operation);
      }
      return;
    }
    if (!access->plane) {
      // A returned pointer or an indirect context access may alias canonical
      // state. Local allocation addresses and other globals cannot.
      if (!access->isLocal() &&
          (access->global.empty() || !globalTypes.contains(access->global)))
        boundaries.insert(operation);
      return;
    }
    if (*access->plane != plane)
      return;
    IntegerAttr owner = access->owner;
    auto type = dyn_cast<IntegerType>(access->type);
    auto offset = access->offset;
    bool load = !access->isWrite(), store = access->isWrite();
    if ((!owner && !activation) || !access->plain || !type ||
        type.getWidth() % 8 || !offset) {
      boundaries.insert(operation);
      Footprint footprint;
      DenseI64ArrayAttr bytes = access->window;
      if (bytes && bytes.size() == 2 && bytes[0] >= 0 && bytes[1] > bytes[0]) {
        uint64_t begin = bytes[0];
        uint64_t end = std::min(uint64_t(bytes[1]), array.getNumElements());
        if (begin < end)
          boundaryFootprints.try_emplace(operation, Footprint{{begin, end}});
      } else if (type && type.getWidth() % 8 == 0 && offset &&
                 accessFootprint(*access, type.getWidth() / 8, footprint))
        boundaryFootprints.try_emplace(operation, std::move(footprint));
      return;
    }
    uint64_t width = type.getWidth() / 8;
    if (*offset >= array.getNumElements() ||
        width > array.getNumElements() - *offset) {
      supported = false;
      return;
    }
    Range &range = ranges[{*offset, width}];
    range.type = type;
    range.operations.push_back(operation);
    if (owner)
      range.owners.insert(owner.getUInt());
    range.read |= load;
    range.written |= store;
    range.stores += store;
  });
  // The plane's address must never escape into an opaque memory operation.
  // Calls are handled at boundaries, but storing the pointer or passing it
  // through control flow would hide later aliases from the access inventory.
  // Ptr-to-int arithmetic only observes the address (including the explicit
  // proof-publication offset), not the deferred payload. Any later int-to-ptr
  // memory access is an unknown alias and already forces a boundary above.
  SmallVector<Value> pending;
  llvm::DenseSet<Value> seen;
  function.walk([&](Operation *operation) {
    if (isa<schedule::NativeStateAddressOp,
            schedule::NativeStateWindowAddressOp>(operation) &&
        getStatePlaneRoot(operation->getResult(0)) == plane)
      pending.push_back(operation->getResult(0));
  });
  while (!pending.empty() && supported) {
    Value pointer = pending.pop_back_val();
    if (!seen.insert(pointer).second)
      continue;
    for (OpOperand &use : pointer.getUses()) {
      Operation *operation = use.getOwner();
      if (auto gep = dyn_cast<LLVM::GEPOp>(operation))
        pending.push_back(gep.getResult());
      else if (auto store = dyn_cast<LLVM::StoreOp>(operation))
        supported &= store.getAddr() == pointer;
      else
        supported &= isa<LLVM::LoadOp, LLVM::CallOp, LLVM::MemcpyOp,
                         LLVM::MemsetOp, LLVM::PtrToIntOp>(operation);
    }
  }
  if (!supported || ranges.empty())
    return success();
  // A connected physical window has one value, even when logical accesses
  // have different widths. Keep overlapping byte slices together and express
  // their loads/stores as exact integer extracts/inserts. This never unions
  // unrelated copy-connected roots or includes bytes outside the window.
  std::optional<bool> littleEndian;
  if (auto layout =
          function->getParentOfType<ModuleOp>()->getAttrOfType<StringAttr>(
              "llvm.data_layout")) {
    auto parsed = llvm::DataLayout::parse(layout.getValue());
    if (!parsed) {
      llvm::consumeError(parsed.takeError());
      return function.emitError("invalid native state data layout");
    }
    littleEndian = parsed->isLittleEndian();
  }
  struct Window {
    uint64_t offset, end;
    SmallVector<Range *> ranges;
    llvm::SmallDenseSet<uint32_t, 2> owners{};
    bool read = false, written = false;
    unsigned stores = 0;
    Block *scope = nullptr;
    Block *dominatedBy = nullptr;
    Operation *first = nullptr, *last = nullptr;
    uint64_t beginOrder = UINT64_MAX, endOrder = 0;
  };
  SmallVector<Window> windows;
  for (auto &[key, range] : ranges) {
    if (windows.empty() || key.first >= windows.back().end)
      windows.push_back({key.first, key.first + key.second, {}});
    Window &window = windows.back();
    window.end = std::max(window.end, key.first + key.second);
    window.ranges.push_back(&range);
    window.owners.insert(range.owners.begin(), range.owners.end());
    window.read |= range.read;
    window.written |= range.written;
    window.stores += range.stores;
  }
  DominanceInfo dominance(function);
  // Several state ranges commonly live in the same arm. Find its exits
  // once and bound the total CFG walk by the existing promotion budget.
  DenseMap<Block *, SmallVector<Block *, 2>> scopeExits;
  uint64_t scopeBudget = budget;
  for (Window &window : windows) {
    bool oneBlock = true;
    Block *root = nullptr;
    bool reachable = true;
    for (Range *range : window.ranges)
      for (Operation *operation : range->operations) {
        Block *block = operation->getBlock();
        reachable &= dominance.isReachableFromEntry(block);
        if (reachable)
          root =
              root ? dominance.findNearestCommonDominator(root, block) : block;
        if (!window.scope)
          window.scope = operation->getBlock();
        oneBlock &= window.scope == operation->getBlock();
        uint64_t order = operationOrder.lookup(operation);
        if (order < window.beginOrder) {
          window.beginOrder = order;
          window.first = operation;
        }
        if (!window.last || order > window.endOrder) {
          window.endOrder = order;
          window.last = operation;
        }
      }
    if (!oneBlock) {
      window.scope = nullptr;
      window.first = window.last = nullptr;
      // Acquire this window only on entry to the arm containing all its
      // accesses. Publish before any exit from that dominator subtree and
      // before a backedge re-enters its root. An observer in the arm still
      // gets the ordinary publish/reacquire pair (1800-2023 4.6, 4.9.3).
      if (!reachable || !root || root == &function.getBody().front() ||
          !window.read || !window.written)
        continue;
      if (!scopeExits.contains(root)) {
        if (!scopeBudget)
          continue;
        SmallVector<llvm::DomTreeNodeBase<Block> *> work{
            dominance.getDomTree(&function.getBody()).getNode(root)};
        SmallVector<Block *, 2> exits;
        while (!work.empty() && scopeBudget) {
          --scopeBudget;
          auto *node = work.pop_back_val();
          Block *block = node->getBlock();
          if (llvm::any_of(block->getSuccessors(), [&](Block *target) {
                return target == root || !dominance.dominates(root, target);
              }))
            exits.push_back(block);
          llvm::append_range(work, node->children());
        }
        if (!work.empty())
          continue;
        scopeExits.try_emplace(root, std::move(exits));
      }
      window.dominatedBy = root;
    }
  }
  auto intersects = [&](Operation *boundary, const Window &window) {
    if (window.dominatedBy &&
        !dominance.dominates(window.dominatedBy, boundary->getBlock()))
      return false;
    if (window.scope && (boundary->getBlock() != window.scope ||
                         operationOrder.lookup(boundary) < window.beginOrder ||
                         operationOrder.lookup(boundary) > window.endOrder))
      return false;
    auto found = boundaryFootprints.find(boundary);
    return found == boundaryFootprints.end() ||
           llvm::any_of(found->second, [&](const auto &range) {
             return window.offset < range.second && range.first < window.end;
           });
  };
  SmallVector<Window *> selected;
  for (Window &window : windows) {
    uint64_t width = window.end - window.offset;
    if (!window.read || !window.written || width > 32 ||
        (window.ranges.size() > 1 && !littleEndian) ||
        !(window.owners.size() > 1 || activation))
      continue;
    // Charge actual potential joins, not every block in an unrelated region.
    // A large evaluator may have thousands of blocks but only a few reaching
    // definitions for this window. The IDF bounds its SSA merge growth.
    llvm::SmallPtrSet<Block *, 32> definitions;
    definitions.insert(window.dominatedBy ? window.dominatedBy
                                          : &function.getBody().front());
    bool writesOnEntry = false;
    for (Range *range : window.ranges)
      for (Operation *operation : range->operations)
        if (isNativeMemoryStore(operation)) {
          definitions.insert(operation->getBlock());
          writesOnEntry |= operation->getBlock() == window.dominatedBy;
        }
    uint64_t relevantBoundaries =
        window.dominatedBy ? scopeExits.find(window.dominatedBy)->second.size()
                           : 0;
    for (Operation *boundary : boundaries) {
      if (!intersects(boundary, window))
        continue;
      ++relevantBoundaries;
      if (!isa<LLVM::ReturnOp>(boundary))
        definitions.insert(boundary->getBlock());
    }
    // An activation-local lane with a single conditional write often gains
    // a longer live range and unconditional epilogue stores, without saving
    // any source store. Retain that canonical form unless accesses share one
    // block or repeated writes can amortize the real publication cuts.
    // A window whose entry only compares old and new keeps its conditional
    // store on the change path. A write in the entry already takes effect
    // on every path through the scope.
    if (activation && window.owners.size() < 2 && !window.scope &&
        !writesOnEntry && window.stores <= relevantBoundaries)
      continue;
    SmallVector<Block *> joins;
    if (!function.getBody().hasOneBlock()) {
      llvm::IDFCalculatorBase<Block, false> idf(
          dominance.getDomTree(&function.getBody()));
      idf.setDefiningBlocks(definitions);
      idf.calculate(joins);
    }
    uint64_t cost = 4 + 6 * relevantBoundaries + joins.size();
    for (Range *range : window.ranges)
      if (range->type != IntegerType::get(function.getContext(), width * 8))
        cost += 5 * range->operations.size();
    if (budget < cost)
      continue;
    budget -= cost;
    selected.push_back(&window);
  }
  if (selected.empty())
    return success();
  OpBuilder builder(function.getContext());
  builder.setInsertionPointToStart(&function.getBody().front());
  Location location = function.getLoc();
  struct Slot {
    uint64_t offset;
    Value local;
    Type type;
    Window *window;
  };
  // Acquisition and publication are typed accesses of the plane's windows.
  auto acquire = [&](Location at, const Slot &slot) -> Value {
    return schedule::NativeStateLoadOp::create(builder, at, slot.type, plane,
                                               Value(), slot.offset, 1);
  };
  auto publish = [&](Location at, const Slot &slot, Value value) {
    schedule::NativeStateStoreOp::create(builder, at, value, plane, Value(),
                                         slot.offset, 1);
  };
  SmallVector<Slot> slots;
  SmallVector<PromotableAllocationOpInterface> allocations;
  for (Window *window : selected) {
    auto type = builder.getIntegerType((window->end - window->offset) * 8);
    Value local = entryAlloca(builder, location, type, 1, 1);
    allocations.push_back(
        cast<PromotableAllocationOpInterface>(local.getDefiningOp()));
    // IEEE 1800-2023 4.3, 4.6(a), 4.9.3: when every access is in one
    // block, acquire at its first access and publish after its last access.
    // This preserves source order and avoids touching state on a skipped
    // branch. Intervening observers still flush/reacquire below (38.15/38.34).
    // A multi-block window starts at the entry of its dominated region.
    // When it spans the function, acquire after the local allocation, which
    // stays valid as this loop erases the original accesses.
    if (window->scope)
      builder.setInsertionPoint(window->first);
    else if (window->dominatedBy)
      builder.setInsertionPointToStart(window->dominatedBy);
    else
      builder.setInsertionPointAfter(local.getDefiningOp());
    Slot slot{window->offset, local, type, window};
    LLVM::StoreOp::create(builder, location, acquire(location, slot), local, 1);
    slots.push_back(slot);
    for (Range *range : window->ranges)
      for (Operation *operation : range->operations) {
        builder.setInsertionPoint(operation);
        NativeMemoryAccess access = *getNativeMemoryAccess(operation);
        uint64_t byte = *access.offset - window->offset;
        unsigned bits = cast<IntegerType>(range->type).getWidth();
        unsigned shift = littleEndian.value_or(true)
                             ? byte * 8
                             : type.getWidth() - byte * 8 - bits;
        Value value;
        if (!access.isWrite()) {
          value = LLVM::LoadOp::create(builder, operation->getLoc(), type,
                                       local, 1);
          if (shift)
            value = LLVM::LShrOp::create(
                builder, operation->getLoc(), value,
                llvmConstant(builder, operation->getLoc(), type, shift));
          if (bits != type.getWidth())
            value = LLVM::TruncOp::create(builder, operation->getLoc(),
                                          range->type, value);
          operation->getResult(0).replaceAllUsesWith(value);
        } else {
          value = access.stored;
          if (bits != type.getWidth()) {
            value =
                LLVM::ZExtOp::create(builder, operation->getLoc(), type, value);
            if (shift)
              value = LLVM::ShlOp::create(
                  builder, operation->getLoc(), value,
                  llvmConstant(builder, operation->getLoc(), type, shift));
            APInt keep =
                ~APInt::getBitsSet(type.getWidth(), shift, shift + bits);
            Value old = LLVM::LoadOp::create(builder, operation->getLoc(), type,
                                             local, 1);
            Value mask = LLVM::ConstantOp::create(builder, operation->getLoc(),
                                                  type, keep);
            value = LLVM::OrOp::create(
                builder, operation->getLoc(),
                LLVM::AndOp::create(builder, operation->getLoc(), old, mask),
                value);
          }
          LLVM::StoreOp::create(builder, operation->getLoc(), value, local, 1);
        }
        if (window->scope && operation == window->last)
          publish(operation->getLoc(), slot,
                  LLVM::LoadOp::create(builder, operation->getLoc(), type,
                                       local, 1));
        operation->erase();
      }
    if (window->dominatedBy)
      for (Block *block : scopeExits.find(window->dominatedBy)->second) {
        Operation *exit = block->getTerminator();
        builder.setInsertionPoint(exit);
        publish(exit->getLoc(), slot,
                LLVM::LoadOp::create(builder, exit->getLoc(), type, local, 1));
      }
  }
  for (Operation *boundary : boundaries) {
    builder.setInsertionPoint(boundary);
    for (const Slot &slot : slots) {
      if (!intersects(boundary, *slot.window))
        continue;
      publish(boundary->getLoc(), slot,
              LLVM::LoadOp::create(builder, boundary->getLoc(), slot.type,
                                   slot.local, 1));
    }
    if (isa<LLVM::ReturnOp>(boundary))
      continue;
    builder.setInsertionPointAfter(boundary);
    for (const Slot &slot : slots) {
      if (!intersects(boundary, *slot.window))
        continue;
      LLVM::StoreOp::create(builder, boundary->getLoc(),
                            acquire(boundary->getLoc(), slot), slot.local, 1);
    }
  }
  if (failed(promoteScalarSlots(allocations, builder,
                                DataLayout::closest(function), dominance)))
    return function.emitError("could not materialize group state in SSA");
  auto attribute = plane == schedule::StatePlane::Value
                       ? ::talos::schedule::Field::EvalSsaValueRanges
                       : ::talos::schedule::Field::EvalSsaUnknownRanges;
  schedule::set(function, attribute, builder.getI64IntegerAttr(slots.size()));
  return success();
}

struct NativeEvalValueLane {
  schedule::StatePlane plane;
  uint64_t begin, end;
  bool written = false;
  SmallVector<Operation *> accesses;
};

struct NativeEvalValueInterface {
  LLVM::LLVMFuncOp body;
  SmallVector<NativeEvalValueLane> lanes;
  Type result;
  bool returnsStatus = false;
};

// Only the already selected, closed computation is eligible. In particular,
// the existence of a two-state implementation does not select that route.
bool isNativeEvalValueCall(LLVM::CallOp call, LLVM::LLVMFuncOp callee) {
  return callee && !callee.isExternal() &&
         (schedule::has<schedule::Field::EvalGroupDomainSelected>(call) ||
          schedule::has<schedule::metadata::evalInfallible>(callee) ||
          schedule::has<schedule::Field::EvalRawCaptures>(callee) ||
          schedule::has<schedule::Field::EvalFourStateSource>(callee) ||
          schedule::has<schedule::Field::EvalConditionallyTwoState>(callee));
}

ArrayAttr extendNativeEvalArgumentAttrs(OpBuilder &builder, ArrayAttr original,
                                        size_t count) {
  if (!original)
    return {};
  SmallVector<Attribute> attrs(original.getValue());
  attrs.resize(count, builder.getDictionaryAttr({}));
  return builder.getArrayAttr(attrs);
}

// Preserve the cold canonical ABI, but move (rather than duplicate) its body
// into a value interface. The source activation/route certificate still owns
// execution; the exact complete memory inventory proves only representation.
// IEEE 1800-2023 4.3 permits this representation change, while 4.6(a) and
// 4.9.3 require every blocking update and its transition actions to retain
// their original position. No final-value comparison replaces those actions.
FailureOr<NativeEvalValueInterface>
materializeNativeEvalValueInterface(LLVM::LLVMFuncOp function,
                                    SmallVector<NativeEvalValueLane> lanes,
                                    SymbolTable &symbols, bool littleEndian) {
  OpBuilder builder(function.getContext());
  Location location = function.getLoc();
  auto originalType = function.getFunctionType();
  bool status = !isa<LLVM::LLVMVoidType>(originalType.getReturnType());
  SmallVector<Type> arguments(originalType.getParams()), results;
  if (status)
    results.push_back(originalType.getReturnType());
  SmallVector<int64_t> description;
  for (const auto &lane : lanes) {
    Type type = builder.getIntegerType((lane.end - lane.begin) * 8);
    arguments.push_back(type);
    if (lane.written)
      results.push_back(type);
    description.append({int64_t(lane.plane == schedule::StatePlane::Unknown),
                        int64_t(lane.begin), int64_t(lane.end - lane.begin),
                        int64_t(lane.written)});
  }
  Type result = results.empty()
                    ? Type(LLVM::LLVMVoidType::get(function.getContext()))
                    : Type(LLVM::LLVMStructType::getLiteral(
                          function.getContext(), results));
  builder.setInsertionPoint(function);
  auto body = LLVM::LLVMFuncOp::create(
      builder, location, function.getSymName().str() + ".__talos_eval_values",
      LLVM::LLVMFunctionType::get(result, arguments, false),
      LLVM::Linkage::Internal);
  symbols.insert(body);
  schedule::inheritEvalRoles(function, body);
  if (auto passthrough = function.getPassthroughAttr())
    body.setPassthroughAttr(passthrough);
  if (auto attrs = extendNativeEvalArgumentAttrs(
          builder, function.getArgAttrsAttr(), arguments.size()))
    body.setArgAttrsAttr(attrs);
  schedule::set<schedule::Field::EvalValueLanes>(
      body, builder.getDenseI64ArrayAttr(description));
  body.getBody().takeBody(function.getBody());
  Block &entry = body.getBody().front();
  SmallVector<Value> locals;
  SmallVector<PromotableAllocationOpInterface> allocations;
  for (const auto &lane : lanes) {
    Type type = builder.getIntegerType((lane.end - lane.begin) * 8);
    Value argument = entry.addArgument(type, location);
    builder.setInsertionPointToStart(&entry);
    Value local = entryAlloca(builder, location, type, 1, 1);
    locals.push_back(local);
    allocations.push_back(
        cast<PromotableAllocationOpInterface>(local.getDefiningOp()));
    LLVM::StoreOp::create(builder, location, argument, local, 1);
    for (Operation *operation : lane.accesses) {
      builder.setInsertionPoint(operation);
      NativeMemoryAccess access = *getNativeMemoryAccess(operation);
      auto narrow = cast<IntegerType>(access.type);
      uint64_t byte = *access.offset - lane.begin;
      unsigned shift = littleEndian ? byte * 8
                                    : cast<IntegerType>(type).getWidth() -
                                          byte * 8 - narrow.getWidth();
      Value value;
      if (!access.isWrite()) {
        value =
            LLVM::LoadOp::create(builder, operation->getLoc(), type, local, 1);
        if (shift)
          value = LLVM::LShrOp::create(
              builder, operation->getLoc(), value,
              llvmConstant(builder, operation->getLoc(), type, shift));
        if (narrow != type)
          value = LLVM::TruncOp::create(builder, operation->getLoc(), narrow,
                                        value);
        operation->getResult(0).replaceAllUsesWith(value);
      } else {
        value = access.stored;
        if (narrow != type) {
          value =
              LLVM::ZExtOp::create(builder, operation->getLoc(), type, value);
          if (shift)
            value = LLVM::ShlOp::create(
                builder, operation->getLoc(), value,
                llvmConstant(builder, operation->getLoc(), type, shift));
          APInt keep = ~APInt::getBitsSet(cast<IntegerType>(type).getWidth(),
                                          shift, shift + narrow.getWidth());
          Value previous = LLVM::LoadOp::create(builder, operation->getLoc(),
                                                type, local, 1);
          value = LLVM::OrOp::create(
              builder, operation->getLoc(), value,
              LLVM::AndOp::create(builder, operation->getLoc(), previous,
                                  LLVM::ConstantOp::create(builder,
                                                           operation->getLoc(),
                                                           type, keep)));
        }
        LLVM::StoreOp::create(builder, operation->getLoc(), value, local, 1);
      }
      operation->erase();
    }
  }
  SmallVector<LLVM::ReturnOp> returns;
  body.walk([&](LLVM::ReturnOp ret) { returns.push_back(ret); });
  for (auto ret : returns) {
    builder.setInsertionPoint(ret);
    if (results.empty())
      continue;
    Value value = LLVM::UndefOp::create(builder, ret.getLoc(), result);
    unsigned field = 0;
    if (status)
      value = insertValue(builder, ret.getLoc(), value, ret.getArg(), field++);
    for (auto [i, lane] : llvm::enumerate(lanes))
      if (lane.written)
        value = insertValue(
            builder, ret.getLoc(), value,
            LLVM::LoadOp::create(builder, ret.getLoc(),
                                 arguments[originalType.getNumParams() + i],
                                 locals[i], 1),
            field++);
    LLVM::ReturnOp::create(builder, ret.getLoc(), value);
    ret.erase();
  }
  DominanceInfo dominance(body);
  if (failed(promoteScalarSlots(allocations, builder, DataLayout::closest(body),
                                dominance)))
    return body.emitError("could not promote eval value interface");

  // Old callers (fine Tier 2/3 execution, guards and function pointers) keep
  // the same symbol and ABI. Only a selected generated caller bypasses this
  // acquisition/publication wrapper. Observer/runtime calls still cut its
  // caller's SSA lifetime (IEEE 1800-2023 4.3, 38.15 and 38.34).
  Block *wrapper = function.addEntryBlock(builder);
  builder.setInsertionPointToStart(wrapper);
  SmallVector<Value> inputs(wrapper->getArguments());
  for (const auto &lane : lanes)
    inputs.push_back(schedule::NativeStateLoadOp::create(
        builder, location, builder.getIntegerType((lane.end - lane.begin) * 8),
        lane.plane, Value(), lane.begin, 1));
  auto call = LLVM::CallOp::create(
      builder, location, results.empty() ? TypeRange{} : TypeRange{result},
      body.getSymName(), inputs);
  if (auto attrs = body.getArgAttrsAttr())
    call.setArgAttrsAttr(attrs);
  unsigned field = status;
  for (const auto &lane : lanes)
    if (lane.written)
      schedule::NativeStateStoreOp::create(
          builder, location,
          LLVM::ExtractValueOp::create(builder, location, call.getResult(),
                                       ArrayRef<int64_t>{field++}),
          lane.plane, Value(), lane.begin, 1);
  if (status)
    LLVM::ReturnOp::create(builder, location,
                           LLVM::ExtractValueOp::create(builder, location,
                                                        call.getResult(),
                                                        ArrayRef<int64_t>{0}));
  else
    LLVM::ReturnOp::create(builder, location, ValueRange{});
  for (auto &lane : lanes)
    lane.accesses.clear();
  return NativeEvalValueInterface{body, std::move(lanes), result, status};
}

// Outlining a closed computation must not force a canonical round trip.
// Carry shared current lanes as arguments/results, allowing the existing
// caller-side SSA promoter to combine them with inlined computation. Pending
// NBA payloads remain separate; this never turns an enqueue into a blocking
// write (IEEE 1800-2023 4.9.4 and 10.4.2).
LogicalResult materializeNativeEvalValueCalls(
    ModuleOp module,
    SmallVector<std::pair<LLVM::LLVMFuncOp, uint64_t>> &callers,
    const llvm::StringMap<Type> &globalTypes,
    const llvm::StringMap<NativeStateFootprint> &footprints,
    DenseSet<Operation *> &valueCallers) {
  auto layout = module->getAttrOfType<StringAttr>("llvm.data_layout");
  if (!layout)
    return success();
  auto parsed = llvm::DataLayout::parse(layout.getValue());
  if (!parsed) {
    llvm::consumeError(parsed.takeError());
    return module.emitError("invalid native eval value data layout");
  }
  SymbolTable symbols(module);
  DenseMap<Operation *, NativeEvalValueInterface> interfaces;
  DenseSet<Operation *> rejected;
  uint64_t valueCalls = 0;
  for (auto &[caller, budget] : callers) {
    SmallVector<LLVM::CallOp> calls;
    caller.walk([&](LLVM::CallOp call) { calls.push_back(call); });
    NativeStateFootprint callerAccesses{true, {}, {}};
    caller.walk([&](Operation *operation) {
      auto access = getNativeMemoryAccess(operation);
      if (!access)
        return;
      auto plane = getStatePlaneOfAccess(*access);
      auto type = dyn_cast<IntegerType>(access->type);
      auto offset = access->offset;
      if (plane && type && offset && type.getWidth() % 8 == 0)
        (*plane == schedule::StatePlane::Value ? callerAccesses.value
                                               : callerAccesses.unknown)
            .emplace_back(*offset, *offset + type.getWidth() / 8);
    });
    normalizeNativeByteFootprint(callerAccesses.value);
    normalizeNativeByteFootprint(callerAccesses.unknown);
    SmallVector<std::pair<Operation *, const NativeStateFootprint *>>
        nativeCalls;
    for (auto call : calls)
      if (call.getCallee()) {
        auto definition = symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee());
        auto footprint = footprints.find(*call.getCallee());
        if (isNativeEvalValueCall(call, definition) &&
            footprint != footprints.end() && footprint->second.exact)
          nativeCalls.emplace_back(call, &footprint->second);
      }
    for (auto call : calls) {
      if (!call.getCallee())
        continue;
      auto callee = symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee());
      if (!isNativeEvalValueCall(call, callee) || callee == caller ||
          rejected.contains(callee) || callee.getFunctionType().isVarArg() ||
          callee.getCConv() != LLVM::cconv::CConv::C ||
          call.getCConv() != LLVM::cconv::CConv::C ||
          call.getTailCallKind() != LLVM::tailcallkind::TailCallKind::None ||
          !call.getOpBundleSizes().empty())
        continue;
      auto found = interfaces.find(callee);
      if (found == interfaces.end()) {
        auto footprint = footprints.find(callee.getSymName());
        Type originalResult = callee.getFunctionType().getReturnType();
        bool status = !isa<LLVM::LLVMVoidType>(originalResult);
        if (footprint == footprints.end() || !footprint->second.exact ||
            (status && (!isa<IntegerType>(originalResult) ||
                        cast<IntegerType>(originalResult).getWidth() > 64))) {
          rejected.insert(callee);
          continue;
        }
        SmallVector<NativeEvalValueLane> ranges;
        NativeStateFootprint cuts{true, {}, {}};
        auto planeArray = [&](schedule::StatePlane plane) {
          return dyn_cast_or_null<LLVM::LLVMArrayType>(
              globalTypes.lookup(schedule::getStatePlaneGlobalName(plane)));
        };
        auto cutPlane =
            [&](schedule::StatePlane plane) -> NativeByteFootprint & {
          return plane == schedule::StatePlane::Value ? cuts.value
                                                      : cuts.unknown;
        };
        auto cutWholePlane = [&](schedule::StatePlane plane) {
          cutPlane(plane).emplace_back(0, planeArray(plane).getNumElements());
        };
        auto cutPointer = [&](Value pointer) {
          if (auto plane = getStatePlaneRoot(pointer);
              plane && schedule::isCanonicalStatePlane(*plane))
            cutWholePlane(*plane);
        };
        // Freeze cuts once, rather than rescanning the complete body for every
        // lane. Nested readers, intrinsics and dynamic/atomic accesses cannot
        // be replaced by a fixed value argument/result interface.
        callee.walk([&](Operation *operation) {
          if (auto nested = dyn_cast<LLVM::CallOp>(operation)) {
            if (nested.getCallee())
              if (auto target = footprints.find(*nested.getCallee());
                  target != footprints.end()) {
                llvm::append_range(cuts.value, target->second.value);
                llvm::append_range(cuts.unknown, target->second.unknown);
              }
            return;
          }
          if (auto copy = dyn_cast<LLVM::MemcpyOp>(operation)) {
            cutPointer(copy.getSrc());
            cutPointer(copy.getDst());
            return;
          }
          if (auto set = dyn_cast<LLVM::MemsetOp>(operation)) {
            cutPointer(set.getDst());
            return;
          }
          auto access = getNativeMemoryAccess(operation);
          if (!access || !access->plane)
            return;
          schedule::StatePlane plane = *access->plane;
          auto offset = access->offset;
          auto type = dyn_cast<IntegerType>(access->type);
          auto array = planeArray(plane);
          if (!offset || !access->plain) {
            DenseI64ArrayAttr bytes = access->window;
            if (bytes && bytes.size() == 2 && bytes[0] >= 0 &&
                bytes[1] > bytes[0])
              cutPlane(plane).emplace_back(bytes[0], bytes[1]);
            else if (offset && type && type.getWidth() % 8 == 0)
              cutPlane(plane).emplace_back(*offset,
                                           *offset + type.getWidth() / 8);
            else
              cutWholePlane(plane);
            return;
          }
          if (type && type.getWidth() % 8 == 0 && array &&
              *offset <= array.getNumElements() &&
              type.getWidth() / 8 <= array.getNumElements() - *offset)
            ranges.push_back({plane,
                              *offset,
                              *offset + type.getWidth() / 8,
                              access->isWrite(),
                              {operation}});
        });
        llvm::sort(ranges, [](const auto &a, const auto &b) {
          return std::tie(a.plane, a.begin, a.end) <
                 std::tie(b.plane, b.begin, b.end);
        });
        SmallVector<NativeEvalValueLane> windows;
        for (auto &range : ranges) {
          if (windows.empty() || windows.back().plane != range.plane ||
              windows.back().end <= range.begin)
            windows.push_back(std::move(range));
          else {
            auto &window = windows.back();
            window.end = std::max(window.end, range.end);
            window.written |= range.written;
            llvm::append_range(window.accesses, range.accesses);
          }
        }
        auto overlaps = [](const NativeEvalValueLane &lane,
                           const NativeStateFootprint &footprint) {
          const auto &ranges = lane.plane == schedule::StatePlane::Value
                                   ? footprint.value
                                   : footprint.unknown;
          auto first = llvm::lower_bound(
              ranges, lane.begin,
              [](auto range, uint64_t begin) { return range.second <= begin; });
          return first != ranges.end() && first->first < lane.end;
        };
        normalizeNativeByteFootprint(cuts.value);
        normalizeNativeByteFootprint(cuts.unknown);
        llvm::erase_if(windows, [&](const auto &lane) {
          if (lane.end - lane.begin > 16)
            return true;
          bool closed = !overlaps(lane, cuts);
          bool shared = overlaps(lane, callerAccesses);
          for (auto [other, footprint] : nativeCalls)
            if (other != call.getOperation())
              shared |= overlaps(lane, *footprint);
          return !closed || !shared;
        });
        llvm::stable_sort(windows, [](const auto &a, const auto &b) {
          return a.accesses.size() > b.accesses.size();
        });
        SmallVector<NativeEvalValueLane> selected;
        unsigned outputs = status, arguments = 0;
        for (Type argument : callee.getFunctionType().getParams())
          arguments += isa<IntegerType>(argument)
                           ? (cast<IntegerType>(argument).getWidth() + 63) / 64
                           : 1;
        uint64_t cost = 0;
        for (auto &lane : windows) {
          // Keep the return in at most two machine words and the complete
          // input interface within the integer-register argument budget.
          unsigned words = (lane.end - lane.begin + 7) / 8;
          if (outputs + words * lane.written > 2 || arguments + words > 6)
            continue;
          uint64_t growth = 12 + 8 * callee.getBody().getBlocks().size();
          for (auto *operation : lane.accesses) {
            Type type = getNativeMemoryAccess(operation)->type;
            if (cast<IntegerType>(type).getWidth() !=
                (lane.end - lane.begin) * 8)
              growth += 5;
          }
          if (cost + growth + 8 * (selected.size() + 1) > budget)
            continue;
          cost += growth;
          outputs += words * lane.written;
          arguments += words;
          selected.push_back(std::move(lane));
        }
        if (selected.empty())
          continue;
        auto interface = materializeNativeEvalValueInterface(
            callee, std::move(selected), symbols, parsed->isLittleEndian());
        if (failed(interface))
          return failure();
        budget -= cost;
        found = interfaces.try_emplace(callee, std::move(*interface)).first;
      }
      auto &interface = found->second;
      uint64_t cost = 8 * interface.lanes.size();
      if (budget < cost)
        continue;
      budget -= cost;
      OpBuilder builder(call);
      SmallVector<Value> arguments(call.getOperands());
      auto owner = schedule::get<schedule::Field::EvalGroupMember>(call);
      for (const auto &lane : interface.lanes) {
        auto load = schedule::NativeStateLoadOp::create(
            builder, call.getLoc(),
            builder.getIntegerType((lane.end - lane.begin) * 8), lane.plane,
            Value(), lane.begin, 1);
        if (owner)
          load.setOwnerAttr(owner);
        arguments.push_back(load);
      }
      bool result = !isa<LLVM::LLVMVoidType>(interface.result);
      auto replacement = LLVM::CallOp::create(
          builder, call.getLoc(),
          result ? TypeRange{interface.result} : TypeRange{},
          interface.body.getSymName(), arguments);
      if (auto attrs = extendNativeEvalArgumentAttrs(
              builder, call.getArgAttrsAttr(), arguments.size()))
        replacement.setArgAttrsAttr(attrs);
      for (auto attr : call->getAttrs())
        if (attr.getName().strref().starts_with("schedule.eval."))
          replacement->setAttr(attr.getName(), attr.getValue());
      unsigned field = interface.returnsStatus;
      for (const auto &lane : interface.lanes)
        if (lane.written) {
          auto store = schedule::NativeStateStoreOp::create(
              builder, call.getLoc(),
              LLVM::ExtractValueOp::create(builder, call.getLoc(),
                                           replacement.getResult(),
                                           ArrayRef<int64_t>{field++}),
              lane.plane, Value(), lane.begin, 1);
          if (owner)
            store.setOwnerAttr(owner);
        }
      if (interface.returnsStatus)
        call.getResult().replaceAllUsesWith(LLVM::ExtractValueOp::create(
            builder, call.getLoc(), replacement.getResult(),
            ArrayRef<int64_t>{0}));
      call.erase();
      valueCallers.insert(caller);
      ++valueCalls;
    }
  }
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos eval value interfaces: cores=" << interfaces.size()
                 << " calls=" << valueCalls << '\n';
  return success();
}

struct NativeGroupPromotionInputs {
  explicit NativeGroupPromotionInputs(Operation *operation) {
    for (auto global : cast<ModuleOp>(operation).getOps<LLVM::GlobalOp>())
      globalTypes.try_emplace(global.getSymName(), global.getGlobalType());
    for (auto function : cast<ModuleOp>(operation).getOps<LLVM::LLVMFuncOp>())
      if (schedule::has<schedule::Field::EvalStateMetadataOnly>(function))
        metadataOnly.insert(function.getSymName());
    callFootprints = buildNativeStateFootprints(cast<ModuleOp>(operation),
                                                globalTypes, metadataOnly);
    debugTiming = native::has<native::DebugTiming>(operation);
  }
  llvm::StringMap<Type> globalTypes;
  llvm::StringSet<> metadataOnly;
  llvm::StringMap<NativeStateFootprint> callFootprints;
  DenseMap<Operation *, std::pair<uint64_t, size_t>> residuals;
  std::shared_ptr<NativeGroupPromotionReport> report;
  bool debugTiming = false;
};

class PromoteNativeGroupFunctionPass final
    : public PassWrapper<PromoteNativeGroupFunctionPass,
                         OperationPass<LLVM::LLVMFuncOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(PromoteNativeGroupFunctionPass)
  StringRef getArgument() const final {
    return "promote-native-group-function";
  }
  // Promotion acquires and publishes state windows with typed accesses.
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<LLVM::LLVMDialect, schedule::ScheduleDialect,
                    native::NativeDialect>();
  }
  void runOnOperation() override {
    auto function = getOperation();
    auto cached = getCachedParentAnalysis<NativeGroupPromotionInputs>(
        function->getParentOfType<ModuleOp>());
    if (!cached) {
      function.emitError("native group promotion requires cached global types");
      return signalPassFailure();
    }
    const auto &inputs = cached->get();
    auto found = inputs.residuals.find(function);
    if (found == inputs.residuals.end()) {
      markAllAnalysesPreserved();
      return;
    }
    auto [budget, index] = found->second;
    uint64_t remaining = budget;
    if (failed(promoteGroupState(function, inputs.globalTypes,
                                 schedule::StatePlane::Value, remaining,
                                 inputs.metadataOnly, inputs.callFootprints)) ||
        failed(promoteGroupState(function, inputs.globalTypes,
                                 schedule::StatePlane::Unknown, remaining,
                                 inputs.metadataOnly, inputs.callFootprints)))
      return signalPassFailure();
    if (remaining == budget) {
      markAllAnalysesPreserved();
      return;
    }
    if (!inputs.debugTiming)
      return;
    llvm::raw_string_ostream diagnostic(inputs.report->diagnostics[index]);
    auto count = [&](schedule::Field name) -> uint64_t {
      auto value = schedule::get<IntegerAttr>(function, name);
      return value ? value.getUInt() : 0;
    };
    diagnostic << "talos native group: " << function.getSymName()
               << " expanded_calls="
               << count(schedule::Field::EvalMaterializedGroupCalls)
               << " value_ranges=" << count(schedule::Field::EvalSsaValueRanges)
               << " unknown_ranges="
               << count(schedule::Field::EvalSsaUnknownRanges)
               << " remaining_budget=" << remaining << '\n';
  }
};

struct InlinedGroupBody {
  uint64_t remaining;
  uint64_t materialized;
};

InlinedGroupBody
inlineGroupBody(LLVM::LLVMFuncOp function, const SymbolTable &symbols,
                const DenseMap<Operation *, uint64_t> &stableCosts,
                DenseMap<Operation *, uint64_t> &costs,
                uint64_t operationLimit) {
  InlinerInterface interface(function.getContext());
  SmallVector<LLVM::CallOp> pending;
  llvm::SmallDenseSet<uint64_t, 4> members;
  function.walk([&](LLVM::CallOp call) {
    if (auto owner =
            ::talos::schedule::get<::talos::schedule::Field::EvalGroupMember>(
                call)) {
      pending.push_back(call);
      members.insert(owner.getValue().getZExtValue());
    }
  });
  // A group body forwards state and readiness between its members: the
  // promotions that follow defer one member's publications to another
  // member's reads. A group calling one member has nothing to forward; the
  // member's own reads already see its writes as values
  // (talos-sim-forward-activation-state). Inlining would only copy its
  // two- and four-state bodies into the group.
  if (members.size() < 2)
    return {operationLimit, 0};
  std::reverse(pending.begin(), pending.end());
  // The existing native helper-size budget also caps total additional IR
  // per coordinator. Oversized computation stays in direct helpers; helper
  // calls do not acquire time/region ownership or become scheduler exits.
  uint64_t remaining = operationLimit;
  uint64_t materialized = 0;
  llvm::DenseSet<Operation *> expanded;
  while (!pending.empty()) {
    LLVM::CallOp call = pending.pop_back_val();
    if (!call.getCallee())
      continue;
    auto callee = symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee());
    if (!callee || callee == function || callee.isExternal() ||
        expanded.contains(callee) ||
        !(::talos::schedule::has<
              ::talos::schedule::Field::EvalGroupDomainSelected>(call) ||
          ::talos::schedule::has<schedule::metadata::evalInfallible>(callee) ||
          ::talos::schedule::has<::talos::schedule::Field::EvalFourStateSource>(
              callee) ||
          ::talos::schedule::has<
              ::talos::schedule::Field::EvalConditionallyTwoState>(callee)))
      continue;
    uint64_t cost;
    if (auto frozen = stableCosts.find(callee); frozen != stableCosts.end()) {
      cost = frozen->second;
    } else {
      auto [found, inserted] = costs.try_emplace(callee, 0);
      if (inserted)
        found->second = nativeInlineCost(callee);
      cost = found->second;
    }
    if (!cost || cost > remaining)
      continue;
    SmallVector<LLVM::CallOp> nested;
    auto owner =
        ::talos::schedule::get<::talos::schedule::Field::EvalGroupMember>(call);
    auto clone = [&](OpBuilder &, Region *source, Block *inlineBlock,
                     Block *postInsertBlock, IRMapping &mapping,
                     bool shouldClone) {
      assert(shouldClone && "canonical executor bodies must remain intact");
      source->cloneInto(inlineBlock->getParent(),
                        postInsertBlock->getIterator(), mapping);
      for (Block &block : *source)
        for (Operation &operation : *mapping.lookup(&block)) {
          if (owner && isNativeMemoryAccess(&operation))
            setNativeMemoryOwner(&operation, owner);
          if (auto child = dyn_cast<LLVM::CallOp>(operation)) {
            if (owner)
              ::talos::schedule::set<::talos::schedule::Field::EvalGroupMember>(
                  child, owner);
            nested.push_back(child);
          }
        }
    };
    if (failed(inlineCall(interface, clone, cast<CallOpInterface>(*call),
                          cast<CallableOpInterface>(*callee),
                          &callee.getBody())))
      continue;
    call.erase();
    // Shared computation remains a direct helper after one expansion.
    // Besides avoiding Cartesian cloning, this cuts recursive call edges
    // even when the user disables the operation-size budget.
    expanded.insert(callee);
    remaining -= cost;
    ++materialized;
    std::reverse(nested.begin(), nested.end());
    llvm::append_range(pending, nested);
  }
  if (materialized)
    ::talos::schedule::set<
        ::talos::schedule::Field::EvalMaterializedGroupCalls>(
        function, IntegerAttr::get(IntegerType::get(function.getContext(), 64),
                                   materialized));
  return {remaining, materialized};
}

LogicalResult
emitGroupDomainGuard(OpBuilder &builder, Location loc,
                     ArrayRef<std::pair<unsigned, uint64_t>> masks,
                     SymbolTable &symbols, bool refreshPending,
                     schedule::GroupProofDependencyAttr domain, Block *known,
                     ValueRange arguments, Block *fallback) {
  auto i64 = builder.getI64Type();
  if (domain && !refreshPending) {
    auto ready = symbols.lookup<LLVM::LLVMFuncOp>(groupPromotionReadyName);
    auto latches = symbols.lookup<LLVM::GlobalOp>(groupPromotionLatchName);
    auto latchType =
        latches ? dyn_cast<LLVM::LLVMArrayType>(latches.getGlobalType())
                : LLVM::LLVMArrayType{};
    std::map<unsigned, uint64_t> expected;
    for (int32_t member : domain.getMembers().asArrayRef())
      if (member >= 0)
        expected[unsigned(member) / 64] |= uint64_t{1}
                                           << (unsigned(member) % 64);
    if (!domain.getDomain() || !latchType ||
        !latchType.getElementType().isInteger(8) ||
        domain.getDomain().getUInt() >= latchType.getNumElements() ||
        !llvm::equal(masks, expected,
                     [](auto a, auto b) {
                       return a.first == b.first && a.second == b.second;
                     }) ||
        !ready || ready.isExternal() ||
        ready.getFunctionType() !=
            LLVM::LLVMFunctionType::get(builder.getI1Type(), {i64}, false))
      return emitError(loc, "group guard has an invalid planned proof domain");
    // IEEE 1800-2023 4.5/4.6, 6.3.1: inspect the exact member union at this
    // existing entry boundary. The query can establish knownness even for
    // inactive/unqueried members, without executing them or clearing their
    // own proof/ready bits. The unchanged ordinary body remains authoritative
    // whenever any required bit is X/Z. Refined children retain member guards.
    Value proved = LLVM::CallOp::create(
                       builder, loc, ready,
                       ValueRange{llvmConstant(builder, loc, i64,
                                               domain.getDomain().getUInt())})
                       .getResult();
    LLVM::CondBrOp::create(builder, loc, proved, known, arguments, fallback,
                           ValueRange{});
    return success();
  }
  Value zero = llvmConstant(builder, loc, i64, 0);
  Value needed = zero;
  SmallVector<std::pair<unsigned, Value>> words;
  for (auto [word, mask] : masks) {
    Value bits = LLVM::AndOp::create(
        builder, loc,
        loadMaskWord(builder, loc, schedule::EvalMask::PromotionPending, word),
        llvmConstant(builder, loc, i64, mask));
    words.emplace_back(word, bits);
    needed = LLVM::OrOp::create(builder, loc, needed, bits);
  }
  Value cached =
      LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::eq, needed, zero);
  auto ready = symbols.lookup<LLVM::LLVMFuncOp>(kernelPromotionReadyName);
  if (!refreshPending || !ready || ready.isExternal() ||
      ready.getFunctionType() !=
          LLVM::LLVMFunctionType::get(builder.getI1Type(), {i64}, false)) {
    LLVM::CondBrOp::create(builder, loc, cached, known, arguments, fallback,
                           ValueRange{});
    return success();
  }
  // A pending certificate can be unqueried, even after its inputs became
  // known during initialization. Refresh all needed group members, including
  // inactive ones, before choosing the group body. This only inspects
  // canonical X/Z and updates proof caches; it executes no source activation
  // (IEEE 1800-2023 4.3, 6.3.1, 6.11.2). The first failed proof keeps the
  // fallback.
  Region *region = builder.getBlock()->getParent();
  auto block = [&](bool argument = false) {
    auto *result = new Block;
    region->push_back(result);
    if (argument)
      result->addArgument(i64, loc);
    return result;
  };
  Block *refresh = block();
  LLVM::CondBrOp::create(builder, loc, cached, known, arguments, refresh,
                         ValueRange{});
  builder.setInsertionPointToStart(refresh);
  for (auto [word, bits] : words) {
    Block *nextBit = block(true), *inspect = block(), *nextWord = block();
    LLVM::BrOp::create(builder, loc, ValueRange{bits}, nextBit);
    builder.setInsertionPointToStart(nextBit);
    Value remaining = nextBit->getArgument(0);
    Value empty = LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::eq,
                                       remaining, zero);
    LLVM::CondBrOp::create(builder, loc, empty, nextWord, ValueRange{}, inspect,
                           ValueRange{});
    builder.setInsertionPointToStart(inspect);
    Value bit =
        LLVM::CountTrailingZerosOp::create(builder, loc, i64, remaining, true);
    Value owner = LLVM::AddOp::create(
        builder, loc, bit,
        llvmConstant(builder, loc, i64, uint64_t{word} * 64));
    Value tail = LLVM::AndOp::create(
        builder, loc, remaining,
        LLVM::SubOp::create(builder, loc, remaining,
                            llvmConstant(builder, loc, i64, 1)));
    Value proved = LLVM::CallOp::create(builder, loc, ready, ValueRange{owner})
                       .getResult();
    LLVM::CondBrOp::create(builder, loc, proved, nextBit, ValueRange{tail},
                           fallback, ValueRange{});
    builder.setInsertionPointToStart(nextWord);
  }
  LLVM::BrOp::create(builder, loc, arguments, known);
  return success();
}

/// The groups of a module, in order, and what their materialization may
/// assume before it changes any body.
struct GroupPlan {
  /// Every group, in module order.
  SmallVector<LLVM::LLVMFuncOp> groups;
  /// Candidates with existing callers. Candidates are transient
  /// compiler-owned bodies; preserve user-authored ones rather than deleting
  /// or retargeting their callable interface.
  DenseSet<Operation *> externallyUsedCandidates;
  /// Costs of the non-group definitions that groups reach; group
  /// materialization never changes them.
  DenseMap<Operation *, uint64_t> stableCosts;
  /// Groups that no other group calls or refines, and that call nothing
  /// leading to a group: preparing one (inlining its members, eliding its
  /// publications, lowering its actions) reads only definitions that do not
  /// change, so workers can prepare them concurrently.
  SmallVector<LLVM::LLVMFuncOp> independent;
};

DenseSet<Operation *>
findExternallyUsedCandidates(ModuleOp module,
                             ArrayRef<LLVM::LLVMFuncOp> groups) {
  DenseSet<Operation *> used;
  if (llvm::none_of(groups, [](auto function) {
        return ::talos::schedule::has<
            ::talos::schedule::Field::EvalDataflowCandidate>(function);
      }))
    return used;
  // Inventory uses once, not once per group.
  SmallVector<Region *> scopes;
  for (Operation *operation : analysis::collectInWalkOrder<Operation *>(
           module, [](Operation *operation) {
             return operation->hasTrait<OpTrait::SymbolTable>();
           }))
    for (Region &region : operation->getRegions())
      scopes.push_back(&region);
  auto uses = collectNativeSymbolUses(module.getContext(), scopes);
  if (!uses) {
    // An unknown symbol scope cannot prove a transient candidate unused.
    for (auto function : groups)
      if (::talos::schedule::has<
              ::talos::schedule::Field::EvalDataflowCandidate>(function))
        used.insert(function);
    return used;
  }
  SymbolTableCollection tables;
  // Resolve in the scope containing the user, as SymbolUserMap does.
  // A symbol-table operation's own attributes still use its outer scope.
  for (const auto &use : *uses)
    if (auto function = tables.lookupNearestSymbolFrom<LLVM::LLVMFuncOp>(
            use.getUser()->getParentOp(), use.getSymbolRef());
        function &&
        ::talos::schedule::has<::talos::schedule::Field::EvalDataflowCandidate>(
            function))
      used.insert(function);
  return used;
}

GroupPlan planGroups(ModuleOp module, const SymbolTable &symbols) {
  GroupPlan plan;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>())
    if (::talos::schedule::has<::talos::schedule::Field::EvalRankedMembers>(
            function))
      plan.groups.push_back(function);
  plan.externallyUsedCandidates =
      findExternallyUsedCandidates(module, plan.groups);

  // Establish body read/write dependencies over the call graph before
  // mutation. A worker must neither read a group another worker can change,
  // nor change a definition read by the ordered refinement phase. Shared leaf
  // executors remain immutable; groups with dependencies retain source order.
  // The graph has the call edges mlir::CallGraph records between the defined
  // functions, gathered concurrently: a call to a declaration or through a
  // pointer reaches no node. Nested callables would need CallGraph's child
  // edges; then every group keeps its order, which only costs concurrency.
  SmallVector<LLVM::LLVMFuncOp> definitions;
  DenseMap<Operation *, unsigned> nodes;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>())
    if (!function.isExternal()) {
      nodes.try_emplace(function, definitions.size());
      definitions.push_back(function);
    }
  bool flatCallables = !analysis::anyNested<CallableOpInterface>(
      module, [&](CallableOpInterface callable) {
        return callable.getCallableRegion() &&
               !(isa<LLVM::LLVMFuncOp>(callable) &&
                 callable->getParentOp() == module.getOperation());
      });
  SmallVector<SmallVector<unsigned, 4>> callees(definitions.size());
  analysis::parallelForChunked(
      module.getContext(), definitions.size(), [&](size_t index) {
        llvm::SmallDenseSet<unsigned, 8> unique;
        definitions[index].walk([&](CallOpInterface call) {
          auto reference = dyn_cast<SymbolRefAttr>(call.getCallableForCallee());
          if (!reference || !reference.getNestedReferences().empty())
            return;
          auto callee =
              nodes.find(symbols.lookup(reference.getRootReference()));
          if (callee != nodes.end() && unique.insert(callee->second).second)
            callees[index].push_back(callee->second);
        });
      });
  SmallVector<SmallVector<unsigned, 4>> callers(definitions.size());
  for (auto [caller, targets] : llvm::enumerate(callees))
    for (unsigned callee : targets)
      callers[callee].push_back(caller);
  SmallVector<char> groupNodes(definitions.size(), false),
      reachesGroup(definitions.size(), false),
      referencedGroups(definitions.size(), false),
      reachable(definitions.size(), false);
  SmallVector<unsigned> pending;
  for (auto function : plan.groups)
    if (auto node = nodes.find(function); node != nodes.end()) {
      groupNodes[node->second] = true;
      reachesGroup[node->second] = true;
      pending.push_back(node->second);
    }
  SmallVector<unsigned> groupIndices(pending);
  while (!pending.empty()) {
    unsigned node = pending.pop_back_val();
    for (unsigned caller : callers[node])
      if (!reachesGroup[caller]) {
        reachesGroup[caller] = true;
        pending.push_back(caller);
      }
  }
  llvm::append_range(pending, groupIndices);
  while (!pending.empty()) {
    unsigned node = pending.pop_back_val();
    if (reachable[node])
      continue;
    reachable[node] = true;
    for (unsigned callee : callees[node]) {
      if (groupNodes[callee])
        referencedGroups[callee] = true;
      pending.push_back(callee);
    }
  }
  SmallVector<LLVM::LLVMFuncOp> stableDefinitions;
  for (auto [node, function] : llvm::enumerate(definitions))
    if (reachable[node] && !groupNodes[node])
      stableDefinitions.push_back(function);
  SmallVector<uint64_t> stableCounts(stableDefinitions.size());
  parallelFor(module.getContext(), 0, stableDefinitions.size(), [&](size_t i) {
    stableCounts[i] = nativeInlineCost(stableDefinitions[i]);
  });
  for (auto [i, function] : llvm::enumerate(stableDefinitions))
    plan.stableCosts.try_emplace(function, stableCounts[i]);

  // Refinement can replace the original named by candidate metadata without
  // a call edge. Preserve that write-before-inline dependency as well. An
  // original preceding its candidate may be prepared early: its ordered
  // preparation already runs before the candidate's body transaction.
  DenseMap<Operation *, size_t> groupOrder;
  for (auto [i, function] : llvm::enumerate(plan.groups))
    groupOrder.try_emplace(function, i);
  DenseSet<Operation *> earlyRefinementTargets;
  for (auto [i, function] : llvm::enumerate(plan.groups))
    if (auto candidate = ::talos::schedule::get<
            ::talos::schedule::Field::EvalDataflowCandidate>(function)) {
      auto original = symbols.lookup<LLVM::LLVMFuncOp>(candidate.getValue());
      auto position = groupOrder.find(original);
      if (position != groupOrder.end() && position->second > i)
        earlyRefinementTargets.insert(original);
    }
  for (auto function : plan.groups) {
    auto node = nodes.find(function);
    if (!flatCallables || node == nodes.end() ||
        referencedGroups[node->second] ||
        earlyRefinementTargets.contains(function) ||
        plan.externallyUsedCandidates.contains(function) ||
        llvm::any_of(callees[node->second],
                     [&](unsigned callee) { return reachesGroup[callee]; }))
      continue;
    plan.independent.push_back(function);
  }
  return plan;
}

/// The part of materializing a group that changes only its own body: its
/// members inlined, its redundant publications elided and its schedule
/// actions lowered.
struct PreparedGroup {
  InlinedGroupBody body;
  unsigned elidedPublications = 0;
  /// How a worker lowered its schedule actions. One whose lowering would add
  /// a module symbol is left to the ordered phase; the runtime entry points
  /// the lowered actions call are declared there, in order.
  std::optional<NativeFunctionActionLowering> actions;
  LogicalResult status = success();
};

/// A group whose dataflow candidate was rejected, split into children that
/// partition its members. Its body becomes a sequence of child calls once
/// every group has materialized.
struct GroupRefinement {
  LLVM::LLVMFuncOp parent;
  SmallVector<LLVM::LLVMFuncOp> children;
};

/// Materializes the group bodies of a module in order: inline each group's
/// members, then install an accepted candidate's dataflow body in front of
/// its original, refine the original of a rejected one into children, erase
/// an invalid one, or leave an ordinary group for residual promotion.
class GroupMaterializer {
public:
  GroupMaterializer(ModuleOp module, NativeGroupPromotionInputs &inputs,
                    NativeGroupPromotionReport &report)
      : module(module), inputs(inputs), report(report),
        symbols(symbolTables.getSymbolTable(module)),
        operationLimit(schedule::getMaxInlineOperations(module)),
        plan(planGroups(module, symbols)), worklist(plan.groups) {}

  LogicalResult run();

private:
  PreparedGroup
  prepareConcurrently(LLVM::LLVMFuncOp function,
                      const schedule::NativeGlobalLookup &globals);
  PreparedGroup prepare(LLVM::LLVMFuncOp function);
  LogicalResult materializeGroup(LLVM::LLVMFuncOp function,
                                 const PreparedGroup &group);
  bool isValidCandidate(LLVM::LLVMFuncOp function, LLVM::LLVMFuncOp original,
                        DenseI32ArrayAttr members);
  void refineOriginal(LLVM::LLVMFuncOp function, LLVM::LLVMFuncOp original);
  LogicalResult acceptCandidate(LLVM::LLVMFuncOp function,
                                LLVM::LLVMFuncOp original,
                                DenseI32ArrayAttr members);
  LogicalResult buildRefinement(const GroupRefinement &refinement);
  void selectResiduals();
  LogicalResult materializeValueCalls();
  void publishResiduals();

  ModuleOp module;
  NativeGroupPromotionInputs &inputs;
  NativeGroupPromotionReport &report;
  // Every symbol change goes through `symbols`, so the per-function action
  // lowering reuses the same module table instead of rebuilding it.
  SymbolTableCollection symbolTables;
  SymbolTable &symbols;
  uint64_t operationLimit;
  const GroupPlan plan;
  // The groups to materialize, in order; refinement appends its children.
  SmallVector<LLVM::LLVMFuncOp> worklist;
  // Measure each other needed definition once. Charging its own operations
  // bounds both cloning and subsequent optimization; following shared callees
  // would repeatedly charge the same graph, just as following global
  // initializers did in native partition cost estimation.
  DenseMap<Operation *, uint64_t> costs;
  SmallVector<std::pair<LLVM::LLVMFuncOp, uint64_t>> residuals;
  DenseMap<Operation *, uint64_t> residualBudgets;
  DenseSet<Operation *> whollyOutlinedGroups, finalized, discarded,
      refinedChildren;
  SmallVector<GroupRefinement> refinements;
  // The refinement tree each candidate belongs to, and that tree's remaining
  // operation budget.
  DenseMap<Operation *, unsigned> refinementRoots;
  SmallVector<uint64_t> refinementBudgets;
};

LogicalResult GroupMaterializer::run() {
  // Workers add or remove no symbols until the ordered phase.
  schedule::NativeGlobalLookup globals(symbols);
  SmallVector<PreparedGroup> preparedBodies(plan.independent.size());
  parallelFor(module.getContext(), 0, plan.independent.size(), [&](size_t i) {
    preparedBodies[i] = prepareConcurrently(plan.independent[i], globals);
  });
  DenseMap<Operation *, PreparedGroup> prepared;
  for (auto [i, function] : llvm::enumerate(plan.independent))
    prepared.try_emplace(function, preparedBodies[i]);
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos native group preparation: independent="
                 << plan.independent.size()
                 << " ordered=" << plan.groups.size() - plan.independent.size()
                 << '\n';

  // Refinement appends children. Keep original activation CFGs intact until
  // all candidates have been considered; memory SSA would erase the entry
  // evidence needed to prove a partial split.
  for (size_t index = 0; index < worklist.size(); ++index) {
    auto function = worklist[index];
    if (plan.externallyUsedCandidates.contains(function)) {
      ::talos::schedule::remove<
          ::talos::schedule::Field::EvalDataflowCandidate>(function);
      continue;
    }
    auto found = prepared.find(function);
    PreparedGroup group =
        found != prepared.end() ? found->second : prepare(function);
    // Refinement may erase a candidate and allocate new child functions.
    // Do not retain a consumed operation pointer across that allocation.
    if (found != prepared.end())
      prepared.erase(found);
    if (failed(materializeGroup(function, group)))
      return failure();
  }
  for (auto &refinement : llvm::reverse(refinements))
    if (failed(buildRefinement(refinement)))
      return failure();
  selectResiduals();
  if (failed(materializeValueCalls()))
    return failure();
  publishResiduals();
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos unconditional member publications elided: "
                 << report.elidedUnconditionalPublications << '\n';
  return success();
}

/// Prepare an independent group on a worker: its own body is all it changes.
PreparedGroup GroupMaterializer::prepareConcurrently(
    LLVM::LLVMFuncOp function, const schedule::NativeGlobalLookup &globals) {
  PreparedGroup group;
  DenseMap<Operation *, uint64_t> localCosts;
  group.body = inlineGroupBody(function, symbols, plan.stableCosts, localCosts,
                               operationLimit);
  group.elidedPublications = elideUnconditionalMemberPublications(function);
  FailureOr<NativeFunctionActionLowering> actions =
      lowerNativeFunctionScheduleActions(function, globals);
  group.status = success(succeeded(actions));
  if (succeeded(actions))
    group.actions = *actions;
  return group;
}

/// Prepare a group in order, after the groups it depends on.
PreparedGroup GroupMaterializer::prepare(LLVM::LLVMFuncOp function) {
  PreparedGroup group;
  group.body = inlineGroupBody(function, symbols, plan.stableCosts, costs,
                               operationLimit);
  // Publications to unconditional members that still execute later are
  // redundant. Preserve backward publications inside an SCC for another
  // sweep. The typed actions still name their destination word and bits.
  group.elidedPublications = elideUnconditionalMemberPublications(function);
  // Member effects are now visible in one CFG. Combine semantic readiness
  // reads/updates before expanding indexes.
  group.status = lowerNativeScheduleActionsToLLVM(function, &symbolTables);
  return group;
}

LogicalResult GroupMaterializer::materializeGroup(LLVM::LLVMFuncOp function,
                                                  const PreparedGroup &group) {
  if (failed(group.status))
    return failure();
  // A worker leaves to this ordered turn the action lowering that adds
  // module symbols, and declaring the runtime entry points its lowering
  // calls, so both happen in group order.
  if (group.actions && !group.actions->lowered) {
    if (failed(lowerNativeScheduleActionsToLLVM(function, &symbolTables)))
      return failure();
  } else if (group.actions) {
    declareNativeFunctionActionRuntime(module, *group.actions);
  }
  report.elidedUnconditionalPublications += group.elidedPublications;
  if (auto candidate = ::talos::schedule::get<
          ::talos::schedule::Field::EvalDataflowCandidate>(function)) {
    auto original = symbols.lookup<LLVM::LLVMFuncOp>(candidate.getValue());
    auto members =
        ::talos::schedule::get<::talos::schedule::Field::EvalRankedMembers>(
            function);
    if (original &&
        schedule::get<schedule::Field::EvalGroupProofDomain>(original) !=
            schedule::get<schedule::Field::EvalGroupProofDomain>(function))
      return function.emitError(
                 "candidate and original group proof domains differ"),
             failure();
    bool identitiesValid = isValidCandidate(function, original, members);
    bool accepted = identitiesValid &&
                    materializeNativeGroupDataflow(function, operationLimit);
    if (native::has<native::DebugTiming>(module))
      llvm::errs() << "talos group dataflow: " << function.getSymName()
                   << " accepted=" << accepted << '\n';
    if (accepted)
      return acceptCandidate(function, original, members);
    if (identitiesValid && !native::has<native::TwoState>(module))
      refineOriginal(function, original);
    symbols.erase(function);
    return success();
  }
  // A completely outlined group can still carry current lanes through
  // explicit helper interfaces; zero inlined calls is not an eval exit.
  if (!group.body.materialized && !refinedChildren.contains(function))
    whollyOutlinedGroups.insert(function);
  residuals.emplace_back(function, group.body.remaining);
  residualBudgets[function] = group.body.remaining;
  return success();
}

/// Whether `function` is a candidate for exactly the members, signature and
/// ingress of `original`, with one pending-mask bit per member.
bool GroupMaterializer::isValidCandidate(LLVM::LLVMFuncOp function,
                                         LLVM::LLVMFuncOp original,
                                         DenseI32ArrayAttr members) {
  auto pendingGlobal = symbols.lookup<LLVM::GlobalOp>(
      schedule::getEvalMaskGlobalName(schedule::EvalMask::PromotionPending));
  auto pendingType =
      pendingGlobal
          ? dyn_cast<LLVM::LLVMArrayType>(pendingGlobal.getGlobalType())
          : LLVM::LLVMArrayType{};
  bool identitiesValid =
      original && original != function && !original.empty() &&
      !::talos::schedule::has<::talos::schedule::Field::EvalDataflowCandidate>(
          original) &&
      !::talos::schedule::has<::talos::schedule::Field::EvalDataflowExecutor>(
          original) &&
      members &&
      !::talos::schedule::has<::talos::schedule::Field::EvalDataflowFallback>(
          original) &&
      !members.empty() &&
      original.getFunctionType() == function.getFunctionType() &&
      ::talos::schedule::get<::talos::schedule::Field::EvalRankedMembers>(
          original) == members &&
      ::talos::schedule::get<::talos::schedule::Field::EvalGroupIngress>(
          original) ==
          ::talos::schedule::get<::talos::schedule::Field::EvalGroupIngress>(
              function) &&
      pendingType && pendingType.getElementType().isInteger(64);
  llvm::SmallDenseSet<uint32_t> identities;
  if (identitiesValid)
    for (int32_t owner : members.asArrayRef())
      identitiesValid &= owner >= 0 &&
                         uint32_t(owner) / 64 < pendingType.getNumElements() &&
                         identities.insert(owner).second;
  return identitiesValid;
}

/// Split `original`, whose dataflow candidate `function` was rejected, into
/// children that partition its members, each with its own candidate, sharing
/// one operation budget per refinement tree.
void GroupMaterializer::refineOriginal(LLVM::LLVMFuncOp function,
                                       LLVM::LLVMFuncOp original) {
  auto [root, inserted] =
      refinementRoots.try_emplace(function, refinementBudgets.size());
  if (inserted)
    refinementBudgets.push_back(operationLimit);
  unsigned rootID = root->second;
  auto children = splitNativeEvalGroup(original, function, symbols,
                                       refinementBudgets[rootID]);
  llvm::append_range(worklist, children);
  if (children.empty())
    return;
  refinements.push_back({original, {children[0], children[2]}});
  refinedChildren.insert(children[0]);
  refinedChildren.insert(children[2]);
  for (unsigned i : {1u, 3u})
    refinementRoots[children[i]] = rootID;
}

/// Make the accepted dataflow body of `function` the entry of `original`,
/// guarded by one value-domain check, with the original body as fallback.
LogicalResult GroupMaterializer::acceptCandidate(LLVM::LLVMFuncOp function,
                                                 LLVM::LLVMFuncOp original,
                                                 DenseI32ArrayAttr members) {
  if (native::has<native::TwoState>(module)) {
    // These members execute their canonical bodies in a globally two-state
    // model. The group's live ingress, source order and finite CFG were
    // checked above. There is no value-domain branch or slow copy to keep.
    original.getBody().dropAllReferences();
    original.getBody().takeBody(function.getBody());
    for (auto role : {schedule::Field::EvalMaterializedGroupCalls,
                      schedule::Field::EvalSsaValueRanges,
                      schedule::Field::EvalSsaUnknownRanges,
                      schedule::Field::EvalControlFlowDataflow,
                      schedule::Field::EvalUnconditionalMembers}) {
      if (auto attr = schedule::get<Attribute>(function, role))
        schedule::set(original, role, attr);
      else
        schedule::remove(original, role);
    }
    whollyOutlinedGroups.erase(original);
    symbols.erase(function);
    return success();
  }
  // Promote the slow body before adding its fast guard, so slow-path
  // materialization never introduces loads on a collapsed child's entry.
  if (auto remaining = residualBudgets.find(original);
      remaining != residualBudgets.end()) {
    if (failed(lowerNativeScheduleActionsToLLVM(original, &symbolTables)))
      return failure();
    if (failed(promoteGroupState(original, inputs.globalTypes,
                                 schedule::StatePlane::Value, remaining->second,
                                 inputs.metadataOnly, inputs.callFootprints)) ||
        failed(promoteGroupState(
            original, inputs.globalTypes, schedule::StatePlane::Unknown,
            remaining->second, inputs.metadataOnly, inputs.callFootprints)))
      return failure();
    finalized.insert(original);
  }
  if (schedule::has<schedule::Field::EvalRefreshGroupProofs>(function))
    schedule::set<schedule::Field::EvalRefreshGroupProofs>(
        original, UnitAttr::get(module.getContext()));
  if (refinedChildren.contains(original)) {
    // The parent owns this child's selection point. Keeping another
    // guarded wrapper on the fast path would add a call boundary which
    // physical native partitioning cannot reliably inline away.
    ::talos::schedule::set<::talos::schedule::Field::EvalDataflowExecutor>(
        original, FlatSymbolRefAttr::get(function));
    ::talos::schedule::remove<::talos::schedule::Field::EvalDataflowCandidate>(
        function);
    return success();
  }
  // Make computation the actual group entry before physical partitioning.
  // Keep exactly one copy of each body: the original guarded executor
  // becomes a cold helper, while the finite SSA body moves into the entry.
  // Native partitioning can then split helpers without reintroducing a
  // wrapper call on every known activation.
  Region fallbackBody;
  fallbackBody.takeBody(original.getBody());
  original.getBody().takeBody(function.getBody());
  function.getBody().takeBody(fallbackBody);
  for (auto name : {::talos::schedule::Field::EvalMaterializedGroupCalls,
                    ::talos::schedule::Field::EvalSsaValueRanges,
                    ::talos::schedule::Field::EvalSsaUnknownRanges,
                    ::talos::schedule::Field::EvalControlFlowDataflow,
                    ::talos::schedule::Field::EvalUnconditionalMembers}) {
    Attribute slow = schedule::get<Attribute>(original, name),
              fast = schedule::get<Attribute>(function, name);
    schedule::remove(original, name);
    schedule::remove(function, name);
    if (fast)
      schedule::set(original, name, fast);
    if (slow)
      schedule::set(function, name, slow);
  }
  symbols.remove(function);
  function.setSymName(original.getSymName().str() + ".fallback");
  symbols.insert(function);
  ::talos::schedule::remove<::talos::schedule::Field::EvalDataflowCandidate>(
      function);
  OpBuilder builder(module.getContext());
  Location loc = function.getLoc();
  Block *oldEntry = &original.getBody().front();
  auto *guard = new Block, *fallback = new Block;
  original.getBody().push_front(guard);
  original.getBody().push_back(fallback);
  for (BlockArgument argument : oldEntry->getArguments())
    guard->addArgument(argument.getType(), argument.getLoc());
  builder.setInsertionPointToStart(guard);
  unsigned width = 64;
  for (int32_t owner : members.asArrayRef())
    width = std::max(width, unsigned(owner) + 1);
  APInt mask(width, 0);
  for (int32_t owner : members.asArrayRef())
    mask.setBit(owner);
  SmallVector<std::pair<unsigned, uint64_t>> masks;
  for (unsigned word = 0; word < mask.getNumWords(); ++word) {
    uint64_t bits = ownerMaskWord(mask, word);
    if (bits)
      masks.emplace_back(word, bits);
  }
  // One value-domain check for the whole computation. Refresh
  // unqueried certificates before treating a pending bit as unknown. A
  // failed proof retains the ordinary per-member path, allowing the
  // unaffected members to remain two-state. Activation predicates are
  // still evaluated inside the dataflow body; no cached coherence fact
  // can be invalidated by a known VPI deposit.
  if (failed(emitGroupDomainGuard(
          builder, loc, masks, symbols,
          schedule::has<schedule::Field::EvalRefreshGroupProofs>(original),
          schedule::get<schedule::Field::EvalGroupProofDomain>(original),
          oldEntry, guard->getArguments(), fallback)))
    return failure();
  builder.setInsertionPointToStart(fallback);
  LLVM::CallOp::create(builder, loc, TypeRange{}, function.getSymName(),
                       guard->getArguments());
  LLVM::ReturnOp::create(builder, loc, ValueRange{});
  ::talos::schedule::set<::talos::schedule::Field::EvalDataflowFallback>(
      original, FlatSymbolRefAttr::get(function));
  return success();
}

/// Replace the body of a refined parent with its children in member order,
/// or discard the children when none of them collapsed.
LogicalResult
GroupMaterializer::buildRefinement(const GroupRefinement &refinement) {
  bool useful = llvm::any_of(refinement.children, [](auto child) {
    return ::talos::schedule::has<
               ::talos::schedule::Field::EvalDataflowExecutor>(child) ||
           ::talos::schedule::has<::talos::schedule::Field::EvalGroupChildren>(
               child);
  });
  if (!useful) {
    for (auto child : refinement.children) {
      discarded.insert(child);
      symbols.erase(child);
    }
    return success();
  }
  // Children partition the original ordered leaf identities. A parent adds
  // no readiness bits, domain guard, or event queue. Backward publications
  // survive child return for the shared loop (IEEE 1800-2023 4.4--4.7).
  auto parent = refinement.parent;
  parent.getBody().dropAllReferences();
  parent.getBody().getBlocks().clear();
  OpBuilder builder(module.getContext());
  Block *entry = parent.addEntryBlock(builder);
  builder.setInsertionPointToStart(entry);
  auto ingress =
      ::talos::schedule::get<::talos::schedule::Field::EvalGroupIngress>(
          parent);
  SmallVector<Attribute> references;
  for (auto child : refinement.children) {
    references.push_back(FlatSymbolRefAttr::get(child));
    // Enter a collapsed child only when it owns pending work: its guard and
    // proof refresh cost more than skipping an inactive child.
    // Reacquire after each child: an earlier child can publish a later one.
    std::map<unsigned, uint64_t> masks;
    for (int32_t owner :
         ::talos::schedule::get<::talos::schedule::Field::EvalRankedMembers>(
             child)
             .asArrayRef())
      masks[unsigned(owner) / 64] |= uint64_t{1} << (unsigned(owner) % 64);
    Value pending =
        llvmConstant(builder, parent.getLoc(), builder.getI64Type(), 0);
    for (auto [word, mask] : masks) {
      Value bits = LLVM::AndOp::create(
          builder, parent.getLoc(),
          schedule::NativeReadyWordLoadOp::create(
              builder, parent.getLoc(), builder.getI64Type(), ingress,
              /*dynamic_word=*/Value{}, builder.getI64IntegerAttr(word),
              /*activation_entry=*/IntegerAttr{}, /*owner=*/IntegerAttr{}),
          llvmConstant(builder, parent.getLoc(), builder.getI64Type(), mask));
      pending = LLVM::OrOp::create(builder, parent.getLoc(), pending, bits);
    }
    Value active = LLVM::ICmpOp::create(
        builder, parent.getLoc(), LLVM::ICmpPredicate::ne, pending,
        llvmConstant(builder, parent.getLoc(), builder.getI64Type(), 0));
    auto *execute = new Block, *next = new Block;
    parent.getBody().push_back(execute);
    parent.getBody().push_back(next);
    LLVM::CondBrOp::create(builder, parent.getLoc(), active, execute,
                           ValueRange{}, next, ValueRange{});
    builder.setInsertionPointToStart(execute);
    if (auto fast = ::talos::schedule::get<
            ::talos::schedule::Field::EvalDataflowExecutor>(child)) {
      auto *collapsed = new Block, *fallback = new Block;
      parent.getBody().push_back(collapsed);
      parent.getBody().push_back(fallback);
      SmallVector<std::pair<unsigned, uint64_t>> domains(masks.begin(),
                                                         masks.end());
      if (failed(emitGroupDomainGuard(
              builder, parent.getLoc(), domains, symbols,
              schedule::has<schedule::Field::EvalRefreshGroupProofs>(child),
              schedule::get<schedule::Field::EvalGroupProofDomain>(child),
              collapsed, {}, fallback)))
        return failure();
      builder.setInsertionPointToStart(collapsed);
      LLVM::CallOp::create(builder, parent.getLoc(), TypeRange{},
                           fast.getValue(), entry->getArguments());
      LLVM::BrOp::create(builder, parent.getLoc(), ValueRange{}, next);
      builder.setInsertionPointToStart(fallback);
    }
    LLVM::CallOp::create(builder, parent.getLoc(), TypeRange{},
                         child.getSymName(), entry->getArguments());
    LLVM::BrOp::create(builder, parent.getLoc(), ValueRange{}, next);
    builder.setInsertionPointToStart(next);
  }
  LLVM::ReturnOp::create(builder, parent.getLoc(), ValueRange{});
  ::talos::schedule::set<::talos::schedule::Field::EvalGroupChildren>(
      parent, builder.getArrayAttr(references));
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos group hierarchy: " << parent.getSymName()
                 << " children=" << refinement.children.size() << '\n';
  return success();
}

/// The functions left for residual promotion: ordinary groups that were
/// neither refined, discarded nor promoted with their candidate, and the
/// raw-capture functions outside groups.
void GroupMaterializer::selectResiduals() {
  // Group refinement and symbol creation are complete. Residual promotion
  // only rewrites its own function and reads globals through a frozen table.
  llvm::erase_if(residuals, [&](const auto &residual) {
    auto function = residual.first;
    return discarded.contains(function) || finalized.contains(function) ||
           ::talos::schedule::has<::talos::schedule::Field::EvalGroupChildren>(
               function);
  });
  // A canonical output need not be globally private to keep its intermediate
  // contents in SSA during a native activation. Transition/knownness actions
  // have already been materialized; their ordered notifications are retained.
  // The access inventory flushes at every opaque alias, observer call and exit
  // (LRM 4.3, 4.6, 9.4.2). Like group dataflow candidates, this retains
  // loops/branches.
  for (auto function : module.getOps<LLVM::LLVMFuncOp>())
    if (!function.isExternal() &&
        schedule::has<schedule::Field::EvalRawCaptures>(function) &&
        !schedule::has<schedule::Field::EvalRankedMembers>(function))
      residuals.emplace_back(function, operationLimit);
}

/// Rewrite the residual functions' calls of closed value helpers to carry
/// current lanes as arguments and results, then drop the completely
/// outlined groups no such call changed.
LogicalResult GroupMaterializer::materializeValueCalls() {
  DenseSet<Operation *> valueCallers;
  if (failed(
          materializeNativeEvalValueCalls(module, residuals, inputs.globalTypes,
                                          inputs.callFootprints, valueCallers)))
    return failure();
  // Retain the original ready-word representation when no computation was
  // exposed. Promoting readiness alone can add spills without avoiding any
  // state round trip in a completely outlined group.
  llvm::erase_if(residuals, [&](const auto &residual) {
    return whollyOutlinedGroups.contains(residual.first) &&
           !valueCallers.contains(residual.first);
  });
  return success();
}

/// Hand the residuals and the final call footprints to the function-local
/// promotion pass.
void GroupMaterializer::publishResiduals() {
  // Value cores and their canonical wrappers have different footprints. Freeze
  // the new complete closure before any function-local promotion worker runs.
  inputs.callFootprints = buildNativeStateFootprints(module, inputs.globalTypes,
                                                     inputs.metadataOnly);
  report.diagnostics.resize(residuals.size());
  for (auto [index, residual] : llvm::enumerate(residuals))
    inputs.residuals.try_emplace(residual.first,
                                 std::make_pair(residual.second, index));
}
} // namespace

/// Materialize certified activation bodies before native partitioning. The
/// original pending bits, source predicates, and boundary exits remain the
/// schedule. Only an explicit source proof of inert redundant evaluation may
/// remove an activation predicate (IEEE 1800-2023 4.3--4.7).
///
/// Route specialization must run first. A durable two-state certificate then
/// exposes a direct body; an unresolved route remains an executor boundary.
/// In particular, do not select a two-state callee just because it appears in
/// an indirect call's allowed-callee inventory.
FailureOr<std::shared_ptr<NativeGroupPromotionReport>>
materializeNativeEvalGroupBodies(ModuleOp module, AnalysisManager manager) {
  auto report = std::make_shared<NativeGroupPromotionReport>();
  auto &inputs = manager.getAnalysis<NativeGroupPromotionInputs>();
  inputs.report = report;
  DialectRegistry registry;
  LLVM::registerInlinerInterface(registry);
  module.getContext()->appendDialectRegistry(registry);
  GroupMaterializer materializer(module, inputs, *report);
  if (failed(materializer.run()))
    return failure();
  return report;
}

std::unique_ptr<Pass> createPromoteNativeGroupFunctionPass() {
  return std::make_unique<PromoteNativeGroupFunctionPass>();
}

} // namespace talos::detail

namespace talos {
#define GEN_PASS_DEF_MATERIALIZETALOSNATIVEEVALGROUPSPASS
#include "talos/Conversion/Passes.h.inc"

namespace {
struct MaterializeTalosNativeEvalGroupsPass
    : impl::MaterializeTalosNativeEvalGroupsPassBase<
          MaterializeTalosNativeEvalGroupsPass> {
  using MaterializeTalosNativeEvalGroupsPassBase::
      MaterializeTalosNativeEvalGroupsPassBase;

  void runOnOperation() override {
    auto report = detail::materializeNativeEvalGroupBodies(
        getOperation(), getAnalysisManager());
    if (failed(report))
      return signalPassFailure();
    if (!(*report)->diagnostics.empty()) {
      OpPassManager functions(ModuleOp::getOperationName());
      functions.nest<LLVM::LLVMFuncOp>().addPass(
          detail::createPromoteNativeGroupFunctionPass());
      if (failed(runPipeline(functions, getOperation())))
        return signalPassFailure();
    }
    for (const auto &diagnostic : (*report)->diagnostics)
      llvm::errs() << diagnostic;
  }
};
} // namespace
} // namespace talos
