//===- SimulationNativeEvalTransaction.cpp - Local NBA captures ---------===//

#include "NativeRuntimeCalls.h"
#include "SimulationAOTPlanning.h"
#include "SimulationEvalNBAQueue.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/EvalRoles.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"

using namespace mlir;

namespace talos::detail {
namespace {

struct PendingRoot {
  uint32_t root, ordinal;
  uint64_t mask;
  uint32_t region;
  bool transient;
  std::string accumulator;
  uint64_t bitmapOffset = 0;
  uint64_t payloadOffset = 0;
  bool twoState = false;
};

struct PendingWord {
  uint32_t canonicalWord;
  uint64_t offset, mask = 0;
  SmallVector<unsigned> roots{};
};

StringRef baseGlobal(Value pointer) {
  while (auto gep = pointer.getDefiningOp<LLVM::GEPOp>())
    pointer = gep.getBase();
  auto global = pointer.getDefiningOp<LLVM::AddressOfOp>();
  return global ? global.getGlobalName() : StringRef{};
}

struct CaptureInventory {
  SmallVector<int64_t, 5> target;
  llvm::SmallDenseSet<uint64_t, 4> sites;
  unsigned stages = 0;
  bool exact = true;
};

struct MemoryInventory {
  bool seen = false;
  bool exact = true;
};

// A field access of a named generated NBA accumulator record. A record
// pointer read from a table names no record.
struct RecordAccess {
  StringRef accumulator;
  NBAField field;
  uint64_t offset;
  Type type;
};

std::optional<RecordAccess> recordAccess(Operation *operation) {
  auto named = [](Value record) {
    auto address =
        record.getDefiningOp<schedule::NativeNBAAccumulatorAddressOp>();
    return address ? address.getGlobal() : StringRef{};
  };
  if (auto load = dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(operation))
    if (StringRef name = named(load.getRecord()); !name.empty())
      return RecordAccess{name, load.getField(), load.getOffset(),
                          load.getType()};
  if (auto store = dyn_cast<schedule::NativeNBAAccumulatorStoreOp>(operation))
    if (StringRef name = named(store.getRecord()); !name.empty())
      return RecordAccess{name, store.getField(), store.getOffset(),
                          store.getValue().getType()};
  return std::nullopt;
}

// An access of a word of the NBA readiness index, with the role its
// producer gave it. A dynamic word has no static index.
struct IndexAccess {
  schedule::NBAIndex index;
  std::optional<uint64_t> word;
  std::optional<uint32_t> root;
  bool canonicalCapture;
  DenseI64ArrayAttr capture;
  bool write;
};

std::optional<IndexAccess> indexAccess(Operation *operation) {
  if (auto load = dyn_cast<schedule::NativeNBAIndexLoadOp>(operation))
    return IndexAccess{load.getIndex(),
                       load.getDynamicWord()
                           ? std::nullopt
                           : std::optional<uint64_t>(load.getStaticWord()),
                       load.getRoot(),
                       load.getCanonicalCapture(),
                       DenseI64ArrayAttr{},
                       /*write=*/false};
  if (auto store = dyn_cast<schedule::NativeNBAIndexStoreOp>(operation))
    return IndexAccess{store.getIndex(),
                       store.getDynamicWord()
                           ? std::nullopt
                           : std::optional<uint64_t>(store.getStaticWord()),
                       store.getRoot(),
                       store.getCanonicalCapture(),
                       store.getCaptureAttr(),
                       /*write=*/true};
  return std::nullopt;
}

bool zero(Value value) {
  APInt constant;
  return matchPattern(value, m_ConstantInt(&constant)) && constant.isZero();
}

Value constant(OpBuilder &builder, Location loc, uint64_t value) {
  return llvmConstant(builder, loc, builder.getI64Type(), value);
}
Value load(OpBuilder &builder, Location loc, Value frame, uint64_t offset) {
  return LLVM::LoadOp::create(builder, loc, builder.getI64Type(),
                              byteGEP(builder, loc, frame, offset), 8);
}
void store(OpBuilder &builder, Location loc, Value frame, uint64_t offset,
           Value value) {
  LLVM::StoreOp::create(builder, loc, value,
                        byteGEP(builder, loc, frame, offset), 8);
}

uint64_t field(const PendingRoot &root, unsigned lane) {
  return root.payloadOffset + (lane - (root.twoState && lane == 2)) * 8;
}

Value pendingBits(OpBuilder &builder, Location loc, Value frame,
                  ArrayRef<PendingWord> words) {
  Value bits = constant(builder, loc, 0);
  for (const auto &word : words)
    bits = LLVM::OrOp::create(builder, loc, bits,
                              load(builder, loc, frame, word.offset));
  return bits;
}

Value selected(OpBuilder &builder, Location loc, Value bits,
               const PendingRoot &root, unsigned destination) {
  if (destination == root.root % 64)
    return LLVM::AndOp::create(
        builder, loc, bits, constant(builder, loc, uint64_t{1} << destination));
  Value bit = LLVM::AndOp::create(
      builder, loc,
      LLVM::LShrOp::create(builder, loc, bits,
                           constant(builder, loc, root.root % 64)),
      constant(builder, loc, 1));
  return destination ? LLVM::ShlOp::create(builder, loc, bit,
                                           constant(builder, loc, destination))
                           .getResult()
                     : bit;
}

// Export/adopt at a real execution cut, preserving captured operands rather
// than replaying producers (IEEE 1800-2023 4.6(b), 4.9.4, 10.4.2). Packed
// CURRENT state remains handled by its existing publication proof; this is
// PENDING state.
void transfer(OpBuilder &builder, Location loc, Value frame,
              ArrayRef<PendingRoot> roots, ArrayRef<PendingWord> words,
              const llvm::SmallBitVector &mask, bool exporting, bool writable) {
  // Each sparse word has its own empty fast path. Preserve source bit
  // positions and transfer only this function's closure, without imposing a
  // model-wide root count or permuting the logical readiness index.
  for (const auto &word : words) {
    uint64_t scope = 0;
    for (unsigned ordinal : word.roots) {
      const auto &root = roots[ordinal];
      if (mask.test(root.ordinal))
        scope |= uint64_t{1} << (root.root % 64);
    }
    if (!scope)
      continue;
    Value available;
    if (exporting) {
      available = load(builder, loc, frame, word.offset);
    } else {
      available = loadNBAIndex(builder, loc, schedule::NBAIndex::DirtyRoots,
                               word.canonicalWord);
    }
    Value any =
        LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::ne,
                             LLVM::AndOp::create(builder, loc, available,
                                                 constant(builder, loc, scope)),
                             constant(builder, loc, 0));
    Block *entry = builder.getInsertionBlock();
    Block *done = entry->splitBlock(builder.getInsertionPoint());
    Block *body = new Block;
    entry->getParent()->getBlocks().insert(Region::iterator(done), body);
    builder.setInsertionPointToEnd(entry);
    LLVM::CondBrOp::create(builder, loc, any, body, ValueRange{}, done,
                           ValueRange{});
    builder.setInsertionPointToStart(body);
    for (unsigned ordinal : word.roots) {
      const auto &root = roots[ordinal];
      if (!mask.test(root.ordinal))
        continue;
      constexpr auto dirtyRoots = schedule::NBAIndex::DirtyRoots;
      uint64_t leaf = root.root / 64;
      Value bits = exporting
                       ? load(builder, loc, frame, word.offset)
                       : Value(loadNBAIndex(builder, loc, dirtyRoots, leaf));
      unsigned bit = root.root % 64;
      Value present = LLVM::ICmpOp::create(
          builder, loc, LLVM::ICmpPredicate::ne,
          LLVM::AndOp::create(builder, loc, bits,
                              constant(builder, loc, uint64_t{1} << bit)),
          constant(builder, loc, 0));
      Block *head = builder.getInsertionBlock();
      Block *tail = head->splitBlock(builder.getInsertionPoint());
      Block *copy = new Block;
      head->getParent()->getBlocks().insert(Region::iterator(tail), copy);
      builder.setInsertionPointToEnd(head);
      LLVM::CondBrOp::create(builder, loc, present, copy, ValueRange{}, tail,
                             ValueRange{});
      builder.setInsertionPointToStart(copy);
      Value accumulator = schedule::NativeNBAAccumulatorAddressOp::create(
          builder, loc, root.accumulator);
      if (!exporting) {
        Value contextAddress = LLVM::AddressOfOp::create(
            builder, loc, LLVM::LLVMPointerType::get(builder.getContext()),
            "__talos_current_context");
        Value runtimeContext = LLVM::LoadOp::create(
            builder, loc, LLVM::LLVMPointerType::get(builder.getContext()),
            contextAddress, 8);
        Value allowed =
            LLVM::CallOp::create(
                builder, loc, TypeRange{builder.getI32Type()},
                writable
                    ? getNativeRuntimeSymbol(
                          NativeRuntimeEntry::StaticNbaSpecializationGuardWrite)
                    : getNativeRuntimeSymbol(
                          NativeRuntimeEntry::StaticNbaSpecializationGuard),
                ValueRange{runtimeContext,
                           llvmConstant(builder, loc, builder.getI32Type(),
                                        root.root)})
                .getResult();
        Value valid = schedule::NativeNBAAccumulatorLoadOp::create(
            builder, loc, builder.getI32Type(), accumulator, NBAField::Valid, 0,
            4);
        Value generated = LLVM::ICmpOp::create(
            builder, loc, LLVM::ICmpPredicate::ne,
            LLVM::AndOp::create(builder, loc, allowed, valid),
            llvmConstant(builder, loc, builder.getI32Type(), 0));
        Value region = schedule::NativeNBAAccumulatorLoadOp::create(
            builder, loc, builder.getI32Type(), accumulator,
            NBAField::ExecRegion, 0, 4);
        Value capturedMask = schedule::NativeNBAAccumulatorLoadOp::create(
            builder, loc, builder.getI64Type(), accumulator,
            NBAField::WriteMask, 0, 8);
        generated = LLVM::AndOp::create(
            builder, loc, generated,
            LLVM::AndOp::create(
                builder, loc,
                LLVM::ICmpOp::create(
                    builder, loc, LLVM::ICmpPredicate::eq, region,
                    llvmConstant(builder, loc, builder.getI32Type(),
                                 root.region)),
                LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::eq,
                                     capturedMask,
                                     constant(builder, loc, root.mask))));
        // The leaf bit also covers runtime/ordered captures. Leave those forms
        // addressable for the common NBA prefix; importing their bit alone
        // would consume work without its captured payload (IEEE 1800-2023
        // 4.9.4, 10.4.2).
        Block *adopt = new Block;
        copy->getParent()->getBlocks().insert(Region::iterator(tail), adopt);
        LLVM::CondBrOp::create(builder, loc, generated, adopt, ValueRange{},
                               tail, ValueRange{});
        builder.setInsertionPointToStart(adopt);
      }
      constexpr NBAField lanes[] = {NBAField::Value, NBAField::Unknown,
                                    NBAField::Transient};
      for (unsigned lane = 0; lane != 3; ++lane) {
        if ((lane == 1 && root.twoState) || (lane == 2 && !root.transient))
          continue;
        if (exporting)
          schedule::NativeNBAAccumulatorStoreOp::create(
              builder, loc, load(builder, loc, frame, field(root, lane)),
              accumulator, lanes[lane], 0, 8);
        else
          store(builder, loc, frame, field(root, lane),
                schedule::NativeNBAAccumulatorLoadOp::create(
                    builder, loc, builder.getI64Type(), accumulator,
                    lanes[lane], 0, 8));
      }
      if (exporting) {
        schedule::NativeNBAAccumulatorStoreOp::create(
            builder, loc, constant(builder, loc, root.mask), accumulator,
            NBAField::WriteMask, 0, 8);
        schedule::NativeNBAAccumulatorStoreOp::create(
            builder, loc, llvmConstant(builder, loc, builder.getI32Type(), 1),
            accumulator, NBAField::Valid, 0, 4);
        schedule::NativeNBAAccumulatorStoreOp::create(
            builder, loc,
            llvmConstant(builder, loc, builder.getI32Type(), root.region),
            accumulator, NBAField::ExecRegion, 0, 4);
        Value old = loadNBAIndex(builder, loc, dirtyRoots, leaf);
        storeNBAIndex(
            builder, loc,
            LLVM::OrOp::create(
                builder, loc, old,
                constant(builder, loc, uint64_t{1} << (root.root % 64))),
            dirtyRoots, leaf);
        constexpr auto dirtySummary = schedule::NBAIndex::DirtySummary;
        Value oldPage =
            loadNBAIndex(builder, loc, dirtySummary, root.root / 4096);
        storeNBAIndex(
            builder, loc,
            LLVM::OrOp::create(
                builder, loc, oldPage,
                constant(builder, loc, uint64_t{1} << ((root.root / 64) % 64))),
            dirtySummary, root.root / 4096);
        store(
            builder, loc, frame, word.offset,
            LLVM::AndOp::create(builder, loc, bits,
                                constant(builder, loc, ~(uint64_t{1} << bit))));
        if (root.transient)
          store(builder, loc, frame, field(root, 2), constant(builder, loc, 0));
      } else {
        // Adoption transfers ownership, not just the index bit. Runtime
        // snapshots and generated knownness predicates also inspect validity
        // directly. A stale canonical valid/mask could republish this capture
        // after the private consumer commits it (IEEE 1800-2023 4.9.4,
        // 10.4.2).
        schedule::NativeNBAAccumulatorStoreOp::create(
            builder, loc, llvmConstant(builder, loc, builder.getI32Type(), 0),
            accumulator, NBAField::Valid, 0, 4);
        schedule::NativeNBAAccumulatorStoreOp::create(
            builder, loc, constant(builder, loc, 0), accumulator,
            NBAField::WriteMask, 0, 8);
        if (root.transient)
          schedule::NativeNBAAccumulatorStoreOp::create(
              builder, loc, constant(builder, loc, 0), accumulator,
              NBAField::Transient, 0, 8);
        storeNBAIndex(
            builder, loc,
            LLVM::AndOp::create(
                builder, loc, bits,
                constant(builder, loc, ~(uint64_t{1} << (root.root % 64)))),
            dirtyRoots, leaf);
        store(builder, loc, frame, word.offset,
              LLVM::OrOp::create(builder, loc,
                                 load(builder, loc, frame, word.offset),
                                 constant(builder, loc, uint64_t{1} << bit)));
      }
      LLVM::BrOp::create(builder, loc, ValueRange{}, tail);
      builder.setInsertionPointToStart(tail);
    }
    LLVM::BrOp::create(builder, loc, ValueRange{}, done);
    builder.setInsertionPointToStart(done);
  }
}

