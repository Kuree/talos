//===- NativeStateAccessLowering.cpp - Typed state accesses ---------------===//
//
// Native passes access the canonical state planes through typed schedule
// operations: producers emit them, and every pointer into a plane is a
// plane's base or a window's address. Once nothing needs to tell a state
// access from another memory access, each becomes the LLVM access it stands
// for: the plane global's address, or for a contribution plane the pointer
// its global binds, a byte GEP to the window, and a load or store of it.
//
//===----------------------------------------------------------------------===//

#include "NativeStateAccess.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_LOWERNATIVESTATEACCESSPASS
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
    auto pointer = LLVM::LLVMPointerType::get(builder.getContext());
    Value address = LLVM::AddressOfOp::create(
        builder, location, pointer, schedule::getStatePlaneGlobalName(plane));
    // A contribution plane's global binds the runtime's retained plane.
    if (!schedule::isCanonicalStatePlane(plane))
      address = LLVM::LoadOp::create(builder, location, pointer, address, 8);
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

// A plane's bytes are read and written by typed state accesses only. A
// plane's base or window address leaves typed operations whole and directly:
// into a copy or fill, which native passes see through the address's
// defining operation, into a call, which they treat as opaque, or into an
// address comparison or integer. Anything else, an LLVM access, an address
// computation, or a select, branch or store that hides the address's origin,
// would be a state access the native passes before this point could not see.
LogicalResult verifyStatePointerUses(Value pointer) {
  for (OpOperand &use : pointer.getUses()) {
    Operation *user = use.getOwner();
    if (isa<LLVM::MemcpyOp, LLVM::MemcpyInlineOp, LLVM::MemmoveOp,
            LLVM::MemsetOp, LLVM::MemsetInlineOp, LLVM::CallOp,
            LLVM::PtrToIntOp, LLVM::ICmpOp, LLVM::ReturnOp>(user))
      continue;
    return user->emitError("accesses a state plane through its address "
                           "instead of a typed state access");
  }
  return success();
}

class LowerNativeStateAccessPass final
    : public impl::LowerNativeStateAccessPassBase<LowerNativeStateAccessPass> {
public:
  void runOnOperation() override {
    LLVM::LLVMFuncOp function = getOperation();
    SmallVector<Operation *> accesses;
    bool valid = true;
    function.walk([&](Operation *operation) {
      if (isa<schedule::NativeStateAddressOp,
              schedule::NativeStateWindowAddressOp, schedule::NativeStateLoadOp,
              schedule::NativeStateStoreOp>(operation))
        accesses.push_back(operation);
      if (isa<schedule::NativeStateAddressOp,
              schedule::NativeStateWindowAddressOp>(operation))
        valid &= succeeded(verifyStatePointerUses(operation->getResult(0)));
      // Before this point a function names a plane only through typed
      // operations. A contribution plane's binding global is otherwise only
      // handed to the runtime, as a call argument, which binds it.
      if (auto address = dyn_cast<LLVM::AddressOfOp>(operation)) {
        std::optional<schedule::StatePlane> plane =
            schedule::getStatePlaneOfGlobal(address.getGlobalName());
        if (plane && schedule::isCanonicalStatePlane(*plane)) {
          address.emitError("takes a state plane's address outside typed "
                            "state operations");
          valid = false;
        } else if (plane &&
                   !llvm::all_of(address->getUses(), [](OpOperand &use) {
                     auto call = dyn_cast<LLVM::CallOp>(use.getOwner());
                     return call && !(call.getCallee() == std::nullopt &&
                                      use.getOperandNumber() == 0);
                   })) {
          address.emitError("takes a contribution plane's binding address "
                            "outside a runtime binding call");
          valid = false;
        }
      }
    });
    if (!valid)
      return signalPassFailure();
    if (accesses.empty())
      return markAllAnalysesPreserved();
    StateAccessLowering lowering;
    // Typed properties served passes before this point; LLVM needs none.
    for (Operation *operation : accesses) {
      OpBuilder builder(operation);
      Location location = operation->getLoc();
      Operation *lowered;
      // An address nothing uses is not taken.
      if (isa<schedule::NativeStateAddressOp,
              schedule::NativeStateWindowAddressOp>(operation) &&
          operation->use_empty()) {
        operation->erase();
        continue;
      }
      if (auto address = dyn_cast<schedule::NativeStateAddressOp>(operation)) {
        // A shared plane address; it carries no access's annotations.
        address.replaceAllUsesWith(
            lowering.base(builder, location, address.getPlane()));
        operation->erase();
        continue;
      }
      if (auto window =
              dyn_cast<schedule::NativeStateWindowAddressOp>(operation)) {
        window.replaceAllUsesWith(lowering.window(
            builder, location, window.getPlane(), window.getDynamicOffset(),
            window.getStaticOffset()));
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
