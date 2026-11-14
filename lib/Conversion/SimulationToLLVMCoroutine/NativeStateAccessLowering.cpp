//===- NativeStateAccessLowering.cpp - Typed state accesses ---------------===//
//
// Native passes access the canonical state planes through typed schedule
// operations. Once nothing needs to tell a state access from another memory
// access, each becomes the LLVM access it stands for: the plane global's
// address, a byte GEP to the window, and a load or store of it.
//
// While producers still emit that LLVM form, raise-native-state-access turns
// it back into typed operations at the start of native LLVM finalization.
// An access the typed operations cannot express (another discardable
// attribute, a volatile or atomic access, a non-byte GEP) stays in LLVM form;
// the finalization stages see both forms through NativeStateAccess.h.
//
//===----------------------------------------------------------------------===//

#include "NativeStateAccess.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_LOWERNATIVESTATEACCESSPASS
#define GEN_PASS_DEF_RAISENATIVESTATEACCESSPASS
#include "talos/Conversion/Passes.h.inc"


namespace {
// Lowers typed state accesses to the LLVM accesses they stand for. A plane's
// address and a window's address are each taken once per block, at their
// first use, so the lowered IR shares addresses as the IR would after CSE,
// even at -O0 where finalization runs no CSE. (The address of a global is a
// constant in LLVM IR; where it is taken costs nothing.) A dynamic window's
// address stays in the blocks that use it: hoisting it to where its offset is
// defined would compute it on paths that never access it.
class StateAccessLowering {
public:
  Value base(OpBuilder &builder, Location location,
             schedule::StatePlane plane) {
    auto key = std::make_tuple(builder.getInsertionBlock(),
                               static_cast<unsigned>(plane), Value{},
                               uint64_t{0});
    if (Value address = addresses.lookup(key))
      return address;
    Value address = LLVM::AddressOfOp::create(
        builder, location, LLVM::LLVMPointerType::get(builder.getContext()),
        schedule::getStatePlaneGlobalName(plane));
    addresses.try_emplace(key, address);
    return address;
  }