ArrayAttr extendArgAttrs(MLIRContext *context, ArrayAttr original, unsigned n) {
  SmallVector<Attribute> attrs;
  if (original)
    llvm::append_range(attrs, original.getValue());
  attrs.resize(n, DictionaryAttr::get(context));
  // Generated cores use this activation-local pointer only for frame accesses
  // and forwarding to other cores. Opaque cuts receive canonical captured
  // operands. Publish the nonescaping contract across LLVM partitions so those
  // calls do not force private readiness/payload words back into memory.
  attrs.push_back(DictionaryAttr::get(
      context,
      {NamedAttribute(
           StringAttr::get(context, LLVM::LLVMDialect::getNoAliasAttrName()),
           UnitAttr::get(context)),
       NamedAttribute(
           StringAttr::get(context, LLVM::LLVMDialect::getNoCaptureAttrName()),
           UnitAttr::get(context))}));
  return ArrayAttr::get(context, attrs);
}

static LLVM::LLVMFuncOp moveBodyWithPointerArgument(LLVM::LLVMFuncOp original,
                                                    StringRef suffix,
                                                    ArrayAttr argumentAttrs,
                                                    SymbolTable &symbols) {
  OpBuilder b(original);
  Location loc = original.getLoc();
  auto ptr = LLVM::LLVMPointerType::get(original.getContext());
  SmallVector<Type> args(original.getArgumentTypes());
  args.push_back(ptr);
  auto type = LLVM::LLVMFunctionType::get(
      original.getFunctionType().getReturnType(), args);
  auto core = LLVM::LLVMFuncOp::create(
      b, loc, (original.getSymName() + suffix).str(), type);
  symbols.insert(core);
  for (NamedAttribute attr : original->getAttrs())
    if (attr.getName() != "sym_name" && attr.getName() != "function_type" &&
        attr.getName() != "arg_attrs")
      core->setAttr(attr.getName(), attr.getValue());
  core.setLinkage(LLVM::Linkage::Internal);
  if (argumentAttrs)
    core.setArgAttrsAttr(argumentAttrs);
  core.getBody().takeBody(original.getBody());
  core.getBody().front().addArgument(ptr, loc);
  return core;
}

// Calls that cannot inspect/stage pending NBA captures. The source writer
// inventory separately excludes runtime Active writers of localized roots.
// An entry that is PendingTransparent for every call qualifies; the others
// only for the argument forms below.
bool pendingRuntimeTransparent(LLVM::CallOp call) {
  auto callee = call.getCallee();
  if (!callee)
    return false;
  if (callee->starts_with("llvm."))
    return true;
  std::optional<NativeRuntimeEntry> entry = getNativeRuntimeEntry(*callee);
  if (!entry)
    return false;
  if (getNativeRuntimeEffects(*entry) & native_runtime::PendingTransparent)
    return true;
  auto arguments = call.getArgOperands();
  auto constant = [&](unsigned index) {
    return static_cast<bool>(
        arguments[index].getDefiningOp<LLVM::ConstantOp>());
  };
  switch (*entry) {
  case NativeRuntimeEntry::SchedulerWideTransitionOwned:
    return arguments.size() == 8 && constant(1) && constant(2) && constant(3);
  case NativeRuntimeEntry::SchedulerStaticTransitionOwned:
    // The verified publication bridge delivers waits but cannot execute a
    // waiting actor or consume pending captures. CURRENT publication still
    // occurs at this call (IEEE 1800-2023 4.6(a), 9.4.2).
    return arguments.size() == 9 && constant(1) && constant(2);
  default:
    return false;
  }
}

// Calls a register body may make while the generic NBA queue's view stays
// shared: they update at most the queue and its membership words. A
// generic capture qualifies only when it is not delayed.
static bool queueCaptureOnly(LLVM::CallOp call) {
  std::optional<StringRef> callee = call.getCallee();
  std::optional<NativeRuntimeEntry> entry =
      callee ? getNativeRuntimeEntry(*callee) : std::nullopt;
  if (!entry ||
      !(getNativeRuntimeEffects(*entry) & native_runtime::QueueCaptureOnly))
    return false;
  if (*entry != NativeRuntimeEntry::SchedulerNba &&
      *entry != NativeRuntimeEntry::SchedulerNbaIfChanged)
    return true;
  return call.getArgOperands().size() == 9 && zero(call.getArgOperands()[6]);
}

