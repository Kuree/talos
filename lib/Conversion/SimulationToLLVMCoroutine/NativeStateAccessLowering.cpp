//===- NativeStateAccessLowering.cpp - Typed state accesses ---------------===//
//
// Native passes access the canonical state planes through typed schedule
// operations: producers emit them, and every pointer into a plane is a
// plane's base or a window's address. Once nothing needs to tell a state
// access from another memory access, each becomes the LLVM access it stands
// for: the plane global's address, or for a contribution plane the pointer
// its global binds, a byte GEP to the window, and a load or store of it.
// Generated NBA accumulator records are accessed the same way: their typed
// field accesses become byte GEPs to the field in the record layout. Ready
// set and eval mask words are lowered earlier, after their last typed reader.
//
//===----------------------------------------------------------------------===//

#include "NativeStateAccess.h"
#include "SimulationEvalReadySet.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_LOWERNATIVESTATEACCESSPASS
#define GEN_PASS_DEF_LOWERNATIVEREADYWORDSPASS
#define GEN_PASS_DEF_LOWERNATIVEMASKWORDSPASS
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

// An NBA accumulator record's fields are read and written by typed
// accumulator accesses only, so native passes before this point see every
// access to the record (IEEE 1800-2023 4.9.4, 10.4.2: a capture is consumed
// exactly once). Its address flows nowhere else.
LogicalResult verifyAccumulatorAddressUses(Value record) {
  // A field access's only pointer operand is its record.
  for (Operation *user : record.getUsers())
    if (!isa<schedule::NativeNBAAccumulatorLoadOp,
             schedule::NativeNBAAccumulatorStoreOp>(user))
      return user->emitError("accesses an NBA accumulator record through its "
                             "address instead of a typed accumulator access");
  return success();
}

// Lowers typed accumulator accesses to byte GEPs of the record by the field's
// offset in the record layout, one per block and offset, at its first use.
class AccumulatorAccessLowering {
public:
  explicit AccumulatorAccessLowering(bool twoState) : twoState(twoState) {}

  FailureOr<Value> field(OpBuilder &builder, Operation *access, Value record,
                         schedule::NBAAccumulatorField field, uint64_t offset) {
    std::optional<uint64_t> fieldOffset =
        detail::getNBAAccumulatorFieldOffset(field, twoState);
    if (!fieldOffset)
      return access->emitError("accesses the X/Z field of a two-state NBA "
                               "accumulator record");
    uint64_t bytes = *fieldOffset + offset;
    auto key = std::make_tuple(builder.getInsertionBlock(), record, bytes);
    if (Value address = addresses.lookup(key))
      return address;
    Value address = detail::byteGEP(builder, access->getLoc(), record, bytes);
    addresses.try_emplace(key, address);
    return address;
  }

private:
  bool twoState;
  DenseMap<std::tuple<Block *, Value, uint64_t>, Value> addresses;
};

// Lowers NBA index accesses to whole-word LLVM accesses of the index global:
// its address once per block, then a byte GEP to a static word or an i64 GEP
// by a dynamic one, shared per block like a state window's.
class IndexAccessLowering {
public:
  Value word(OpBuilder &builder, Location location, StringRef global,
             Value dynamicWord, uint64_t staticWord) {
    auto key = std::make_tuple(builder.getInsertionBlock(), global, dynamicWord,
                               staticWord);
    if (Value address = words.lookup(key))
      return address;
    auto pointer = LLVM::LLVMPointerType::get(builder.getContext());
    auto baseKey = std::make_pair(builder.getInsertionBlock(), global);
    Value base = bases.lookup(baseKey);
    if (!base) {
      base = LLVM::AddressOfOp::create(builder, location, pointer, global);
      bases.try_emplace(baseKey, base);
    }
    Value address;
    if (!dynamicWord)
      address = detail::byteGEP(builder, location, base,
                                staticWord * sizeof(uint64_t));
    else if (!staticWord)
      address =
          LLVM::GEPOp::create(builder, location, pointer, builder.getI64Type(),
                              base, ValueRange{dynamicWord});
    else
      address = detail::byteGEP(builder, location,
                                word(builder, location, global, dynamicWord, 0),
                                staticWord * sizeof(uint64_t));
    words.try_emplace(key, address);
    return address;
  }

private:
  DenseMap<std::pair<Block *, StringRef>, Value> bases;
  DenseMap<std::tuple<Block *, StringRef, Value, uint64_t>, Value> words;
};

