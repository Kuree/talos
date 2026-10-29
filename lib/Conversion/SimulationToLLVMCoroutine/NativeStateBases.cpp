//===- NativeStateBases.cpp - Address native state through one base -------===//
//
// Native state lives in one internal global per plane. Loading each plane's
// address once keeps accesses as GEPs off a shared base rather than constant
// expressions that code generation rematerializes in each block. These opaque
// pointer loads lose the original global's alias identity, so record that the
// two physical plane allocations are separate storage. Single-block functions
// keep direct addresses, and coroutines do not carry a base across suspension.
//
//===----------------------------------------------------------------------===//

#include "talos/Conversion/SimulationToLLVMCoroutine.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/Support/Error.h"

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_ADDRESSNATIVESTATETHROUGHBASESPASS
#include "talos/Conversion/Passes.h.inc"

namespace {
struct StateBase {
  StringAttr name;
  uint64_t bytes;
};

/// Only bounded integer accesses rooted in the physical plane qualify. In
/// particular an arbitrary pointer or unknown offset acquires no promise.
/// The scopes do not separate overlapping SV subviews within one plane.
static StringAttr
boundedStatePlane(Value address, uint64_t bytes,
                  const DenseMap<StringAttr, StateBase> &bases,
                  unsigned indexBits, unsigned pointerBits) {
  auto pointer = dyn_cast<LLVM::LLVMPointerType>(address.getType());
  if (!pointer || pointer.getAddressSpace() != 0)
    return {};
  uint64_t offset = 0;
  StringAttr plane;
  while (Operation *operation = address.getDefiningOp()) {
    if (auto gep = dyn_cast<LLVM::GEPOp>(operation)) {
      // Narrow GEP arithmetic can wrap only the low part of a pointer. An
      // offset bound alone is insufficient without a base-alignment proof.
      if (indexBits != pointerBits || !gep.getElemType().isInteger(8) ||
          gep.getRawConstantIndices().size() != 1)
        return {};
      APInt index;
      if (gep.getDynamicIndices().empty())
        index = APInt(32, gep.getRawConstantIndices().front(), true);
      else if (gep.getDynamicIndices().size() != 1 ||
               !matchPattern(gep.getDynamicIndices().front(),
                             m_ConstantInt(&index)))
        return {};
      if (index.isNegative() || index.getActiveBits() > 64 ||
          index.getSignificantBits() > indexBits)
        return {};
      uint64_t next = index.getZExtValue();
      if (next > UINT64_MAX - offset)
        return {};
      offset += next;
      uint64_t maximum = indexBits >= 64 ? UINT64_MAX >> 1
                                         : (uint64_t{1} << (indexBits - 1)) - 1;
      if (offset > maximum)
        return {};
      address = gep.getBase();
    } else if (auto cast = dyn_cast<LLVM::BitcastOp>(operation)) {
      address = cast.getArg();
    } else if (auto global = dyn_cast<LLVM::AddressOfOp>(operation)) {
      plane = global.getGlobalNameAttr().getAttr();
      break;
    } else if (auto load = dyn_cast<LLVM::LoadOp>(operation)) {
      auto slot = load.getAddr().getDefiningOp<LLVM::AddressOfOp>();
      if (!slot)
        return {};
      for (const auto &[candidate, base] : bases)
        if (base.name == slot.getGlobalNameAttr().getAttr()) {
          plane = candidate;
          break;
        }
      break;
    } else {
      return {};
    }
  }
  auto found = bases.find(plane);
  if (found == bases.end() || offset > found->second.bytes ||
      bytes > found->second.bytes - offset)
    return {};
  return plane;
}

static void appendScopes(LLVM::AliasAnalysisOpInterface operation,
                         ArrayRef<Attribute> scopes, bool noAlias) {
  ArrayAttr old = noAlias ? operation.getNoAliasScopesOrNull()
                          : operation.getAliasScopesOrNull();
  SmallVector<Attribute> combined;
  if (old)
    llvm::append_range(combined, old);
  for (Attribute scope : scopes)
    if (!llvm::is_contained(combined, scope))
      combined.push_back(scope);
  auto attributes = ArrayAttr::get(operation->getContext(), combined);
  if (noAlias)
    operation.setNoAliasScopes(attributes);
  else
    operation.setAliasScopes(attributes);
}

/// Carry the existing metadata-only proof through LLVM translation and native
/// partitioning. Publication remains an ordered, side-effecting call; only
/// its exclusion from the physical value/X/Z planes is stated. This retains
/// the state updates and observations required by LRM 4.6 and 6.3.1.
static void
annotateStateMetadataCalls(LLVM::LLVMFuncOp function,
                           const DenseSet<StringAttr> &metadataOnly,
                           const DenseMap<StringAttr, StateBase> &bases,
                           unsigned indexBits, unsigned pointerBits) {
  SmallVector<LLVM::CallOp> calls;
  function.walk([&](LLVM::CallOp call) {
    if (call.getCallee() && metadataOnly.contains(StringAttr::get(
                                function.getContext(), *call.getCallee())))
      calls.push_back(call);
  });
  if (calls.empty())
    return;
  SmallVector<std::pair<Operation *, StringAttr>> accesses;
  function.walk([&](Operation *operation) {
    Value address;
    Type type;
    if (auto load = dyn_cast<LLVM::LoadOp>(operation)) {
      address = load.getAddr();
      type = load.getType();
    } else if (auto store = dyn_cast<LLVM::StoreOp>(operation)) {
      address = store.getAddr();
      type = store.getValue().getType();
    }
    auto integer = dyn_cast_or_null<IntegerType>(type);
    if (!integer)
      return;
    uint64_t bytes = (uint64_t(integer.getWidth()) + 7) / 8;
    if (StringAttr plane =
            boundedStatePlane(address, bytes, bases, indexBits, pointerBits))
      accesses.emplace_back(operation, plane);
  });
  if (accesses.empty())
    return;
  Builder builder(function.getContext());
  // String identities keep this late pass deterministic and idempotent.
  // The scopes describe global physical storage, not dynamic stack objects.
  auto domain = LLVM::AliasScopeDomainAttr::get(
      function.getContext(),
      builder.getStringAttr("talos.state_metadata." +
                            function.getSymName().str()),
      builder.getStringAttr("native state versus proof metadata"));
  DenseMap<StringAttr, Attribute> byPlane;
  SmallVector<Attribute, 2> scopes;
  for (StringRef name : {"__talos_state_value", "__talos_state_unknown"}) {
    auto key = builder.getStringAttr(name);
    if (!bases.contains(key))
      continue;
    auto scope =
        LLVM::AliasScopeAttr::get(function.getContext(), key, domain, key);
    byPlane[key] = scope;
    scopes.push_back(scope);
  }
  for (auto [operation, plane] : accesses)
    appendScopes(cast<LLVM::AliasAnalysisOpInterface>(operation),
                 {byPlane.lookup(plane)}, false);
  for (LLVM::CallOp call : calls)
    appendScopes(cast<LLVM::AliasAnalysisOpInterface>(call.getOperation()),
                 scopes, true);
}
} // namespace