// Ordinary generated plane and stack reads/writes cannot rebind the queue.
// A store through a context argument or another unproved pointer can.
static bool accessesOnlyGeneratedStorage(Operation *op) {
  if (auto store = dyn_cast<LLVM::StoreOp>(op)) {
    Value address = store.getAddr();
    while (auto gep = address.getDefiningOp<LLVM::GEPOp>())
      address = gep.getBase();
    auto global = address.getDefiningOp<LLVM::AddressOfOp>();
    return (global && global.getGlobalName() != "__talos_current_context") ||
           isa_and_nonnull<LLVM::AllocaOp, schedule::NativeStateAddressOp,
                           schedule::NativeStateWindowAddressOp>(
               address.getDefiningOp());
  }
  // A named generated NBA accumulator record is generated storage; a record
  // pointer read from memory is not proved to be one.
  if (auto store = dyn_cast<schedule::NativeNBAAccumulatorStoreOp>(op))
    return store.getRecord()
               .getDefiningOp<schedule::NativeNBAAccumulatorAddressOp>() !=
           nullptr;
  if (isa<CallOpInterface, LLVM::InlineAsmOp>(op))
    return false;
  // The NBA readiness index is generated storage too.
  return isMemoryEffectFree(op) ||
         isa<LLVM::LoadOp, LLVM::AllocaOp, LLVM::ReturnOp,
             schedule::NativeStateLoadOp, schedule::NativeStateStoreOp,
             schedule::NativeNBAAccumulatorLoadOp,
             schedule::NativeNBAIndexLoadOp, schedule::NativeNBAIndexStoreOp,
             schedule::NativeReadyReadOp, schedule::NativeReadyUpdateOp,
             schedule::NativeReadyCommitOp, schedule::NativeReadyMergeOp>(op);
}

// A periodic clock can call hundreds of capture-only register bodies in
// succession. They update the common FIFO and its membership words, but none
// changes which bitmap describes that FIFO. Pass that checked view down the
// straight-line clock prefix. Every check in a body still reads the current
// words at the original capture (1800-2023 4.6(b), 9.4.2, 10.4.2).
static void shareGenericQueueView(ModuleOp module) {
  auto run =
      module.lookupSymbol<LLVM::LLVMFuncOp>("__talos_aot_schedule_run_v1");
  if (!run || run.isExternal() ||
      !module.lookupSymbol("__talos_current_context"))
    return;
  MLIRContext *ctx = module.getContext();
  Type ptr = LLVM::LLVMPointerType::get(ctx);
  SymbolTable symbols(module);
  constexpr StringLiteral queryName =
      getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerGenericNbaWords);
  struct Body {
    bool closed = false;
    std::optional<uint32_t> maxState;
    LLVM::LLVMFuncOp implementation;
  };
  DenseMap<Operation *, Body> bodies;
  auto ordinary = [](LLVM::CallOp call) {
    return call.getCConv() == LLVM::CConv::C &&
           call.getOpBundleSizes().empty() && !call.getVarCalleeType() &&
           call.getTailCallKind() == LLVM::tailcallkind::TailCallKind::None;
  };
  // Check the actual executable closure, including the two-state selector
  // and its four-state alternative. A cold foreign call still ends the view.
  std::function<Body(LLVM::LLVMFuncOp)> inspect =
      [&](LLVM::LLVMFuncOp fn) -> Body {
    if (!fn || fn == run || fn.isExternal() || fn.isVarArg() ||
        fn.getCConv() != LLVM::CConv::C)
      return {};
    if (auto found = bodies.find(fn); found != bodies.end())
      return found->second;
    bodies.try_emplace(fn); // A recursive call has no certificate.
    bool raw = schedule::has<schedule::Field::EvalRawCaptures>(fn);
    bool selected =
        raw || schedule::has<schedule::Field::EvalInfallible>(fn) ||
        schedule::has<schedule::Field::EvalPathKnownPredicate>(fn) ||
        schedule::has<schedule::Field::EvalStateMetadataOnly>(fn);
    if (auto attrs = fn.getPassthroughAttr())
      selected |=
          llvm::is_contained(attrs, StringAttr::get(ctx, "alwaysinline"));
    if (!selected)
      return {};
    Body facts;
    auto include = [&](uint32_t id) {
      facts.maxState = std::max(id, facts.maxState.value_or(0));
    };
    WalkResult checked = fn.walk([&](Operation *op) {
      auto call = dyn_cast<LLVM::CallOp>(op);
      if (!call)
        return op == fn || accessesOnlyGeneratedStorage(op)
                   ? WalkResult::advance()
                   : WalkResult::interrupt();
      auto callee = call.getCallee();
      if (!callee || !ordinary(call))
        return WalkResult::interrupt();
      if (*callee == queryName) {
        APInt id;
        if (!raw || call.getArgOperands().size() != 2 ||
            !matchPattern(call.getArgOperands()[1], m_ConstantInt(&id)) ||
            id.getActiveBits() > 32)
          return WalkResult::interrupt();
        auto load = call.getArgOperands()[0].getDefiningOp<LLVM::LoadOp>();
        auto address = load ? load.getAddr().getDefiningOp<LLVM::AddressOfOp>()
                            : LLVM::AddressOfOp{};
        if (!address || address.getGlobalName() != "__talos_current_context")
          return WalkResult::interrupt();
        include(id.getZExtValue());
      } else if (!queueCaptureOnly(call)) {
        Body child = inspect(symbols.lookup<LLVM::LLVMFuncOp>(*callee));
        if (!child.closed)
          return WalkResult::interrupt();
        if (child.maxState)
          include(*child.maxState);
      }
      return WalkResult::advance();
    });
    if (!checked.wasInterrupted()) {
      facts.closed = true;
      bodies[fn] = facts;
    }
    return bodies.lookup(fn);
  };
  llvm::SetVector<Operation *> needed;
  llvm::MapVector<Operation *, Operation *> selected;
  uint32_t maximum = 0;
  run.walk([&](LLVM::CallOp call) {
    if (!call.getCallee() || !ordinary(call))
      return;
    auto function = symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee());
    Body facts = inspect(function);
    if (facts.closed && facts.maxState) {
      selected.insert({call, function});
      needed.insert(function);
      maximum = std::max(maximum, *facts.maxState);
    }
  });
  if (selected.size() < 2)
    return;
  for (size_t i = 0; i < needed.size(); ++i)
    cast<LLVM::LLVMFuncOp>(needed[i]).walk([&](LLVM::CallOp call) {
      if (auto name = call.getCallee())
        if (auto child = symbols.lookup<LLVM::LLVMFuncOp>(*name))
          if (bodies.lookup(child).maxState)
            needed.insert(child);
    });
  auto current = [&](OpBuilder &b, Location loc) -> Value {
    return LLVM::LoadOp::create(
        b, loc, ptr,
        LLVM::AddressOfOp::create(b, loc, ptr, "__talos_current_context"));
  };
  auto forward = [&](LLVM::CallOp call, LLVM::LLVMFuncOp target, Value view) {
    if (auto attrs = call.getArgAttrsAttr()) {
      SmallVector<Attribute> extended(attrs.begin(), attrs.end());
      extended.push_back(DictionaryAttr::get(ctx));
      call.setArgAttrsAttr(ArrayAttr::get(ctx, extended));
    }
    call.setCallee(target.getSymName());
    call.getCalleeOperandsMutable().append(view);
  };
  // Keep one implementation of every register body, with a checked public
  // adapter for calls made outside this invocation of the clock coordinator.
  for (Operation *operation : needed) {
    auto original = cast<LLVM::LLVMFuncOp>(operation);
    Location loc = original.getLoc();
    OpBuilder b(original);
    ArrayAttr argumentAttrs;
    if (auto attrs = original.getArgAttrsAttr()) {
      SmallVector<Attribute> extended(attrs.begin(), attrs.end());
      extended.push_back(b.getDictionaryAttr({}));
      argumentAttrs = b.getArrayAttr(extended);
    }
    auto core = moveBodyWithPointerArgument(original, ".__talos_queue_view",
                                            argumentAttrs, symbols);
    Body &info = bodies[operation];
    info.implementation = core;
    Block *entry = original.addEntryBlock(b);
    b.setInsertionPointToStart(entry);
    SmallVector<Value> operands(entry->getArguments());
    operands.push_back(
        LLVM::CallOp::create(
            b, loc, TypeRange{ptr}, queryName,
            ValueRange{current(b, loc),
                       llvmConstant(b, loc, b.getI32Type(), *info.maxState)})
            .getResult());
    auto result = LLVM::CallOp::create(b, loc, core, operands);
    LLVM::ReturnOp::create(b, loc, result.getResults());
  }
  for (Operation *operation : needed) {
    auto core = bodies.lookup(operation).implementation;
    Value view = core.getBody().front().getArguments().back();
    core.walk([&](LLVM::CallOp call) {
      if (call.getCallee() == queryName) {
        call.getResult().replaceAllUsesWith(view);
        call.erase();
      } else if (auto child =
                     symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee())) {
        if (auto next = bodies.lookup(child).implementation)
          forward(call, next, view);
      }
    });
  }
  // The cache belongs to this invocation. Handoffs, callbacks and ordinary
  // dispatchers cannot inherit it, even when they reenter the same model.
  OpBuilder b = OpBuilder::atBlockBegin(&run.getBody().front());
  Value slot = entryAlloca(b, run.getLoc(), ptr, 1, 8);
  Value empty = LLVM::ZeroOp::create(b, run.getLoc(), ptr);
  LLVM::StoreOp::create(b, run.getLoc(), empty, slot, 8);
  SmallVector<Operation *> cuts;
  run.walk([&](Operation *op) {
    if (op != run && !accessesOnlyGeneratedStorage(op))
      cuts.push_back(op);
  });
  for (Operation *op : cuts) {
    b.setInsertionPoint(op);
    Location loc = op->getLoc();
    auto call = dyn_cast<LLVM::CallOp>(op);
    if (!selected.count(op)) {
      if (call && call.getCallee()) {
        if (callsNativeRuntime(
                call, NativeRuntimeEntry::SchedulerPrioritySignalPending))
          continue;
        if (auto target = symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee()))
          if (bodies.lookup(target).closed)
            continue;
      }
      LLVM::StoreOp::create(b, loc, empty, slot, 8);
      continue;
    }
    Value cached = LLVM::LoadOp::create(b, loc, ptr, slot, 8);
    Block *head = op->getBlock();
    Block *invoke = head->splitBlock(Block::iterator(op));
    Block *query = b.createBlock(head->getParent(), invoke->getIterator());
    Value words = invoke->addArgument(ptr, loc);
    b.setInsertionPointToEnd(head);
    Value valid =
        LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::ne, cached, empty);
    LLVM::CondBrOp::create(b, loc, valid, invoke, ValueRange{cached}, query,
                           ValueRange{});
    b.setInsertionPointToEnd(query);
    Value fresh = LLVM::CallOp::create(
                      b, loc, TypeRange{ptr}, queryName,
                      ValueRange{current(b, loc),
                                 llvmConstant(b, loc, b.getI32Type(), maximum)})
                      .getResult();
    LLVM::StoreOp::create(b, loc, fresh, slot, 8);
    LLVM::BrOp::create(b, loc, ValueRange{fresh}, invoke);
    b.setInsertionPoint(call);
    forward(call, bodies.lookup(selected.lookup(op)).implementation, words);
  }
}
} // namespace

