#include "mlir/Analysis/SliceAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/Transforms/NativeTransforms.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/MapVector.h"

using namespace mlir;
namespace talos::schedule {
namespace {
std::optional<unsigned> cacheWidth(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.getWidth() <= 256 ? std::optional(integer.getWidth())
                                     : std::nullopt;
  auto structure = dyn_cast<LLVM::LLVMStructType>(type);
  if (!structure || structure.isOpaque())
    return std::nullopt;
  unsigned width = 0;
  for (Type field : structure.getBody()) {
    auto integer = dyn_cast<IntegerType>(field);
    if (!integer || integer.getWidth() > 256 - width)
      return std::nullopt;
    width += integer.getWidth();
  }
  return width ? std::optional(width) : std::nullopt;
}
bool isDeterministicValueOp(Operation *op) {
  return op->getNumRegions() == 0 && isMemoryEffectFree(op) &&
         isSpeculatable(op) &&
         !isa<LLVM::UndefOp, LLVM::PoisonOp, LLVM::FreezeOp>(op) &&
         llvm::all_of(op->getResultTypes(),
                      [](Type type) { return cacheWidth(type).has_value(); });
}
// Keep an existing value helper's ABI and cache the complete function.
bool isAlreadyPure(LLVM::LLVMFuncOp function) {
  return !function
              .walk([&](Operation *op) {
                return op != function &&
                               !op->hasTrait<OpTrait::IsTerminator>() &&
                               !isDeterministicValueOp(op)
                           ? WalkResult::interrupt()
                           : WalkResult::advance();
              })
              .wasInterrupted();
}
// Outline at uses that must execute: loads and publications stay in the
// caller; the helper receives their already captured SSA snapshots.
llvm::SetVector<Value> coneRoots(Block &block) {
  llvm::SetVector<Value> roots;
  for (Operation &op : block)
    if (!isDeterministicValueOp(&op) || op.hasTrait<OpTrait::IsTerminator>())
      for (Value value : op.getOperands())
        if (cacheWidth(value.getType()))
          roots.insert(value);
  return roots;
}
// The closed pure computation of `block` that `root` would be outlined from,
// and its inputs.
struct PureCone {
  llvm::SetVector<Operation *> slice;
  llvm::SetVector<Value> inputs;
};
std::optional<PureCone> findCone(Block &block, Value root, uint64_t minimumCost,
                                 uint64_t maximumCost) {
  Operation *definition = root.getDefiningOp();
  if (!definition || definition->getBlock() != &block ||
      !isDeterministicValueOp(definition) || !cacheWidth(root.getType()))
    return std::nullopt;
  PureCone cone;
  llvm::SetVector<Operation *> &slice = cone.slice;
  BackwardSliceOptions options;
  options.inclusive = true;
  options.omitBlockArguments = true;
  options.filter = [&](Operation *op) {
    return op->getBlock() == &block && isDeterministicValueOp(op);
  };
  if (failed(getBackwardSlice(definition, &slice, options)) ||
      slice.size() < minimumCost || slice.size() > maximumCost)
    return std::nullopt;
  llvm::SetVector<Value> &inputs = cone.inputs;
  bool closed = true;
  for (Operation *op : slice) {
    for (Value operand : op->getOperands())
      if (!slice.contains(operand.getDefiningOp()))
        inputs.insert(operand);
    for (Value result : op->getResults())
      if (result != root &&
          llvm::any_of(result.getUsers(),
                       [&](Operation *user) { return !slice.contains(user); }))
        closed = false;
  }
  unsigned inputBits = 0;
  for (Value input : inputs) {
    auto width = cacheWidth(input.getType());
    if (!width || *width > 256 - inputBits) {
      closed = false;
      break;
    }
    inputBits += *width;
  }
  if (!closed || inputs.empty() || inputs.size() > 4)
    return std::nullopt;
  return cone;
}
unsigned outlineCones(ModuleOp module, uint64_t minimumCost,
                      uint64_t maximumCost, unsigned maximumCones) {
  SmallVector<LLVM::LLVMFuncOp> functions(module.getOps<LLVM::LLVMFuncOp>());
  // Outlining changes only its own function and adds helpers. Find, without
  // changing IR, the functions that have a cone to outline; the serial pass
  // below revisits only those, in order.
  SmallVector<char> hasCone(functions.size(), false);
  analysis::parallelForChunked(
      module.getContext(), functions.size(), [&](size_t index) {
        LLVM::LLVMFuncOp function = functions[index];
        if (function.isExternal() || isAlreadyPure(function))
          return;
        for (Block &block : function.getBody())
          for (Value root : coneRoots(block))
            if (findCone(block, root, minimumCost, maximumCost)) {
              hasCone[index] = true;
              return;
            }
      });
  SymbolTable symbols(module);
  unsigned outlined = 0;
  for (auto [index, function] : llvm::enumerate(functions)) {
    if (function.isExternal() || function->hasAttr("schedule.pure_cache") ||
        function->hasAttr("schedule.pure_cone"))
      continue;
    if (!hasCone[index] || isAlreadyPure(function))
      continue;
    for (Block &block : function.getBody()) {
      llvm::SetVector<Value> roots = coneRoots(block);
      for (Value root : roots) {
        if (outlined == maximumCones)
          return outlined;
        std::optional<PureCone> cone =
            findCone(block, root, minimumCost, maximumCost);
        if (!cone)
          continue;
        Operation *definition = root.getDefiningOp();
        llvm::SetVector<Operation *> &slice = cone->slice;
        llvm::SetVector<Value> &inputs = cone->inputs;
        OpBuilder builder(module.getContext());
        builder.setInsertionPointAfter(function);
        SmallVector<Type> types;
        for (Value input : inputs)
          types.push_back(input.getType());
        auto helper = LLVM::LLVMFuncOp::create(
            builder, definition->getLoc(),
            (function.getSymName() + ".__talos_pure_cone").str(),
            LLVM::LLVMFunctionType::get(root.getType(), types));
        symbols.insert(helper);
        helper.setLinkage(LLVM::Linkage::Internal);
        helper->setAttr("schedule.pure_cone", builder.getUnitAttr());
        helper->setAttr(
            "passthrough",
            builder.getArrayAttr({builder.getStringAttr("noinline")}));
        if (StringAttr partition = native::get<native::Partition>(function))
          native::set<native::Partition>(helper, partition);
        Block *entry = helper.addEntryBlock(builder);
        IRMapping mapping;
        for (auto [input, argument] :
             llvm::zip_equal(inputs, entry->getArguments()))
          mapping.map(input, argument);
        builder.setInsertionPointToStart(entry);
        for (Operation *op : slice)
          builder.clone(*op, mapping);
        LLVM::ReturnOp::create(builder, definition->getLoc(),
                               mapping.lookup(root));
        builder.setInsertionPoint(definition);
        Value replacement = LLVM::CallOp::create(builder, definition->getLoc(),
                                                 helper, inputs.getArrayRef())
                                .getResult();
        root.replaceAllUsesWith(replacement);
        for (Operation *op : llvm::reverse(slice))
          op->erase();
        ++outlined;
      }
    }
  }
  return outlined;
}
void cacheFunction(ModuleOp module, LLVM::LLVMFuncOp function,
                   ArrayRef<unsigned> keys) {
  auto loc = function.getLoc();
  auto ctx = module.getContext();
  OpBuilder builder(ctx);
  auto ptr = LLVM::LLVMPointerType::get(ctx);
  auto resultType = function.getFunctionType().getReturnType();
  SmallVector<Type> fields{builder.getI1Type(), resultType};
  auto &original = function.getBody().front();
  for (unsigned key : keys)
    fields.push_back(original.getArgument(key).getType());
  auto cacheType = LLVM::LLVMStructType::getLiteral(ctx, fields);
  SymbolTable symbols(module);
  builder.setInsertionPointToStart(module.getBody());
  auto global = LLVM::GlobalOp::create(
      builder, loc, cacheType, false, LLVM::Linkage::Internal,
      ("__talos_pure_cache." + function.getSymName()).str(), Attribute{}, 8, 0,
      false, /*thread_local_=*/true);
  symbols.insert(global);
  if (StringAttr partition = native::get<native::Partition>(function))
    native::set<native::Partition>(global, partition);
  global.getInitializerRegion().push_back(new Block);
  builder.setInsertionPointToStart(&global.getInitializerRegion().front());
  Value empty = LLVM::ZeroOp::create(builder, loc, cacheType);
  LLVM::ReturnOp::create(builder, loc, empty);

  SmallVector<LLVM::ReturnOp> returns;
  function.walk([&](LLVM::ReturnOp op) { returns.push_back(op); });
  Block *entry = new Block;
  Block *hit = new Block;
  function.getBody().push_front(entry);
  function.getBody().push_back(hit);
  for (auto argument : original.getArguments())
    entry->addArgument(argument.getType(), argument.getLoc());
  builder.setInsertionPointToStart(entry);
  Value address = LLVM::AddressOfOp::create(builder, loc, global);
  auto fieldAddress = [&](unsigned field) -> Value {
    return LLVM::GEPOp::create(builder, loc, ptr, cacheType, address,
                               ArrayRef<LLVM::GEPArg>{0, int32_t(field)});
  };
  Value validAddress = fieldAddress(0);
  Value resultAddress = fieldAddress(1);
  Value match =
      LLVM::LoadOp::create(builder, loc, builder.getI1Type(), validAddress);
  SmallVector<Value> keyAddresses;
  SmallVector<Value> arguments(entry->getArguments());
  for (auto [index, key] : llvm::enumerate(keys)) {
    Value keyAddress = fieldAddress(index + 2);
    keyAddresses.push_back(keyAddress);
    // LLVM poison/undef inputs must not become a new immediate-UB branch.
    // Freeze keys once and use those same snapshots in the miss computation.
    // Concrete simulation values are unchanged; unspecified LLVM values are
    // refined consistently rather than sampled differently by the cache.
    Value value = LLVM::FreezeOp::create(builder, loc, entry->getArgument(key));
    arguments[key] = value;
    Value previous =
        LLVM::LoadOp::create(builder, loc, value.getType(), keyAddress);
    auto compare = [&](Value lhs, Value rhs) {
      Value same =
          LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::eq, lhs, rhs);
      match = LLVM::AndOp::create(builder, loc, match, same);
    };
    if (auto structure = dyn_cast<LLVM::LLVMStructType>(value.getType())) {
      // Packed logic keys include both planes. A known-to-X change must miss
      // even if the value plane did not change.
      for (auto [field, type] : llvm::enumerate(structure.getBody())) {
        Value lhs = LLVM::ExtractValueOp::create(
            builder, loc, previous, ArrayRef<int64_t>{int64_t(field)});
        Value rhs = LLVM::ExtractValueOp::create(
            builder, loc, value, ArrayRef<int64_t>{int64_t(field)});
        compare(lhs, rhs);
      }
    } else
      compare(previous, value);
  }
  LLVM::CondBrOp::create(builder, loc, match, hit, ValueRange{}, &original,
                         arguments);
  builder.setInsertionPointToStart(hit);
  Value cached = LLVM::LoadOp::create(builder, loc, resultType, resultAddress);
  LLVM::ReturnOp::create(builder, loc, cached);
  for (auto returned : returns) {
    builder.setInsertionPoint(returned);
    Value result = LLVM::FreezeOp::create(builder, loc, returned.getArg());
    for (auto [index, key] : llvm::enumerate(keys))
      LLVM::StoreOp::create(builder, loc, arguments[key], keyAddresses[index]);
    LLVM::StoreOp::create(builder, loc, result, resultAddress);
    returned->setOperand(0, result);
    Value valid = LLVM::ConstantOp::create(builder, loc, builder.getI1Type(),
                                           builder.getBoolAttr(true));
    LLVM::StoreOp::create(builder, loc, valid, validAddress);
  }
  function->setAttr("schedule.pure_cache",
                    builder.getDenseI32ArrayAttr(
                        SmallVector<int32_t>(keys.begin(), keys.end())));
}
} // namespace
// Partitioned native codegen optimizes each owner's LLVM separately. Give
// repeated direct calls with the same constant controls a common body in
// their caller's partition. The original ABI handles all other arguments.
// Preserve both planes of each by-value argument (IEEE 1800-2023 6.11.2,
// 13.5.1), including a dynamic unknown plane alongside a constant value.
void specializeNativeValueFunctions(ModuleOp module) {
  if (!native::has<native::ClosedExecutable>(module))
    return;
  using Key = std::tuple<Operation *, StringAttr, ArrayAttr>;
  llvm::MapVector<Key, SmallVector<LLVM::CallOp>> groups;
  SymbolTable symbols(module);
  Builder attrs(module.getContext());
  for (auto caller : module.getOps<LLVM::LLVMFuncOp>()) {
    auto partition = native::get<native::Partition>(caller);
    if (!partition || caller.isExternal())
      continue;
    caller.walk([&](LLVM::CallOp call) {
      auto name = call.getCallee();
      auto callee =
          name ? symbols.lookup<LLVM::LLVMFuncOp>(*name) : LLVM::LLVMFuncOp{};
      auto kind =
          callee ? native::get<native::EntryKind>(callee) : IntegerAttr{};
      if (!callee || callee.isExternal() || !callee.isPrivate() || !kind ||
          kind.getInt() != static_cast<unsigned>(sim::EntryKind::Function) ||
          native::get<native::Partition>(callee) == partition ||
          callee.getFunctionType().isVarArg() ||
          !cacheWidth(callee.getFunctionType().getReturnType()) ||
          callee.getNumArguments() != call.getArgOperands().size())
        return;
      SmallVector<Attribute> constants;
      bool specializes = false;
      for (auto [formal, actual] :
           llvm::zip_equal(callee.getBody().front().getArguments(),
                           call.getArgOperands())) {
        APInt value;
        auto type = dyn_cast<IntegerType>(actual.getType());
        if (!formal.use_empty() && type && type.getWidth() <= 16 &&
            matchPattern(actual, m_ConstantInt(&value))) {
          constants.push_back(attrs.getIntegerAttr(type, value));
          specializes = true;
        } else {
          constants.push_back(attrs.getUnitAttr());
        }
      }
      if (specializes)
        groups[{callee, partition, attrs.getArrayAttr(constants)}].push_back(
            call);
    });
  }
  // Bound cloned IR independently of the number of elaborated instances.
  // Reserve specialization for nontrivial arithmetic that normal local
  // inlining cannot see across an owner boundary.
  constexpr unsigned maxBody = 512, maxAdditionalOps = 8192;
  unsigned added = 0, copies = 0, rewritten = 0;
  DenseMap<Operation *, unsigned> costs;
  for (auto &[key, calls] : groups) {
    if (calls.size() < 2)
      continue;
    auto [owner, partition, constants] = key;
    auto function = cast<LLVM::LLVMFuncOp>(owner);
    auto [pos, inserted] = costs.try_emplace(owner);
    if (inserted) {
      unsigned cost = 0;
      WalkResult checked = function.walk([&](Operation *op) {
        if (op == function || op->hasTrait<OpTrait::IsTerminator>())
          return WalkResult::advance();
        ++cost;
        // The call still executes in place. In particular, a poison
        // aggregate filled by insertvalue or a freeze is evaluated afresh
        // at every call. The stronger memoization test stays separate.
        return cost <= maxBody &&
                       (isDeterministicValueOp(op) ||
                        isa<LLVM::PoisonOp, LLVM::UndefOp, LLVM::FreezeOp>(op))
                   ? WalkResult::advance()
                   : WalkResult::interrupt();
      });
      if (!checked.wasInterrupted() && cost >= 32)
        pos->second = cost;
    }
    unsigned cost = pos->second;
    if (!cost || cost > maxAdditionalOps - added)
      continue;
    auto clone = cast<LLVM::LLVMFuncOp>(function->clone());
    clone.setSymName((function.getSymName() + ".__talos_const").str());
    clone.setLinkage(LLVM::Linkage::Internal);
    native::set<native::Partition>(clone, partition);
    auto name = symbols.insert(clone, std::next(function->getIterator()));
    OpBuilder builder = OpBuilder::atBlockBegin(&clone.getBody().front());
    for (auto [arg, constant] :
         llvm::zip_equal(clone.getBody().front().getArguments(), constants))
      if (auto value = dyn_cast<IntegerAttr>(constant))
        arg.replaceAllUsesWith(LLVM::ConstantOp::create(builder, clone.getLoc(),
                                                        arg.getType(), value));
    for (LLVM::CallOp call : calls)
      call.setCalleeAttr(FlatSymbolRefAttr::get(name));
    added += cost;
    ++copies;
    rewritten += calls.size();
  }
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos constant value functions: copies=" << copies
                 << " calls=" << rewritten << '\n';
}