class LowerNativeStateAccessPass final
    : public impl::LowerNativeStateAccessPassBase<LowerNativeStateAccessPass> {
public:
  using Base::Base;

  void runOnOperation() override {
    LLVM::LLVMFuncOp function = getOperation();
    SmallVector<Operation *> accesses;
    SmallVector<Operation *> accumulatorAccesses;
    SmallVector<Operation *> indexAccesses;
    bool valid = true;
    function.walk([&](Operation *operation) {
      if (isa<schedule::NativeStateAddressOp,
              schedule::NativeStateWindowAddressOp, schedule::NativeStateLoadOp,
              schedule::NativeStateStoreOp>(operation))
        accesses.push_back(operation);
      if (isa<schedule::NativeNBAAccumulatorAddressOp,
              schedule::NativeNBAAccumulatorLoadOp,
              schedule::NativeNBAAccumulatorStoreOp>(operation))
        accumulatorAccesses.push_back(operation);
      if (isa<schedule::NativeNBAIndexLoadOp, schedule::NativeNBAIndexStoreOp>(
              operation))
        indexAccesses.push_back(operation);
      if (isa<schedule::NativeNBAAccumulatorAddressOp>(operation))
        valid &=
            succeeded(verifyAccumulatorAddressUses(operation->getResult(0)));
      if (isa<schedule::NativeStateAddressOp,
              schedule::NativeStateWindowAddressOp>(operation))
        valid &= succeeded(verifyStatePointerUses(operation->getResult(0)));
      // Before this point a function names a plane only through typed
      // operations. A contribution plane's binding global is otherwise only
      // handed to the runtime, as a call argument, which binds it.
      // A function names the NBA readiness index only through typed index
      // operations too.
      if (auto address = dyn_cast<LLVM::AddressOfOp>(operation);
          address && schedule::getNBAIndexOfGlobal(address.getGlobalName())) {
        address.emitError("takes an NBA readiness index's address outside "
                          "typed index operations");
        valid = false;
      }
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
    if (accesses.empty() && accumulatorAccesses.empty() &&
        indexAccesses.empty())
      return markAllAnalysesPreserved();
    if (failed(lowerAccumulatorAccesses(accumulatorAccesses)))
      return signalPassFailure();
    lowerIndexAccesses(indexAccesses);
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

private:
  // Index words are whole 64-bit words, accessed with their natural alignment.
  void lowerIndexAccesses(ArrayRef<Operation *> operations) {
    IndexAccessLowering lowering;
    for (Operation *operation : operations) {
      OpBuilder builder(operation);
      Location location = operation->getLoc();
      Operation *lowered;
      if (auto load = dyn_cast<schedule::NativeNBAIndexLoadOp>(operation)) {
        lowered = LLVM::LoadOp::create(
            builder, location, builder.getI64Type(),
            lowering.word(builder, location, load.getGlobal(),
                          load.getDynamicWord(), load.getStaticWord()),
            sizeof(uint64_t));
        load.getResult().replaceAllUsesWith(lowered->getResult(0));
      } else {
        auto store = cast<schedule::NativeNBAIndexStoreOp>(operation);
        lowered = LLVM::StoreOp::create(
            builder, location, store.getValue(),
            lowering.word(builder, location, store.getGlobal(),
                          store.getDynamicWord(), store.getStaticWord()),
            sizeof(uint64_t));
      }
      // Other dialects' annotations stay with the access.
      for (NamedAttribute attribute : operation->getDiscardableAttrs())
        lowered->setAttr(attribute.getName(), attribute.getValue());
      operation->erase();
    }
  }

  // A record's address is taken where its typed address was; its fields are
  // the LLVM accesses of the same alignment at their layout offsets.
  LogicalResult lowerAccumulatorAccesses(ArrayRef<Operation *> operations) {
    // Records first, so the field addresses below are keyed on the LLVM
    // addresses that stay.
    SmallVector<Operation *> accesses;
    for (Operation *operation : operations) {
      auto address =
          dyn_cast<schedule::NativeNBAAccumulatorAddressOp>(operation);
      if (!address) {
        accesses.push_back(operation);
        continue;
      }
      if (!address.use_empty()) {
        OpBuilder builder(operation);
        address.replaceAllUsesWith(
            LLVM::AddressOfOp::create(
                builder, operation->getLoc(),
                LLVM::LLVMPointerType::get(builder.getContext()),
                address.getGlobal())
                .getResult());
      }
      operation->erase();
    }
    AccumulatorAccessLowering lowering(twoState);
    for (Operation *operation : accesses) {
      OpBuilder builder(operation);
      Location location = operation->getLoc();
      Operation *lowered;
      if (auto load =
              dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(operation)) {
        FailureOr<Value> field =
            lowering.field(builder, operation, load.getRecord(),
                           load.getField(), load.getOffset());
        if (failed(field))
          return failure();
        lowered = LLVM::LoadOp::create(builder, location, load.getType(),
                                       *field, load.getAlignment());
        load.getResult().replaceAllUsesWith(lowered->getResult(0));
      } else {
        auto store = cast<schedule::NativeNBAAccumulatorStoreOp>(operation);
        FailureOr<Value> field =
            lowering.field(builder, operation, store.getRecord(),
                           store.getField(), store.getOffset());
        if (failed(field))
          return failure();
        lowered = LLVM::StoreOp::create(builder, location, store.getValue(),
                                        *field, store.getAlignment());
      }
      // Other dialects' annotations stay with the access.
      for (NamedAttribute attribute : operation->getDiscardableAttrs())
        lowered->setAttr(attribute.getName(), attribute.getValue());
      operation->erase();
    }
    return success();
  }
};

// The LLVM addresses of whole words of the generated word globals, the ready
// sets and the eval masks, in one function: a global's address once per
// function, at the start of its entry block in the order of first use, then
// a static word's address per access and a dynamic word's once per block, as
// the eval schedule's LLVM form takes them.
class WordAddresses {
public:
  explicit WordAddresses(LLVM::LLVMFuncOp function) : function(function) {}

  Value get(Operation *access, FlatSymbolRefAttr global, Value dynamicWord,
            uint64_t staticWord) {
    Location location = access->getLoc();
    Value &base = bases[global];
    if (!base) {
      OpBuilder entry = OpBuilder::atBlockBegin(&function.getBody().front());
      if (lastBase)
        entry.setInsertionPointAfter(lastBase);
      base = LLVM::AddressOfOp::create(
          entry, location, LLVM::LLVMPointerType::get(function.getContext()),
          global.getValue());
      lastBase = base.getDefiningOp();
    }
    if (!dynamicWord) {
      OpBuilder builder(access);
      return detail::ownerWordAddress(builder, location, base, staticWord);
    }
    // A dynamic word's address is computed once per block, where its index
    // is: right after the index's definition in the access's block, else
    // before the block's first access.
    Value &shared =
        dynamicAddresses[{access->getBlock(), global, dynamicWord, staticWord}];
    if (shared)
      return shared;
    OpBuilder at(access);
    Operation *definition = dynamicWord.getDefiningOp();
    if (definition && definition->getBlock() == access->getBlock()) {
      Operation *&after = lastAfterIndex[dynamicWord];
      at.setInsertionPointAfter(after ? after : definition);
    }
    Value word =
        LLVM::GEPOp::create(at, location, base.getType(), at.getI64Type(), base,
                            ValueRange{dynamicWord});
    if (staticWord)
      word = detail::byteGEP(at, location, word, staticWord * sizeof(uint64_t));
    if (definition && definition->getBlock() == access->getBlock())
      lastAfterIndex[dynamicWord] = word.getDefiningOp();
    return shared = word;
  }

  // Replaces `access`, a typed load (with `result`) or store (with `value`)
  // of a word, with the 8-byte aligned LLVM access it stands for; other
  // dialects' annotations stay with it, and `owner` becomes its group-owner
  // tag. Returns the LLVM access.
  Operation *lower(Operation *access, FlatSymbolRefAttr global,
                   Value dynamicWord, uint64_t staticWord, Value result,
                   Value value, IntegerAttr owner) {
    Value address = get(access, global, dynamicWord, staticWord);
    OpBuilder builder(access);
    Operation *lowered;
    if (result) {
      lowered =
          LLVM::LoadOp::create(builder, access->getLoc(), builder.getI64Type(),
                               address, sizeof(uint64_t));
      result.replaceAllUsesWith(lowered->getResult(0));
    } else {
      lowered = LLVM::StoreOp::create(builder, access->getLoc(), value, address,
                                      sizeof(uint64_t));
    }
    for (NamedAttribute attribute : access->getDiscardableAttrs())
      lowered->setAttr(attribute.getName(), attribute.getValue());
    if (owner)
      detail::setNativeMemoryOwner(lowered, owner);
    return lowered;
  }

private:
  LLVM::LLVMFuncOp function;
  llvm::SmallDenseMap<Attribute, Value, 2> bases;
  Operation *lastBase = nullptr;
  DenseMap<std::tuple<Block *, Attribute, Value, uint64_t>, Value>
      dynamicAddresses;
  DenseMap<Value, Operation *> lastAfterIndex;
};

// Lowers ready set word accesses to whole-word LLVM accesses of the set's
// global (WordAddresses).
class LowerNativeReadyWordsPass final
    : public impl::LowerNativeReadyWordsPassBase<LowerNativeReadyWordsPass> {
public:
  void runOnOperation() override {
    LLVM::LLVMFuncOp function = getOperation();
    SmallVector<Operation *> words;
    bool valid = true;
    function.walk([&](Operation *operation) {
      if (isa<schedule::NativeReadyWordLoadOp,
              schedule::NativeReadyWordStoreOp>(operation))
        words.push_back(operation);
      // Before this point a function accesses a ready set only through ready
      // actions and typed words, which the passes before it inspect (ready
      // region boundaries, group dataflow and hierarchy, and the elision of
      // ranked publications). This rejects an address taken by the set's
      // name. Generated code reaches a set no other way; a pointer that does
      // (an argument, an llvm.mlir.alias, a loaded pointer) is not detected,
      // and only ready-region lowering, which keeps an untyped access it
      // cannot prove disjoint as a boundary, handles it (native-ready-region).
      if (auto address = dyn_cast<LLVM::AddressOfOp>(operation);
          address && schedule::getReadySetOfGlobal(address.getGlobalName())) {
        address.emitError("takes a ready set's address outside typed ready "
                          "operations");
        valid = false;
      }
    });
    if (!valid)
      return signalPassFailure();
    if (words.empty())
      return markAllAnalysesPreserved();
    WordAddresses addresses(function);
    for (Operation *operation : words) {
      if (auto load = dyn_cast<schedule::NativeReadyWordLoadOp>(operation)) {
        Operation *lowered =
            addresses.lower(load, load.getSetAttr(), load.getDynamicWord(),
                            load.getStaticWord(), load.getResult(), Value{},
                            load.getOwnerAttr());
        if (IntegerAttr entry = load.getActivationEntryAttr())
          detail::setNativeActivationEntry(lowered, entry);
      } else {
        auto store = cast<schedule::NativeReadyWordStoreOp>(operation);
        addresses.lower(store, store.getSetAttr(), store.getDynamicWord(),
                        store.getStaticWord(), Value{}, store.getValue(),
                        store.getOwnerAttr());
      }
      operation->erase();
    }
  }
};

// Lowers eval mask word accesses to whole-word LLVM accesses of the mask's
// global (WordAddresses).
class LowerNativeMaskWordsPass final
    : public impl::LowerNativeMaskWordsPassBase<LowerNativeMaskWordsPass> {
public:
  void runOnOperation() override {
    LLVM::LLVMFuncOp function = getOperation();
    SmallVector<Operation *> words;
    function.walk([&](Operation *operation) {
      if (isa<schedule::NativeMaskLoadOp, schedule::NativeMaskStoreOp>(
              operation))
        words.push_back(operation);
    });
    if (words.empty())
      return markAllAnalysesPreserved();
    WordAddresses addresses(function);
    for (Operation *operation : words) {
      if (auto load = dyn_cast<schedule::NativeMaskLoadOp>(operation)) {
        addresses.lower(load, load.getMaskAttr(), load.getDynamicWord(),
                        load.getStaticWord(), load.getResult(), Value{},
                        load.getOwnerAttr());
      } else {
        auto store = cast<schedule::NativeMaskStoreOp>(operation);
        addresses.lower(store, store.getMaskAttr(), store.getDynamicWord(),
                        store.getStaticWord(), Value{}, store.getValue(),
                        store.getOwnerAttr());
      }
      operation->erase();
    }
  }
};
} // namespace
} // namespace talos