// The shared coordinator visits its pre-NBA cut between deferred clock
// owners. Keep a cut only across a closed call tree that cannot publish to
// runtime actors. Generated Active readiness is still consumed by the
// ordinary dispatcher after every owner (1800-2023 4.4.2.3-4, 4.5).
void reuseQuietNBACuts(ModuleOp module) {
  if (!schedule::has<schedule::Field::EvalRuntimeCalendar>(module) ||
      schedule::has<schedule::Field::ForceGenericNBA>(module) ||
      !native::has<native::ClosedExecutable>(module))
    return;
  auto dispatch =
      module.lookupSymbol<LLVM::LLVMFuncOp>("__talos_eval_dispatch_v1");
  if (!dispatch || dispatch.isExternal())
    return;
  constexpr StringLiteral prepare =
      getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerPrepareEvalNba);
  SymbolTable symbols(module);
  DenseMap<Operation *, bool> inspected;
  auto localMemory = [&](Operation *op) {
    if (accessesOnlyGeneratedStorage(op))
      return true;
    auto store = dyn_cast<LLVM::StoreOp>(op);
    if (!store)
      return false;
    Value addr = store.getAddr();
    while (auto gep = addr.getDefiningOp<LLVM::GEPOp>())
      addr = gep.getBase();
    auto data = addr.getDefiningOp<LLVM::LoadOp>();
    // Field zero points into the separately reserved array of NBA captures.
    if (!data || !isa<LLVM::LLVMPointerType>(data.getType()))
      return false;
    addr = data.getAddr();
    while (auto gep = addr.getDefiningOp<LLVM::GEPOp>()) {
      if (!llvm::all_of(gep.getIndices(), [](auto index) {
            if (auto attr = dyn_cast<IntegerAttr>(index))
              return attr.getValue().isZero();
            return zero(cast<Value>(index));
          }))
        return false;
      addr = gep.getBase();
    }
    return baseGlobal(addr) == evalNBAQueueName;
  };
  std::function<bool(LLVM::CallOp)> quiet = [&](LLVM::CallOp call) {
    auto name = call.getCallee();
    if (!name)
      return false;
    if (hasNativeRuntimeEffect(*name, native_runtime::CutQuiet))
      return true;
    auto fn = symbols.lookup<LLVM::LLVMFuncOp>(*name);
    if (!fn || fn == dispatch || fn.isExternal())
      return false;
    if (auto found = inspected.find(fn); found != inspected.end())
      return found->second;
    inspected[fn] = false;
    // Independent helpers can be selected through a value-domain probe.
    // Never infer safety from a hot branch or from a function's name.
    bool safe =
        !fn.walk([&](Operation *op) {
             auto nested = dyn_cast<LLVM::CallOp>(op);
             return (nested ? quiet(nested) : op == fn || localMemory(op))
                        ? WalkResult::advance()
                        : WalkResult::interrupt();
           }).wasInterrupted();
    inspected[fn] = safe;
    return safe;
  };
  // A clock owner can sit behind an executor adapter. Follow that adapter
  // to the body whose captures it actually runs.
  auto defined = [&](LLVM::CallOp call) -> LLVM::LLVMFuncOp {
    if (auto name = call.getCallee())
      if (auto fn = symbols.lookup<LLVM::LLVMFuncOp>(*name);
          fn && !fn.isExternal() && fn != dispatch &&
          !fn.getFunctionType().isVarArg())
        return fn;
    return {};
  };
  DenseMap<Operation *, bool> hasClock;
  std::function<bool(LLVM::CallOp)> reachesClock = [&](LLVM::CallOp call) {
    auto fn = defined(call);
    if (!fn)
      return false;
    if (schedule::hasEvalRoles(fn, schedule::EvalRole::ClockedKernel))
      return true;
    if (auto found = hasClock.find(fn); found != hasClock.end())
      return found->second;
    hasClock[fn] = false;
    return hasClock[fn] = fn.walk([&](LLVM::CallOp nested) {
                              return reachesClock(nested)
                                         ? WalkResult::interrupt()
                                         : WalkResult::advance();
                            }).wasInterrupted();
  };

  // Some register bodies have an assertion report or publication on one
  // branch. Preserve the drained cut on paths that only capture registers.
  // An opaque operation anywhere on the executed path clears it before its
  // effects become visible. Follow ordinary CFG edges only.
  DenseMap<Operation *, bool> hasQuietPath;
  std::function<bool(LLVM::CallOp)> conditional = [&](LLVM::CallOp call) {
    auto fn = defined(call);
    if (!fn || quiet(call))
      return false;
    if (auto found = hasQuietPath.find(fn); found != hasQuietPath.end())
      return found->second;
    hasQuietPath[fn] = false;
    SmallVector<Block *> pending{&fn.getBody().front()};
    llvm::SmallPtrSet<Block *, 16> seen;
    while (!pending.empty()) {
      Block *block = pending.pop_back_val();
      if (!seen.insert(block).second)
        continue;
      bool clear = llvm::all_of(*block, [&](Operation &op) {
        if (auto nested = dyn_cast<LLVM::CallOp>(op))
          return quiet(nested) || conditional(nested);
        return op.getNumRegions() == 0 && localMemory(&op);
      });
      if (!clear)
        continue;
      if (isa<LLVM::ReturnOp>(block->getTerminator()))
        return hasQuietPath[fn] = true;
      llvm::append_range(pending, block->getSuccessors());
    }
    return false;
  };

  SmallVector<LLVM::CallOp> checks, clockCalls;
  SmallVector<Operation *> cuts;
  llvm::SetVector<Operation *> conditionalBodies;
  unsigned quietClocked = 0;
  dispatch.walk([&](Operation *op) {
    if (auto call = dyn_cast<LLVM::CallOp>(op)) {
      if (call.getCallee() == prepare && call.getArgOperands().size() == 2) {
        checks.push_back(call);
        return;
      }
      if (quiet(call)) {
        quietClocked += reachesClock(call);
        return;
      }
      if (reachesClock(call) && conditional(call)) {
        conditionalBodies.insert(defined(call));
        clockCalls.push_back(call);
        ++quietClocked;
        return;
      }
    } else if (op == dispatch || localMemory(op)) {
      return;
    }
    cuts.push_back(op);
  });
  if (checks.empty() || quietClocked < 2)
    return;
  OpBuilder b = OpBuilder::atBlockBegin(&dispatch.getBody().front());
  Location loc = dispatch.getLoc();
  // Deferred owners can stage more NBAs. Only the barrier read after their
  // ready set is empty needs to select a region. The earlier checks still
  // drain every runtime Active/Inactive event and report termination (4.5).
  LLVM::LoadOp barrier;
  if (checks.size() == 1) {
    auto prepare = checks.front();
    Value region = prepare.getArgOperands()[1];
    auto ctx = dyn_cast<BlockArgument>(prepare.getArgOperands()[0]);
    // The early result can still report termination. A caller that also
    // inspects the actual region before the marked read needs the original
    // prepare contract.
    auto testsTermination = [](Value value, Operation *user) {
      if (auto cmp = dyn_cast<arith::CmpIOp>(user)) {
        if (cmp.getPredicate() != arith::CmpIPredicate::eq &&
            cmp.getPredicate() != arith::CmpIPredicate::ne)
          return false;
      } else if (auto cmp = dyn_cast<LLVM::ICmpOp>(user)) {
        if (cmp.getPredicate() != LLVM::ICmpPredicate::eq &&
            cmp.getPredicate() != LLVM::ICmpPredicate::ne)
          return false;
      } else
        return false;
      APInt other;
      return matchPattern(
                 user->getOperand(user->getOperand(0) == value ? 1 : 0),
                 m_ConstantInt(&other)) &&
             other == TALOS_RT_EVAL_NBA_TERMINATED;
    };
    if (region.getDefiningOp<LLVM::AllocaOp>() && ctx &&
        ctx.getOwner() == &dispatch.getBody().front())
      for (Operation *use : region.getUsers()) {
        if (use == prepare)
          continue;
        auto read = dyn_cast<LLVM::LoadOp>(use);
        if (read && !read.getVolatile_() &&
            read.getOrdering() == LLVM::AtomicOrdering::not_atomic) {
          if (schedule::has<schedule::Field::EvalNbaBarrierRead>(read)) {
            if (!barrier) {
              barrier = read;
              continue;
            }
          } else if (llvm::all_of(read->getUsers(), [&](Operation *user) {
                       return testsTermination(read.getResult(), user);
                     }))
            continue;
        }
        barrier = {};
        break;
      }
  }
  auto service = declareNativeRuntime(
      module, barrier ? NativeRuntimeEntry::SchedulerDrainClockedActive
                      : NativeRuntimeEntry::SchedulerPrepareQuietEvalNba);
  Value stamp =
      entryAlloca(b, loc, b.getI64Type(), TALOS_RT_EVAL_NBA_CUT_WORDS, 8);
  Value invalid = llvmConstant(b, loc, b.getI64Type(), 0);
  LLVM::StoreOp::create(b, loc, invalid, stamp, 8);
  for (Operation *cut : cuts) {
    b.setInsertionPoint(cut);
    LLVM::StoreOp::create(b, cut->getLoc(), invalid, stamp, 8);
  }
  if (!conditionalBodies.empty()) {
    for (unsigned i = 0; i != conditionalBodies.size(); ++i) {
      auto fn = cast<LLVM::LLVMFuncOp>(conditionalBodies[i]);
      fn.walk([&](LLVM::CallOp call) {
        if (conditional(call))
          conditionalBodies.insert(defined(call));
      });
    }
    DenseMap<Operation *, LLVM::LLVMFuncOp> cores;
    for (Operation *op : conditionalBodies) {
      auto original = cast<LLVM::LLVMFuncOp>(op);
      Location at = original.getLoc();
      auto core = moveBodyWithPointerArgument(
          original, ".__talos_clock_cut",
          extendArgAttrs(module.getContext(), original.getArgAttrsAttr(),
                         original.getArgumentTypes().size()),
          symbols);
      cores[op] = core;
      // Callers outside the coordinator retain their ABI. Their private
      // word can be cleared without affecting another invocation.
      Block *entry = original.addEntryBlock(b);
      b.setInsertionPointToStart(entry);
      SmallVector<Value> args(entry->getArguments());
      args.push_back(entryAlloca(b, at, b.getI64Type(), 1, 8));
      auto result = LLVM::CallOp::create(b, at, core, args);
      LLVM::ReturnOp::create(b, at, result.getResults());
    }
    auto forward = [&](LLVM::CallOp call, Value activeCut) {
      if (auto core = cores.lookup(defined(call))) {
        call.setCallee(core.getSymName());
        call.getCalleeOperandsMutable().append(activeCut);
        return true;
      }
      return false;
    };
    for (LLVM::CallOp call : clockCalls)
      forward(call, stamp);
    for (Operation *op : conditionalBodies) {
      auto core = cores.lookup(op);
      Value activeCut = core.getBody().front().getArguments().back();
      SmallVector<Operation *> publications;
      core.walk([&](Operation *nested) {
        if (auto call = dyn_cast<LLVM::CallOp>(nested)) {
          if (forward(call, activeCut) || quiet(call))
            return;
        } else if (nested == core || localMemory(nested)) {
          return;
        }
        publications.push_back(nested);
      });
      for (Operation *publication : publications) {
        b.setInsertionPoint(publication);
        auto at = publication->getLoc();
        LLVM::StoreOp::create(b, at, llvmConstant(b, at, b.getI64Type(), 0),
                              activeCut, 8);
      }
    }
  }
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos deferred clock captures: owners=" << quietClocked
                 << " conditional bodies=" << conditionalBodies.size()
                 << " deferred barrier=" << bool(barrier) << '\n';
  for (auto call : checks) {
    call.setCallee(service.getSymName());
    call.getCalleeOperandsMutable().append(stamp);
  }
  if (barrier) {
    auto query = declareNativeRuntime(
        module, NativeRuntimeEntry::SchedulerClockedNbaRegion);
    b.setInsertionPoint(barrier);
    auto region = LLVM::CallOp::create(b, barrier.getLoc(), query,
                                       checks.front().getArgOperands()[0]);
    barrier.replaceAllUsesWith(region.getResult());
    barrier.erase();
  }
}