void cacheNativePureCones(ModuleOp module, uint64_t minimumCost,
                          uint64_t maximumCost, unsigned maximumCaches) {
  unsigned outlined =
      outlineCones(module, minimumCost, maximumCost, maximumCaches);
  SmallVector<std::pair<LLVM::LLVMFuncOp, SmallVector<unsigned>>> candidates;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>()) {
    if (candidates.size() >= maximumCaches)
      break;
    if (function.isExternal() ||
        function.getLinkage() != LLVM::Linkage::Internal ||
        function->hasAttr("schedule.pure_cache") ||
        function.getFunctionType().isVarArg() ||
        !cacheWidth(function.getFunctionType().getReturnType()))
      continue;
    SmallVector<unsigned> keys;
    unsigned keyWidth = 0;
    bool eligible = true;
    for (auto [index, argument] :
         llvm::enumerate(function.getBody().front().getArguments())) {
      if (argument.use_empty())
        continue;
      auto width = cacheWidth(argument.getType());
      if (!width || *width > 256 - keyWidth) {
        eligible = false;
        break;
      }
      keyWidth += *width;
      keys.push_back(index);
    }
    if (!eligible || keys.empty() || keys.size() > 4)
      continue;
    uint64_t cost = 0;
    function.walk([&](Operation *op) {
      if (op == function || isa<LLVM::ReturnOp, LLVM::BrOp, LLVM::CondBrOp,
                                cf::BranchOp, cf::CondBranchOp>(op))
        return;
      // Undef/freeze and hidden globals are not deterministic input functions.
      // State loads, calls, publications and callbacks always stay outside.
      if (!isDeterministicValueOp(op))
        eligible = false;
      ++cost;
    });
    if (eligible && cost >= minimumCost && cost <= maximumCost)
      candidates.emplace_back(function, std::move(keys));
  }
  for (auto &[function, keys] : candidates)
    cacheFunction(module, function, keys);
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos pure cones: outlined=" << outlined
                 << " cached=" << candidates.size() << '\n';
}
} // namespace talos::schedule

namespace talos {
#define GEN_PASS_DEF_CACHENATIVEPURECONESPASS
#include "talos/Dialect/Schedule/Transforms/Passes.h.inc"
namespace {
struct CacheNativePureConesPass
    : impl::CacheNativePureConesPassBase<CacheNativePureConesPass> {
  using CacheNativePureConesPassBase::CacheNativePureConesPassBase;
  void runOnOperation() override {
    schedule::cacheNativePureCones(getOperation(), minimumCost, maximumCost,
                                   maximumCaches);
  }
};
} // namespace
} // namespace talos