LogicalResult addressNativeStateThroughBases(ModuleOp module) {
  static constexpr StringLiteral planes[] = {"__talos_state_value",
                                             "__talos_state_unknown"};
  MLIRContext *context = module.getContext();
  SymbolTable symbols(module);
  OpBuilder builder(context);
  auto pointer = LLVM::LLVMPointerType::get(context);
  DenseMap<StringAttr, StateBase> bases;
  for (StringRef plane : planes) {
    auto global = symbols.lookup<LLVM::GlobalOp>(plane);
    if (!global)
      continue;
    auto array = dyn_cast<LLVM::LLVMArrayType>(global.getGlobalType());
    if (!array || !array.getElementType().isInteger(8))
      return global.emitError("native state plane must be a byte array");
    std::string name = (plane + "_base").str();
    auto base = symbols.lookup<LLVM::GlobalOp>(name);
    if (!base) {
      if (symbols.lookup(name))
        return global.emitError("native state base symbol is not a global");
      // The private constant has only its static initializer. The externally
      // initialized flag keeps LLVM from folding the pointer into each use;
      // it does not install a writer or change the initialized address.
      builder.setInsertionPointAfter(global);
      base = LLVM::GlobalOp::create(builder, global.getLoc(), pointer,
                                    /*isConstant=*/true,
                                    LLVM::Linkage::Internal, name, Attribute(),
                                    /*alignment=*/8);
      base.setExternallyInitialized(true);
      Block *initializer = builder.createBlock(&base.getInitializerRegion());
      builder.setInsertionPointToStart(initializer);
      Value address =
          LLVM::AddressOfOp::create(builder, global.getLoc(), pointer, plane);
      LLVM::ReturnOp::create(builder, global.getLoc(), address);
    } else {
      Region &initializer = base.getInitializerRegion();
      LLVM::AddressOfOp address;
      LLVM::ReturnOp result;
      if (initializer.hasOneBlock() &&
          initializer.front().getOperations().size() == 2) {
        address = dyn_cast<LLVM::AddressOfOp>(initializer.front().front());
        result = dyn_cast<LLVM::ReturnOp>(initializer.front().back());
      }
      if (base.getGlobalType() != pointer || !base.getConstant() ||
          base.getLinkage() != LLVM::Linkage::Internal ||
          !base.getExternallyInitialized() ||
          base.getAlignment().value_or(0) < 8 || base.getAddrSpace() != 0 ||
          !address || !result || result.getNumOperands() != 1 ||
          result.getOperand(0) != address.getResult() ||
          address.getGlobalName() != plane)
        return base.emitError(
            "native state base must be a private externally initialized "
            "aligned constant pointer initialized to its plane address");
    }
    bases[global.getSymNameAttr()] = {base.getSymNameAttr(),
                                      array.getNumElements()};
  }
  if (bases.empty())
    return success();
  DenseSet<StringAttr> metadataOnly;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>())
    if (schedule::has<schedule::Field::EvalStateMetadataOnly>(function))
      metadataOnly.insert(function.getSymNameAttr());
  auto layout = module->getAttrOfType<StringAttr>("llvm.data_layout");
  auto parsed = llvm::DataLayout::parse(layout ? layout.getValue() : "");
  if (!parsed)
    return module.emitError() << "invalid native state data layout: "
                              << llvm::toString(parsed.takeError());
  unsigned indexBits = parsed->getIndexSizeInBits(0);
  unsigned pointerBits = parsed->getPointerSizeInBits(0);
  // Each function rewrites only its own body.
  SmallVector<LLVM::LLVMFuncOp> functions;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>())
    if (!function.isExternal())
      functions.push_back(function);
  analysis::parallelForChunked(context, functions.size(), [&](size_t index) {
    LLVM::LLVMFuncOp function = functions[index];
    OpBuilder builder(context);
    // A coroutine would carry the base across its suspensions in the frame.
    llvm::MapVector<StringAttr, SmallVector<LLVM::AddressOfOp>> uses;
    bool coroutine = false;
    function.walk([&](Operation *operation) {
      if (isa<LLVM::CoroBeginOp>(operation))
        coroutine = true;
      else if (auto address = dyn_cast<LLVM::AddressOfOp>(operation))
        if (bases.count(address.getGlobalNameAttr().getAttr()))
          uses[address.getGlobalNameAttr().getAttr()].push_back(address);
    });
    if (coroutine)
      return;
    if (!metadataOnly.empty())
      annotateStateMetadataCalls(function, metadataOnly, bases, indexBits,
                                  pointerBits);
    if (uses.empty())
      return;
    // Within one block, code generation already folds the smallest offset
    // into the plane address and reaches the rest with immediates.
    DenseSet<Block *> blocks;
    for (auto &[plane, addresses] : uses)
      for (LLVM::AddressOfOp address : addresses)
        for (Operation *user : address->getUsers())
          blocks.insert(user->getBlock());
    if (blocks.size() < 2)
      return;
    builder.setInsertionPointToStart(&function.getBody().front());
    SmallVector<Value, 2> loadedBases;
    SmallVector<uint64_t, 2> planeBytes;
    for (auto &[plane, addresses] : uses) {
      StateBase base = bases.lookup(plane);
      Location location = addresses.front().getLoc();
      Value slot =
          LLVM::AddressOfOp::create(builder, location, pointer, base.name);
      auto load = LLVM::LoadOp::create(builder, location, pointer, slot,
                                       /*alignment=*/8, /*isVolatile=*/false,
                                       /*isNonTemporal=*/false,
                                       /*isInvariant=*/true);
      load.setDereferenceableAttr(
          LLVM::DereferenceableAttr::get(context, base.bytes, false));
      loadedBases.push_back(load);
      planeBytes.push_back(base.bytes);
      for (LLVM::AddressOfOp address : addresses)
        address.replaceAllUsesWith(load.getResult());
    }
    if (loadedBases.size() == 2) {
      // The bases point to different global allocations, not different source
      // signals within one allocation. LLVM's separate_storage assumption
      // restores that fact without restricting unknown pointer arguments or
      // overlapping accesses in one plane. Addresses and ordered value/X/Z
      // effects remain identical (IEEE 1800-2023 4.3, 4.6, 6.3.1).
      // Repeat the existing dereferenceable facts in the same assumption:
      // otherwise LLVM 22 InstCombine can sink a base load and drop the
      // separate_storage bundle before redundant-load elimination sees it.
      Location location = function.getLoc();
      Value condition = LLVM::ConstantOp::create(
          builder, location, builder.getI1Type(), builder.getBoolAttr(true));
      SmallVector<Value, 2> left{loadedBases[0],
                                 LLVM::ConstantOp::create(builder, location,
                                                          builder.getI64Type(),
                                                          planeBytes[0])};
      SmallVector<Value, 2> right{loadedBases[1],
                                  LLVM::ConstantOp::create(builder, location,
                                                           builder.getI64Type(),
                                                           planeBytes[1])};
      SmallVector<ValueRange, 3> bundles{loadedBases, left, right};
      LLVM::AssumeOp::create(
          builder, location, condition, bundles,
          builder.getStrArrayAttr(
              {"separate_storage", "dereferenceable", "dereferenceable"}));
    }
    for (auto &[plane, addresses] : uses)
      for (LLVM::AddressOfOp address : addresses)
        address.erase();
  });
  return success();
}

namespace {
class AddressNativeStateThroughBasesPass final
    : public impl::AddressNativeStateThroughBasesPassBase<
          AddressNativeStateThroughBasesPass> {
  void runOnOperation() override {
    if (failed(addressNativeStateThroughBases(getOperation())))
      signalPassFailure();
  }
};
} // namespace

} // namespace talos