LogicalResult materializeNativeEvalTransactions(ModuleOp module) {
  if (schedule::has<schedule::Field::ForceGenericNBA>(module) &&
      schedule::has<schedule::Field::EvalRuntimeCalendar>(module) &&
      native::has<native::ClosedExecutable>(module))
    shareGenericQueueView(module);
  auto certificate =
      schedule::get<schedule::Field::EvalTransactionRoots>(module);
  if (!certificate ||
      !schedule::has<schedule::Field::EvalRuntimeCalendar>(module))
    return success();
  MLIRContext *context = module.getContext();
  llvm::StringMap<LLVM::LLVMFuncOp> functions;
  bool writable = schedule::has<schedule::Field::EvalWritableVpi>(module);
  llvm::SetVector<Operation *> reachable;
  SmallVector<LLVM::LLVMFuncOp> work;
  for (auto function : module.getOps<LLVM::LLVMFuncOp>()) {
    functions.try_emplace(function.getSymName(), function);
    if (schedule::has<schedule::metadata::evalCallClosureRoot>(function))
      work.push_back(function);
  }
  while (!work.empty()) {
    auto function = work.pop_back_val();
    if (function.isExternal() || !reachable.insert(function.getOperation()))
      continue;
    function.walk([&](LLVM::CallOp call) {
      if (call.getCallee())
        if (auto callee = functions.lookup(*call.getCallee()))
          work.push_back(callee);
    });
  }
  DenseMap<uint32_t, CaptureInventory> captures;
  DenseMap<uint32_t, std::string> commitConsumers;
  llvm::StringMap<MemoryInventory> memoryInventory;
  // Globals a function addresses with llvm.mlir.addressof. Native code
  // accesses accumulator records and the NBA readiness index only through
  // typed operations; an LLVM address of one is an access this pass cannot
  // see.
  llvm::StringSet<> rawAddressed;
  for (Operation *operation : reachable) {
    // Inventory every use of an accumulator address, not just typed field
    // accesses. A cast, CFG argument or memory intrinsic can hide an alias.
    // Localizing only the visible accesses would split capture ownership and
    // change the consumed payload (IEEE 1800-2023 4.9.4, 10.4.2).
    cast<LLVM::LLVMFuncOp>(operation).walk(
        [&](schedule::NativeNBAAccumulatorAddressOp record) {
          auto &memory = memoryInventory[record.getGlobal()];
          for (OpOperand &use : record.getResult().getUses()) {
            auto load =
                dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(use.getOwner());
            auto store =
                dyn_cast<schedule::NativeNBAAccumulatorStoreOp>(use.getOwner());
            if (!(load && load.getRecord() == record.getResult()) &&
                !(store && store.getRecord() == record.getResult() &&
                  store.getValue() != record.getResult()))
              memory.exact = false;
          }
        });
    cast<LLVM::LLVMFuncOp>(operation).walk([&](LLVM::AddressOfOp address) {
      rawAddressed.insert(address.getGlobalName());
    });
    cast<LLVM::LLVMFuncOp>(operation).walk([&](Operation *nested) {
      std::optional<IndexAccess> index = indexAccess(nested);
      // A runtime-held capture keeps its root canonical.
      if (index && index->canonicalCapture)
        captures[*index->root].exact = false;
      // A generated stage certifies its capture on its dirty-root mark.
      if (index && index->capture) {
        auto data = index->capture.asArrayRef();
        if (data.size() != 6 || data[0] < 0 || data[0] > UINT32_MAX)
          return;
        auto &capture = captures[data[0]];
        if (capture.target.empty())
          capture.target.assign(data.begin(), data.begin() + 5);
        else
          capture.exact &= llvm::equal(capture.target, data.take_front(5));
        capture.sites.insert(static_cast<uint64_t>(data[5]));
        ++capture.stages;
      }
      // The readiness index projects onto the private index word by word.
      if (index) {
        auto &memory =
            memoryInventory[schedule::getNBAIndexGlobalName(index->index)];
        memory.seen = true;
        memory.exact &= index->word.has_value();
        return;
      }
      // A field access of a named record: whole words of the bit fields, and
      // the 32-bit valid and region flags.
      if (std::optional<RecordAccess> access = recordAccess(nested)) {
        auto &memory = memoryInventory[access->accumulator];
        memory.seen = true;
        bool flag = access->field == NBAField::Valid ||
                    access->field == NBAField::ExecRegion;
        memory.exact &=
            access->offset == 0 && access->type.isInteger(flag ? 32 : 64);
        // The generated consumer that commits the root tests its capture.
        auto load = dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(nested);
        if (load && load.getPendingRoot() && access->field == NBAField::Valid &&
            access->offset == 0 && access->type.isInteger(32))
          commitConsumers.try_emplace(*load.getPendingRoot(),
                                      access->accumulator.str());
        return;
      }
      // The index and accumulator records are accessed only through typed
      // operations; a raw access of a global is not one this pass localizes.
      if (isa<LLVM::LoadOp, LLVM::StoreOp>(nested)) {
        Value pointer = isa<LLVM::LoadOp>(nested)
                            ? cast<LLVM::LoadOp>(nested).getAddr()
                            : cast<LLVM::StoreOp>(nested).getAddr();
        if (StringRef name = baseGlobal(pointer); !name.empty()) {
          auto &memory = memoryInventory[name];
          memory.seen = true;
          memory.exact = false;
        }
      } else if (auto call = dyn_cast<LLVM::CallOp>(nested)) {
        // An accumulator passed as an address cannot be privatized without
        // an explicit capture interface for the receiving function.
        for (Value argument : call.getArgOperands())
          if (isa<LLVM::LLVMPointerType>(argument.getType()))
            if (StringRef name = baseGlobal(argument); !name.empty())
              memoryInventory[name].exact = false;
      }
    });
  }
  // Dynamic or escaping readiness addresses cannot be projected onto the
  // private sparse index. Retain one canonical owner rather than localizing
  // only the visible constant-offset queries (IEEE 1800-2023 4.9.4, 10.4.2).
  for (schedule::NBAIndex index :
       {schedule::NBAIndex::DirtyRoots, schedule::NBAIndex::DirtySummary}) {
    StringRef name = schedule::getNBAIndexGlobalName(index);
    if (auto memory = memoryInventory.find(name);
        (memory != memoryInventory.end() && !memory->second.exact) ||
        rawAddressed.contains(name))
      return success();
  }
  SmallVector<PendingRoot> candidates;
  for (Attribute raw : certificate) {
    auto record = dyn_cast<DictionaryAttr>(raw);
    auto info =
        record ? record.getAs<DenseI64ArrayAttr>("root") : DenseI64ArrayAttr{};
    auto name = record ? record.getAs<FlatSymbolRefAttr>("accumulator")
                       : FlatSymbolRefAttr{};
    auto sites =
        record ? record.getAs<DenseI64ArrayAttr>("sites") : DenseI64ArrayAttr{};
    if (!info || info.size() != 8 || !name || !sites)
      return module.emitError("invalid source eval transaction certificate");
    auto data = info.asArrayRef();
    if (data[1] < 0 || data[1] > UINT32_MAX || data[4] <= 0 || data[4] > 64 ||
        data[6] != TALOS_RT_REGION_NBA)
      return module.emitError("unsupported source eval transaction interval");
    auto capture = captures.find(data[1]);
    auto memory = memoryInventory.find(name.getValue());
    auto consumer = commitConsumers.find(data[1]);
    if (capture == captures.end() || !capture->second.exact ||
        !capture->second.stages || memory == memoryInventory.end() ||
        !memory->second.seen || !memory->second.exact ||
        rawAddressed.contains(name.getValue()) || sites.empty() ||
        consumer == commitConsumers.end() ||
        consumer->second != name.getValue())
      continue;
    // IEEE 1800-2023 4.9.4, 10.4.2: a private capture needs the typed
    // generated consumer that commits it at the common barrier. Source writer
    // ownership alone does not close an interval whose publication is
    // runtime-owned. Such a root would export at every NBA cut and retain the
    // accumulator round trip.
    const auto &lowered = capture->second;
    if (lowered.target[1] != data[2] || lowered.target[2] != data[4] ||
        !lowered.target[3] || lowered.target[4] != data[6] ||
        (data[5] && lowered.target[3] != data[5]) ||
        lowered.sites.size() != sites.size() ||
        !llvm::all_of(sites.asArrayRef(), [&](int64_t site) {
          return lowered.sites.contains(static_cast<uint64_t>(site));
        }))
      continue;
    candidates.push_back({static_cast<uint32_t>(data[1]), 0,
                          static_cast<uint64_t>(lowered.target[3]),
                          static_cast<uint32_t>(data[6]), bool(data[7]),
                          name.getValue().str()});
  }
  // Admit the complete proved set. Scratch is proportional to admitted scalar
  // payloads, and wrappers/word transfers use each function's transitive scope.
  // The readiness layout is sparse in canonical words; gaps cost no storage.
  SmallVector<PendingRoot> roots = candidates;
  llvm::sort(roots,
             [](const auto &a, const auto &b) { return a.root < b.root; });
  if (roots.empty())
    return success();
  SmallVector<PendingWord> words;
  DenseMap<uint32_t, unsigned> byWord;
  llvm::StringMap<unsigned> byAccumulator;
  DenseMap<uint32_t, unsigned> byRoot;
  for (auto [ordinal, root] : llvm::enumerate(roots)) {
    root.ordinal = ordinal;
    uint32_t canonicalWord = root.root / 64;
    if (words.empty() || words.back().canonicalWord != canonicalWord) {
      byWord.try_emplace(canonicalWord, words.size());
      words.push_back({canonicalWord, words.size() * 8});
    }
    auto &word = words.back();
    root.bitmapOffset = word.offset;
    word.mask |= uint64_t{1} << (root.root % 64);
    word.roots.push_back(ordinal);
    byAccumulator.try_emplace(root.accumulator, root.ordinal);
    byRoot.try_emplace(root.root, root.ordinal);
  }
  uint64_t frameBytes = words.size() * 8;
  for (auto &root : roots) {
    root.twoState = bool(native::get<native::TwoState>(module));
    root.payloadOffset = frameBytes;
    frameBytes += (root.transient ? 24 : 16) - (root.twoState ? 8 : 0);
  }

  // Freeze the transitive pure-call inventory before moving bodies. Outlined
  // computation is not itself a publication cut; an opaque descendant is.
  DenseSet<Operation *> opaque;
  DenseMap<Operation *, SmallVector<Operation *>> pureCallers;
  llvm::StringMap<unsigned> externalCuts;
  for (Operation *operation : reachable) {
    auto function = cast<LLVM::LLVMFuncOp>(operation);
    if (schedule::has<schedule::Field::EvalStateMetadataOnly>(function))
      continue;
    function.walk([&](LLVM::CallOp call) {
      if (pendingRuntimeTransparent(call))
        return;
      auto callee = call.getCallee() ? functions.lookup(*call.getCallee())
                                     : LLVM::LLVMFuncOp{};
      if (callee && reachable.contains(callee.getOperation()))
        pureCallers[callee.getOperation()].push_back(operation);
      else {
        opaque.insert(operation);
        ++externalCuts[call.getCallee().value_or("<indirect>")];
      }
    });
  }
  SmallVector<Operation *> opaqueWork(opaque.begin(), opaque.end());
  while (!opaqueWork.empty())
    for (Operation *caller : pureCallers[opaqueWork.pop_back_val()])
      if (opaque.insert(caller).second)
        opaqueWork.push_back(caller);
  if (native::has<native::DebugTiming>(module)) {
    SmallVector<StringRef> names;
    for (const auto &entry : externalCuts)
      names.push_back(entry.getKey());
    llvm::sort(names);
    for (StringRef name : names)
      llvm::errs() << "talos eval pending external cut: " << name
                   << " sites=" << externalCuts.lookup(name) << '\n';
  }

  DenseMap<Operation *, llvm::SmallBitVector> masks;
  DenseMap<Operation *, SmallVector<Operation *>> callers;
  for (Operation *operation : reachable) {
    auto function = cast<LLVM::LLVMFuncOp>(operation);
    auto &scope = masks.try_emplace(operation, roots.size()).first->second;
    // A metadata-only helper touches no pending root, so it is never cloned
    // and its convention need not be the default one.
    if (!schedule::has<schedule::Field::EvalStateMetadataOnly>(function) &&
        (function.isVarArg() || function.getCConv() != LLVM::CConv::C))
      return success();
    function.walk([&](Operation *nested) {
      if (auto call = dyn_cast<LLVM::CallOp>(nested)) {
        if (call.getCallee())
          if (auto callee = functions.lookup(*call.getCallee()))
            if (reachable.contains(callee.getOperation()))
              callers[callee.getOperation()].push_back(operation);
      }
      if (auto load = dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(nested))
        if (std::optional<uint32_t> pending = load.getPendingRoot())
          if (auto root = byRoot.find(*pending); root != byRoot.end())
            scope.set(root->second);
      if (std::optional<RecordAccess> access = recordAccess(nested)) {
        if (auto root = byAccumulator.find(access->accumulator);
            root != byAccumulator.end())
          scope.set(root->second);
        return;
      }
      std::optional<IndexAccess> index = indexAccess(nested);
      if (!index || !index->word || index->canonicalCapture)
        return;
      // A root's own index access concerns that root only.
      if (index->root) {
        if (auto root = byRoot.find(*index->root); root != byRoot.end())
          scope.set(root->second);
        return;
      }
      // Other logical index queries can select private captures even when
      // this function has no direct accumulator access. Producers for
      // canonical roots keep their canonical RMW interface.
      if (index->index == schedule::NBAIndex::DirtyRoots) {
        if (auto word = byWord.find(*index->word); word != byWord.end())
          for (unsigned ordinal : words[word->second].roots)
            scope.set(ordinal);
        return;
      }
      for (const auto &word : words)
        if (word.canonicalWord / 64 == *index->word)
          for (unsigned ordinal : word.roots)
            scope.set(ordinal);
    });
  }
  if (native::has<native::DebugTiming>(module)) {
    SmallVector<std::pair<unsigned, StringRef>> scopes;
    for (const auto &[operation, mask] : masks)
      if (mask.any())
        scopes.emplace_back(mask.count(),
                            cast<LLVM::LLVMFuncOp>(operation).getSymName());
    llvm::sort(scopes, [](auto a, auto b) {
      return a.first != b.first ? a.first > b.first : a.second < b.second;
    });
    for (auto [count, name] : ArrayRef(scopes).take_front(8))
      llvm::errs() << "talos eval pending direct scope: roots=" << count
                   << " function=" << name << '\n';
  }
  SmallVector<Operation *> pending;
  for (const auto &[operation, mask] : masks)
    if (mask.any())
      pending.push_back(operation);
  while (!pending.empty()) {
    Operation *callee = pending.pop_back_val();
    for (Operation *caller : callers[callee]) {
      llvm::SmallBitVector merged = masks[caller];
      merged |= masks[callee];
      if (merged != masks[caller]) {
        masks[caller] = merged;
        pending.push_back(caller);
      }
    }
  }

  // Changing an ABI must not silently discard a musttail/operand-bundle or
  // calling-convention contract. The appended pointer refers to caller-owned
  // storage, so even an ordinary tail-call promise is not valid for this ABI.
  for (Operation *operation : reachable) {
    bool supported = true;
    cast<LLVM::LLVMFuncOp>(operation).walk([&](LLVM::CallOp call) {
      auto callee = call.getCallee() ? functions.lookup(*call.getCallee())
                                     : LLVM::LLVMFuncOp{};
      if (callee && masks.lookup(callee.getOperation()).any())
        supported &=
            call.getCConv() == LLVM::CConv::C &&
            call.getTailCallKind() == LLVM::tailcallkind::TailCallKind::None &&
            call.getOpBundleSizes().empty();
    });
    if (!supported)
      return success();
  }

  SymbolTable symbols(module);
  DenseMap<Operation *, LLVM::LLVMFuncOp> cores;
  SmallVector<LLVM::LLVMFuncOp> originals;
  for (Operation *operation : reachable)
    if (masks.lookup(operation).any())
      originals.push_back(cast<LLVM::LLVMFuncOp>(operation));
  for (auto original : originals) {
    auto attrs = extendArgAttrs(context, original.getArgAttrsAttr(),
                                original.getNumArguments());
    auto core = moveBodyWithPointerArgument(original, ".__talos_pending", attrs,
                                            symbols);
    cores.try_emplace(original.getOperation(), core);
  }

  llvm::SmallBitVector allRoots(roots.size(), true);
  for (auto original : originals) {
    auto core = cores.lookup(original.getOperation());
    Value frame = core.getBody().front().getArguments().back();
    SmallVector<Operation *> operations;
    core.walk([&](Operation *operation) { operations.push_back(operation); });
    for (Operation *operation : operations) {
      OpBuilder builder(operation);
      Location loc = operation->getLoc();
      std::optional<IndexAccess> index = indexAccess(operation);
      // A runtime-held capture's root stays in the canonical index.
      if (index && index->canonicalCapture)
        continue;
      // A privatized root's own test or mark uses its private index bit; its
      // summary mark is the private index's own business.
      if (index && index->root && byRoot.contains(*index->root)) {
        const auto &root = roots[byRoot.lookup(*index->root)];
        if (index->index == schedule::NBAIndex::DirtyRoots) {
          Value bits = load(builder, loc, frame, root.bitmapOffset);
          if (!index->write) {
            operation->getResult(0).replaceAllUsesWith(
                selected(builder, loc, bits, root, root.root % 64));
          } else {
            store(builder, loc, frame, root.bitmapOffset,
                  LLVM::OrOp::create(
                      builder, loc, bits,
                      constant(builder, loc, uint64_t{1} << (root.root % 64))));
          }
          operation->erase();
        } else if (index->write) {
          operation->erase();
        }
        continue;
      }
      // A generated consumer's test of a privatized root's capture reads the
      // private index.
      auto access = recordAccess(operation);
      auto pendingTest =
          dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(operation);
      if (pendingTest && pendingTest.getPendingRoot() &&
          byRoot.contains(*pendingTest.getPendingRoot())) {
        const auto &root = roots[byRoot.lookup(*pendingTest.getPendingRoot())];
        Value pending =
            selected(builder, loc, load(builder, loc, frame, root.bitmapOffset),
                     root, root.root % 64);
        if (pendingTest.getType().isInteger(32))
          pending = LLVM::ZExtOp::create(
              builder, loc, pendingTest.getType(),
              LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::ne,
                                   pending, constant(builder, loc, 0)));
        pendingTest.replaceAllUsesWith(pending);
        pendingTest.erase();
        continue;
      }
      // The fields of a privatized root's record live in the frame.
      if (auto mapped = access ? byAccumulator.find(access->accumulator)
                               : byAccumulator.end();
          mapped != byAccumulator.end()) {
        const auto &root = roots[mapped->second];
        auto typedRead =
            dyn_cast<schedule::NativeNBAAccumulatorLoadOp>(operation);
        auto typedWrite =
            dyn_cast<schedule::NativeNBAAccumulatorStoreOp>(operation);
        std::optional<unsigned> lane;
        if (access->offset == 0 && access->field == NBAField::Value)
          lane = 0;
        else if (access->offset == 0 && access->field == NBAField::Unknown)
          lane = 1;
        else if (access->offset == 0 && access->field == NBAField::Transient)
          lane = 2;
        if (lane) {
          if ((*lane == 1 && root.twoState) ||
              (*lane == 2 && !root.transient)) {
            if (typedRead)
              typedRead.replaceAllUsesWith(constant(builder, loc, 0));
            operation->erase();
            continue;
          }
          Value local = byteGEP(builder, loc, frame, field(root, *lane));
          if (typedRead) {
            auto frameRead =
                LLVM::LoadOp::create(builder, loc, typedRead.getType(), local,
                                     typedRead.getAlignment());
            Value value = frameRead;
            if (*lane < 2 && root.mask != UINT64_MAX) {
              // Every certified capture writes this same mask. Bits outside
              // it are not a logical pending value: commit blends them from
              // CURRENT. Make that interface explicit so a partial stage need
              // not preserve unused accumulator bits across outlined calls
              // (IEEE 1800-2023 4.9.4, 10.4.2).
              builder.setInsertionPointAfter(frameRead);
              value = LLVM::AndOp::create(builder, loc, frameRead,
                                          constant(builder, loc, root.mask));
            }
            typedRead.replaceAllUsesWith(value);
          } else {
            Value value = typedWrite.getValue();
            if (*lane < 2 && root.mask != UINT64_MAX)
              value = LLVM::AndOp::create(builder, loc, value,
                                          constant(builder, loc, root.mask));
            LLVM::StoreOp::create(builder, loc, value, local,
                                  typedWrite.getAlignment());
          }
        } else if (typedWrite) {
          if (access->field == NBAField::Valid && access->offset == 0 &&
              zero(typedWrite.getValue())) {
            // Clearing captured validity consumes this local NBA, even when a
            // private batch clears its leaf word only afterward. Do not
            // republish an already committed capture at the next opaque cut
            // (IEEE 1800-2023 4.9.4, 10.4.2).
            store(builder, loc, frame, root.bitmapOffset,
                  LLVM::AndOp::create(
                      builder, loc,
                      load(builder, loc, frame, root.bitmapOffset),
                      constant(builder, loc,
                               ~(uint64_t{1} << (root.root % 64)))));
          }
        } else {
          Value replacement;
          if (access->field == NBAField::WriteMask && access->offset == 0) {
            if (typedRead.getAtCommit()) {
              replacement = constant(builder, loc, root.mask);
            } else {
              Value staged = selected(
                  builder, loc, load(builder, loc, frame, root.bitmapOffset),
                  root, 0);
              replacement = LLVM::SelectOp::create(
                  builder, loc,
                  LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::ne,
                                       staged, constant(builder, loc, 0)),
                  constant(builder, loc, root.mask), constant(builder, loc, 0));
            }
          } else if (access->field == NBAField::Valid && access->offset == 0) {
            // A caller can inspect validity outside the commit's selected
            // root branch (for example a knownness predicate). Preserve the
            // actual capture bit there too; the existence of a typed consumer
            // does not prove that this barrier staged the root (IEEE
            // 1800-2023 4.9.4, 10.4.2).
            replacement = LLVM::ZExtOp::create(
                builder, loc, typedRead.getType(),
                LLVM::ICmpOp::create(
                    builder, loc, LLVM::ICmpPredicate::ne,
                    selected(builder, loc,
                             load(builder, loc, frame, root.bitmapOffset), root,
                             0),
                    constant(builder, loc, 0)));
          } else {
            replacement = llvmConstant(builder, loc, typedRead.getType(),
                                       access->field == NBAField::ExecRegion &&
                                               access->offset == 0
                                           ? root.region
                                           : 1);
          }
          typedRead.replaceAllUsesWith(replacement);
        }
        operation->erase();
        continue;
      }
      // Other logical index queries see private bits too, and updates leave
      // privatized roots' bits to the private index.
      if (index && !index->root && index->word) {
        auto read = dyn_cast<schedule::NativeNBAIndexLoadOp>(operation);
        auto write = dyn_cast<schedule::NativeNBAIndexStoreOp>(operation);
        if (index->index == schedule::NBAIndex::DirtyRoots) {
          auto mappedWord = byWord.find(*index->word);
          if (mappedWord == byWord.end())
            continue;
          const auto &word = words[mappedWord->second];
          uint64_t localMask = word.mask;
          if (write && zero(write.getValue())) {
            store(builder, loc, frame, word.offset,
                  LLVM::AndOp::create(builder, loc,
                                      load(builder, loc, frame, word.offset),
                                      constant(builder, loc, ~localMask)));
          } else if (write) {
            // Reads use the complete logical index, including private bits.
            // That value may reach an update through CFG block arguments or
            // be shared by a selection and a read/modify/write. Project at
            // the write, rather than suppressing private bits at the read.
            // An index update without a root cannot create a canonical
            // capture for a localized root: its producers mark their root or
            // use an opaque captured-value ABI. Preserve canonical bits only
            // when the old canonical index and this update both retain them
            // (IEEE 1800-2023 4.9.4, 10.4.2: one owner and one consumption
            // per capture).
            Value prior = loadNBAIndex(
                builder, loc, schedule::NBAIndex::DirtyRoots, *index->word);
            Value canonical = LLVM::OrOp::create(
                builder, loc, prior, constant(builder, loc, ~localMask));
            write.getValueMutable().assign(
                LLVM::AndOp::create(builder, loc, write.getValue(), canonical));
          } else {
            OpBuilder after(read);
            after.setInsertionPointAfter(read);
            Value bits = load(after, loc, frame, word.offset);
            Value combined = LLVM::AndOp::create(
                after, loc, bits, constant(after, loc, localMask));
            Value old = read.getResult();
            auto merged = LLVM::OrOp::create(after, loc, old, combined);
            old.replaceAllUsesExcept(merged, merged);
          }
          continue;
        }
        Value privatePage = constant(builder, loc, 0);
        uint64_t localMask = 0;
        for (const auto &word : words) {
          if (word.canonicalWord / 64 != *index->word)
            continue;
          uint64_t bit = uint64_t{1} << (word.canonicalWord % 64);
          localMask |= bit;
          Value bits;
          if (read) {
            bits = load(builder, loc, frame, word.offset);
          } else {
            // A logical page may contain private-only leaf words. The
            // canonical summary indexes canonical payloads only; testing the
            // canonical leaf also preserves mixed private/canonical words
            // (IEEE 1800-2023 4.9.4, 10.4.2: coherent ownership at both
            // levels).
            bits = loadNBAIndex(builder, loc, schedule::NBAIndex::DirtyRoots,
                                word.canonicalWord);
          }
          Value present =
              LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::ne, bits,
                                   constant(builder, loc, 0));
          privatePage = LLVM::OrOp::create(
              builder, loc, privatePage,
              LLVM::SelectOp::create(builder, loc, present,
                                     constant(builder, loc, bit),
                                     constant(builder, loc, 0)));
        }
        if (!localMask)
          continue;
        if (read) {
          builder.setInsertionPointAfter(read);
          auto merged =
              LLVM::OrOp::create(builder, loc, read.getResult(), privatePage);
          read.getResult().replaceAllUsesExcept(merged, merged);
        } else {
          Value canonical = LLVM::OrOp::create(
              builder, loc, privatePage, constant(builder, loc, ~localMask));
          write.getValueMutable().assign(
              LLVM::AndOp::create(builder, loc, write.getValue(), canonical));
        }
        continue;
      }
      auto call = dyn_cast<LLVM::CallOp>(operation);
      if (!call)
        continue;
      auto callee = call.getCallee() ? functions.lookup(*call.getCallee())
                                     : LLVM::LLVMFuncOp{};
      if (callee && cores.contains(callee.getOperation())) {
        SmallVector<Value> args(call.getArgOperands());
        args.push_back(frame);
        auto replacement = LLVM::CallOp::create(
            builder, loc, call.getResultTypes(),
            cores.lookup(callee.getOperation()).getSymName(), args);
        if (call.getArgAttrsAttr())
          replacement.setArgAttrsAttr(extendArgAttrs(
              context, call.getArgAttrsAttr(), call.getArgOperands().size()));
        for (NamedAttribute attr : call->getAttrs())
          if (attr.getName() != "callee" && attr.getName() != "arg_attrs" &&
              attr.getName() != "var_callee_type" &&
              attr.getName() != "operandSegmentSizes" &&
              attr.getName() != "op_bundle_sizes")
            replacement->setAttr(attr.getName(), attr.getValue());
        call.replaceAllUsesWith(replacement.getResults());
        call.erase();
      } else if (callsNativeRuntime(
                     call, NativeRuntimeEntry::SchedulerPrepareEvalNba)) {
        Value bits = pendingBits(builder, loc, frame, words);
        Value localRegion = LLVM::SelectOp::create(
            builder, loc,
            LLVM::ICmpOp::create(builder, loc, LLVM::ICmpPredicate::ne, bits,
                                 constant(builder, loc, 0)),
            llvmConstant(builder, loc, builder.getI32Type(),
                         TALOS_RT_REGION_NBA),
            llvmConstant(builder, loc, builder.getI32Type(), UINT32_MAX));
        StringRef service =
            writable
                ? getNativeRuntimeSymbol(
                      NativeRuntimeEntry::SchedulerPrepareEvalNbaLocalWrite)
                : getNativeRuntimeSymbol(
                      NativeRuntimeEntry::SchedulerPrepareEvalNbaLocal);
        auto replacement = LLVM::CallOp::create(
            builder, loc, call.getResultTypes(), service,
            ValueRange{call.getArgOperands()[0], localRegion,
                       call.getArgOperands()[1]});
        call.replaceAllUsesWith(replacement.getResults());
        call.erase();
        // A successful TERMINATED result cancels the transaction's pending NBA
        // on finish; never export it again after final procedures have run.
        // Do not read the out parameter on a handoff/error (IEEE 1800-2023
        // 4.5, 20.2).
        builder.setInsertionPointAfter(replacement);
        Value ok = LLVM::ICmpOp::create(
            builder, loc, LLVM::ICmpPredicate::eq, replacement.getResult(),
            llvmConstant(builder, loc, builder.getI32Type(), TALOS_RT_OK));
        Block *head = builder.getInsertionBlock();
        Block *tail = head->splitBlock(builder.getInsertionPoint());
        Block *prepared = new Block;
        head->getParent()->getBlocks().insert(Region::iterator(tail), prepared);
        builder.setInsertionPointToEnd(head);
        LLVM::CondBrOp::create(builder, loc, ok, prepared, ValueRange{}, tail,
                               ValueRange{});
        builder.setInsertionPointToStart(prepared);
        Value barrier =
            LLVM::LoadOp::create(builder, loc, builder.getI32Type(),
                                 replacement.getArgOperands()[2], 4);
        Value ended = LLVM::ICmpOp::create(
            builder, loc, LLVM::ICmpPredicate::eq, barrier,
            llvmConstant(builder, loc, builder.getI32Type(),
                         TALOS_RT_EVAL_NBA_TERMINATED));
        for (const auto &word : words)
          store(builder, loc, frame, word.offset,
                LLVM::SelectOp::create(builder, loc, ended,
                                       constant(builder, loc, 0),
                                       load(builder, loc, frame, word.offset)));
        LLVM::BrOp::create(builder, loc, ValueRange{}, tail);
      } else if (!pendingRuntimeTransparent(call) &&
                 (!callee || !reachable.contains(callee.getOperation()) ||
                  opaque.contains(callee.getOperation()))) {
        // Cold/fine/opaque execution retains the existing captured NBA ABI.
        // IEEE 1800-2023 38.15, 38.34: no private continuation is exposed to
        // foreign code.
        transfer(builder, loc, frame, roots, words, allRoots, true, writable);
        builder.setInsertionPointAfter(call);
        transfer(builder, loc, frame, roots, words, allRoots, false, writable);
      }
    }

    // Keep every original actor/helper symbol and signature for fine/cold
    // ingress. Only generated calls use the extra private, nonescaping slot.
    OpBuilder builder(original);
    Location loc = original.getLoc();
    Block *entry = original.addEntryBlock(builder);
    builder.setInsertionPointToStart(entry);
    Value local =
        entryAlloca(builder, loc, builder.getI64Type(), frameBytes / 8, 8);
    for (const auto &word : words)
      store(builder, loc, local, word.offset, constant(builder, loc, 0));
    const auto &scope = masks[original.getOperation()];
    // Unrelated payloads never need initialization. A later opaque adoption
    // writes a payload before setting its bit. Initialize this closure's lanes
    // for predicates and partial-stage RMWs that execute without a capture.
    for (const auto &root : roots)
      if (scope.test(root.ordinal))
        for (unsigned lane = 0; lane != (root.transient ? 3u : 2u); ++lane)
          if (lane != 1 || !root.twoState)
            store(builder, loc, local, field(root, lane),
                  constant(builder, loc, 0));
    transfer(builder, loc, local, roots, words,
             masks.lookup(original.getOperation()), false, writable);
    SmallVector<Value> args(entry->getArguments());
    args.push_back(local);
    auto call = LLVM::CallOp::create(
        builder, loc,
        isa<LLVM::LLVMVoidType>(original.getFunctionType().getReturnType())
            ? TypeRange{}
            : TypeRange{original.getFunctionType().getReturnType()},
        core.getSymName(), args);
    transfer(builder, loc, local, roots, words,
             masks.lookup(original.getOperation()), true, writable);
    LLVM::ReturnOp::create(builder, loc, call.getResults());
  }
  declareNativeRuntime(
      module, writable ? NativeRuntimeEntry::SchedulerPrepareEvalNbaLocalWrite
                       : NativeRuntimeEntry::SchedulerPrepareEvalNbaLocal);
  declareNativeRuntime(
      module, writable ? NativeRuntimeEntry::StaticNbaSpecializationGuardWrite
                       : NativeRuntimeEntry::StaticNbaSpecializationGuard);
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos eval local pending roots: " << roots.size()
                 << " cores=" << cores.size()
                 << " fixed-candidates=" << candidates.size()
                 << " bitmap-words=" << words.size()
                 << " frame-bytes=" << frameBytes << '\n';
  return success();
}

} // namespace talos::detail