  // The address of a window: the plane plus a byte GEP by the dynamic offset
  // and one to the static offset, each only when it moves the address.
  Value window(OpBuilder &builder, Location location,
               schedule::StatePlane plane, Value dynamicOffset,
               uint64_t staticOffset) {
    if (!dynamicOffset && !staticOffset)
      return base(builder, location, plane);
    auto key = std::make_tuple(builder.getInsertionBlock(),
                               static_cast<unsigned>(plane), dynamicOffset,
                               staticOffset);
    if (Value address = addresses.lookup(key))
      return address;
    Value address;
    if (!staticOffset)
      address = LLVM::GEPOp::create(
          builder, location, LLVM::LLVMPointerType::get(builder.getContext()),
          builder.getI8Type(), base(builder, location, plane),
          ValueRange{dynamicOffset});
    else
      address = detail::byteGEP(
          builder, location, window(builder, location, plane, dynamicOffset, 0),
          staticOffset);
    addresses.try_emplace(key, address);
    return address;
  }

private:
  DenseMap<std::tuple<Block *, unsigned, Value, uint64_t>, Value> addresses;
};

// The tags producers still put on LLVM-form state accesses, and the typed
// access properties that replace them. An access with any other discardable
// attribute, or with a tag its property would not admit, stays in LLVM form,
// where its consumers treat malformed evidence conservatively.
template <typename AccessOp> bool raiseTags(Operation *from, AccessOp to) {
  for (NamedAttribute tag : from->getDiscardableAttrs()) {
    StringRef name = tag.getName().strref();
    Attribute value = tag.getValue();
    auto range = dyn_cast<DenseI64ArrayAttr>(value);
    auto owner = dyn_cast<IntegerAttr>(value);
    if (name == schedule::getFieldName(schedule::Field::EvalStateAccessBytes)) {
      if (!range || !schedule::isValidStateWindow(range.asArrayRef()))
        return false;
      to.setWindowAttr(range);
    } else if (name == schedule::getFieldName(
                           schedule::Field::EvalPreserveNbaUnknown)) {
      to.setLatchDestination(true);
    } else if (name ==
               schedule::getFieldName(schedule::Field::EvalGroupOwner)) {
      if (!owner || !owner.getType().isSignlessInteger(32))
        return false;
      to.setOwnerAttr(owner);
    } else if constexpr (std::is_same_v<AccessOp,
                                        schedule::NativeStateStoreOp>) {
      if (name ==
          schedule::getFieldName(schedule::Field::EvalUnknownWriteRange)) {
        if (!range || !schedule::isValidStateWrittenBits(range.asArrayRef()))
          return false;
        to.setWrittenBitsAttr(range);
      } else if (name == schedule::getFieldName(
                             schedule::Field::EvalUnknownSummaryReported)) {
        to.setSummaryReported(true);
      } else {
        return false;
      }
    } else {
      return false;
    }
  }
  return true;
}

// Whether a typed state access can stand for an LLVM access with these
// properties: lowering reproduces only its alignment and native tags.
template <typename AccessOp> bool isPlainAccess(AccessOp access, Type type) {
  std::optional<uint64_t> alignment = access.getAlignment();
  if (!alignment || !llvm::isPowerOf2_64(*alignment) || access.getVolatile_() ||
      access.getNontemporal() || access.getInvariantGroup() ||
      access.getOrdering() != LLVM::AtomicOrdering::not_atomic ||
      access.getSyncscope() || access.getAccessGroupsAttr() ||
      access.getAliasScopesAttr() || access.getNoaliasScopesAttr() ||
      access.getTbaaAttr())
    return false;
  if (auto vector = dyn_cast<VectorType>(type))
    type = vector.getElementType();
  auto integer = dyn_cast<IntegerType>(type);
  return integer && integer.isSignless();
}

class RaiseNativeStateAccessPass final
    : public impl::RaiseNativeStateAccessPassBase<RaiseNativeStateAccessPass> {
public:
  void runOnOperation() override {
    // Plane addresses: LLVM ones become typed bases; producers' typed bases
    // are raised from as they are.
    SmallVector<Operation *> planes;
    getOperation().walk([&](Operation *operation) {
      if (auto address = dyn_cast<LLVM::AddressOfOp>(operation)) {
        if (schedule::getStatePlaneOfGlobal(address.getGlobalName()))
          planes.push_back(address);
      } else if (isa<schedule::NativeStateAddressOp>(operation)) {
        planes.push_back(operation);
      }
    });
    if (planes.empty())
      return markAllAnalysesPreserved();
    for (Operation *plane : planes) {
      auto base = dyn_cast<schedule::NativeStateAddressOp>(plane);
      if (auto address = dyn_cast<LLVM::AddressOfOp>(plane)) {
        if (!address->getDiscardableAttrDictionary().empty())
          continue;
        OpBuilder builder(address);
        base = schedule::NativeStateAddressOp::create(
            builder, address.getLoc(), address.getType(),
            address.getGlobalNameAttr());
        address.replaceAllUsesWith(base.getResult());
        address.erase();
      }
      // An access at offset zero uses the base itself: canonicalization
      // folds a zero GEP away.
      for (Operation *user : llvm::make_early_inc_range(base->getUsers())) {
        if (auto gep = dyn_cast<LLVM::GEPOp>(user))
          raiseWindow(gep, base);
        else
          raiseAccess(user, base.getResult(), base.getPlane(), Value{}, 0);
      }
      // Typed accesses name their plane; a base nothing else uses is dead.
      if (base->use_empty())
        base.erase();
    }
  }

private:
  // Accesses through one plain byte GEP of the plane base become typed.
  void raiseWindow(LLVM::GEPOp gep, schedule::NativeStateAddressOp base) {
    if (gep.getBase() != base.getResult() || !gep.getElemType().isInteger(8) ||
        gep.getIndices().size() != 1 ||
        gep.getNoWrapFlags() != LLVM::GEPNoWrapFlags::none ||
        !gep->getDiscardableAttrDictionary().empty())
      return;
    Value dynamicOffset;
    uint64_t staticOffset = 0;
    auto index = gep.getIndices()[0];
    APInt constant;
    if (auto attribute = dyn_cast<IntegerAttr>(index))
      constant = attribute.getValue();
    else if (!matchPattern(cast<Value>(index), m_ConstantInt(&constant)))
      dynamicOffset = cast<Value>(index);
    if (dynamicOffset) {
      if (!dynamicOffset.getType().isInteger(64))
        return;
    } else {
      // A constant index, as an attribute or an SSA constant, is the static
      // offset.
      if (constant.isNegative() || constant.getActiveBits() > 63)
        return;
      staticOffset = constant.getZExtValue();
    }
    for (Operation *user : llvm::make_early_inc_range(gep->getUsers()))
      raiseAccess(user, gep.getResult(), base.getPlane(), dynamicOffset,
                  staticOffset);
    if (!gep->use_empty())
      return;
    // The static offset replaced a constant index, which may now be unused.
    Operation *constantIndex = nullptr;
    if (!dynamicOffset && !gep.getDynamicIndices().empty())
      constantIndex = gep.getDynamicIndices().front().getDefiningOp();
    gep.erase();
    if (constantIndex && constantIndex->use_empty() &&
        isMemoryEffectFree(constantIndex))
      constantIndex->erase();
  }

  // A plain load or store of `address`, the plane's window at the given
  // offsets, becomes typed.
  void raiseAccess(Operation *user, Value address, schedule::StatePlane plane,
                   Value dynamicOffset, uint64_t staticOffset) {
    OpBuilder builder(user);
    Operation *raised = nullptr;
    if (auto load = dyn_cast<LLVM::LoadOp>(user);
        load && load.getAddr() == address &&
        isPlainAccess(load, load.getType()) && !load.getInvariant() &&
        !load.getDereferenceable())
      raised = schedule::NativeStateLoadOp::create(
          builder, load.getLoc(), load.getType(), plane, dynamicOffset,
          staticOffset, *load.getAlignment());
    else if (auto store = dyn_cast<LLVM::StoreOp>(user);
             store && store.getAddr() == address &&
             store.getValue() != address &&
             isPlainAccess(store, store.getValue().getType()))
      raised = schedule::NativeStateStoreOp::create(
          builder, store.getLoc(), store.getValue(), plane, dynamicOffset,
          staticOffset, *store.getAlignment());
    if (!raised)
      return;
    bool tagged =
        isa<schedule::NativeStateLoadOp>(raised)
            ? raiseTags(user, cast<schedule::NativeStateLoadOp>(raised))
            : raiseTags(user, cast<schedule::NativeStateStoreOp>(raised));
    if (!tagged) {
      raised->erase();
      return;
    }
    user->replaceAllUsesWith(raised);
    user->erase();
  }
};

class LowerNativeStateAccessPass final
    : public impl::LowerNativeStateAccessPassBase<LowerNativeStateAccessPass> {
public:
  void runOnOperation() override {
    LLVM::LLVMFuncOp function = getOperation();
    SmallVector<Operation *> accesses;
    function.walk([&](Operation *operation) {
      if (isa<schedule::NativeStateAddressOp, schedule::NativeStateLoadOp,
              schedule::NativeStateStoreOp>(operation))
        accesses.push_back(operation);
    });
    if (accesses.empty())
      return markAllAnalysesPreserved();
    StateAccessLowering lowering;
    // Typed properties served passes before this point; LLVM needs none.
    for (Operation *operation : accesses) {
      OpBuilder builder(operation);
      Location location = operation->getLoc();
      Operation *lowered;
      if (auto address = dyn_cast<schedule::NativeStateAddressOp>(operation)) {
        // A shared plane address; it carries no access's annotations.
        address.replaceAllUsesWith(
            lowering.base(builder, location, address.getPlane()));
        operation->erase();
        continue;
      }
      if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation)) {
        lowered = LLVM::LoadOp::create(
            builder, location, load.getType(),
            lowering.window(builder, location, load.getPlane(),
                            load.getDynamicOffset(), load.getStaticOffset()),
            load.getAlignment());
        load.getResult().replaceAllUsesWith(lowered->getResult(0));
      } else {
        auto store = cast<schedule::NativeStateStoreOp>(operation);
        lowered = LLVM::StoreOp::create(
            builder, location, store.getValue(),
            lowering.window(builder, location, store.getPlane(),
                            store.getDynamicOffset(), store.getStaticOffset()),
            store.getAlignment());
      }
      // Other dialects' annotations stay with the access.
      for (NamedAttribute attribute : operation->getDiscardableAttrs())
        lowered->setAttr(attribute.getName(), attribute.getValue());
      operation->erase();
    }
  }
};
} // namespace
} // namespace talos
