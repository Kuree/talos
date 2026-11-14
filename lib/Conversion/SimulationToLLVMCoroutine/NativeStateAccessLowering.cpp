//===- NativeStateAccessLowering.cpp - Typed state accesses to LLVM -------===//
//
// Native passes access the canonical state planes through typed schedule
// operations. Once nothing needs to tell a state access from another memory
// access, each becomes the LLVM access it stands for: the plane global's
// address, a byte GEP to the window, and a load or store of it.
//
//===----------------------------------------------------------------------===//

#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_LOWERNATIVESTATEACCESSPASS
#include "talos/Conversion/Passes.h.inc"

namespace {
// The plane's address plus the window's offset, as producers built it: a
// byte GEP to a static offset, a GEP by the dynamic offset, or both.
Value lowerAddress(OpBuilder &builder, Location location,
                   FlatSymbolRefAttr global, Value dynamicOffset,
                   uint64_t staticOffset) {
  auto pointer = LLVM::LLVMPointerType::get(builder.getContext());
  Value address = LLVM::AddressOfOp::create(builder, location, pointer, global);
  if (dynamicOffset) {
    address = LLVM::GEPOp::create(builder, location, pointer,
                                  builder.getI8Type(), address,
                                  ValueRange{dynamicOffset});
    if (!staticOffset)
      return address;
  }
  return detail::byteGEP(builder, location, address, staticOffset);
}

class LowerNativeStateAccessPass final
    : public impl::LowerNativeStateAccessPassBase<LowerNativeStateAccessPass> {
public:
  void runOnOperation() override {
    SmallVector<Operation *> accesses;
    getOperation().walk([&](Operation *operation) {
      if (isa<schedule::NativeStateAddressOp, schedule::NativeStateLoadOp,
              schedule::NativeStateStoreOp>(operation))
        accesses.push_back(operation);
    });
    if (accesses.empty())
      return markAllAnalysesPreserved();
    for (Operation *operation : accesses) {
      OpBuilder builder(operation);
      Location location = operation->getLoc();
      Operation *lowered;
      if (auto address = dyn_cast<schedule::NativeStateAddressOp>(operation)) {
        lowered = LLVM::AddressOfOp::create(
            builder, location, address.getType(), address.getGlobalAttr());
      } else if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation)) {
        lowered = LLVM::LoadOp::create(
            builder, location, load.getType(),
            lowerAddress(builder, location, load.getGlobalAttr(),
                         load.getDynamicOffset(), load.getStaticOffset()),
            load.getAlignment());
      } else {
        auto store = cast<schedule::NativeStateStoreOp>(operation);
        lowered = LLVM::StoreOp::create(
            builder, location, store.getValue(),
            lowerAddress(builder, location, store.getGlobalAttr(),
                         store.getDynamicOffset(), store.getStaticOffset()),
            store.getAlignment());
      }
      // Native tags on the access stay with it.
      lowered->setDiscardableAttrs(operation->getDiscardableAttrDictionary());
      operation->replaceAllUsesWith(lowered);
      operation->erase();
    }
  }
};
} // namespace
} // namespace talos
