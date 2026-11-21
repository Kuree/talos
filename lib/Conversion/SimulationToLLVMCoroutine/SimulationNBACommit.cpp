//===- SimulationNBACommit.cpp - Table-driven scalar NBA commits ----------===//

#include "NativeStateAccess.h"
#include "SimulationAOTPlanning.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"

#include <optional>

using namespace mlir;

namespace talos::detail {

void materializeNativeNBAMetadataExport(
    ModuleOp module, const NativeStaticNBAPlan &plan,
    ArrayRef<SmallVector<uint32_t>> rootsByWord) {
  if (schedule::has<schedule::Field::EvalRuntimeCalendar>(module))
    return;
  SmallVector<std::pair<uint32_t, SmallVector<uint32_t>>> words;
  for (auto [word, roots] : llvm::enumerate(rootsByWord)) {
    SmallVector<uint32_t> compact;
    for (uint32_t root : roots)
      if (plan.generatedCompactStages[root])
        compact.push_back(root);
    if (!compact.empty())
      words.push_back({static_cast<uint32_t>(word), std::move(compact)});
  }
  if (words.empty())
    return;
  // IEEE 1800-2023 4.5 and 10.4.2: switching barrier executors must carry
  // every captured NBA, including siblings of an exceptional four-state
  // owner. Only the dirty index is authoritative for compact captures. Export
  // its derived fields at the boundary, without applying or resampling data.
  // The runtime reads those fields for pending work, barrier regions and
  // handoffs, so stale exported validity must be cleared as well. Visit only
  // words with a compact dirty bit or a previously exported root.
  OpBuilder b(module.getContext());
  auto loc = module.getLoc();
  auto ptr = LLVM::LLVMPointerType::get(module.getContext());
  auto i8 = b.getI8Type(), i32 = b.getI32Type(), i64 = b.getI64Type();
  constexpr StringLiteral name = "__talos_eval_export_nba_metadata_v1";
  constexpr StringLiteral exportedName = "__talos_eval_nba_exported_roots_v1";
  constexpr StringLiteral liveName = "__talos_eval_nba_exported_live_v1";
  b.setInsertionPointToStart(module.getBody());
  LLVM::GlobalOp::create(b, loc, LLVM::LLVMArrayType::get(i64, words.size()),
                         false, LLVM::Linkage::Internal, exportedName,
                         b.getZeroAttr(RankedTensorType::get(
                             {static_cast<int64_t>(words.size())}, i64)),
                         8);
  LLVM::GlobalOp::create(b, loc, i8, false, LLVM::Linkage::Internal, liveName,
                         b.getI8IntegerAttr(0), 1);
  b.setInsertionPointToEnd(module.getBody());
  auto function = LLVM::LLVMFuncOp::create(
      b, loc, name,
      LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(module.getContext()),
                                  {}, false));
  function.setLinkage(LLVM::Linkage::Internal);
  Block *current = function.addEntryBlock(b);
  b.setInsertionPointToStart(current);
  Value dirty =
      LLVM::AddressOfOp::create(b, loc, ptr, "__talos_aot_nba_dirty_roots_v1");
  Value summary = LLVM::AddressOfOp::create(b, loc, ptr,
                                            "__talos_aot_nba_dirty_summary_v1");
  Value exported = LLVM::AddressOfOp::create(b, loc, ptr, exportedName);
  Value live = llvmConstant(b, loc, i64, 0);
  for (auto [slot, entry] : llvm::enumerate(words)) {
    auto &[word, roots] = entry;
    uint64_t compactMask = 0;
    for (uint32_t root : roots)
      compactMask |= uint64_t{1} << (root % 64);
    // Hoist operands that build IR: argument evaluation order is
    // unspecified (MSVC goes right to left) and tests pin the emitted order.
    Value dirtyWord = LLVM::LoadOp::create(
        b, loc, i64, byteGEP(b, loc, dirty, uint64_t{word} * 8), 8);
    Value compact = llvmConstant(b, loc, i64, compactMask);
    Value bits = arith::AndIOp::create(b, loc, dirtyWord, compact);
    Value shadowAddress = byteGEP(b, loc, exported, uint64_t{slot} * 8);
    Value previous = LLVM::LoadOp::create(b, loc, i64, shadowAddress, 8);
    Block *visit = new Block, *next = new Block;
    next->addArgument(i64, loc);
    function.getBody().push_back(visit);
    function.getBody().push_back(next);
    Value changed = arith::OrIOp::create(b, loc, bits, previous);
    Value zero = llvmConstant(b, loc, i64, 0);
    cf::CondBranchOp::create(
        b, loc,
        arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne, changed, zero),
        visit, ValueRange{}, next, ValueRange{live});
    b.setInsertionPointToStart(visit);
    for (uint32_t root : roots) {
      Value selected = arith::AndIOp::create(
          b, loc, bits, llvmConstant(b, loc, i64, uint64_t{1} << (root % 64)));
      Value present =
          arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne, selected,
                                llvmConstant(b, loc, i64, 0));
      Value accumulator = schedule::NativeNBAAccumulatorAddressOp::create(
          b, loc, plan.generatedAccumulators[root]);
      Value mask =
          plan.generatedFixedWriteMasks[root]
              ? llvmConstant(b, loc, i64, plan.generatedFixedWriteMasks[root])
              : schedule::NativeNBAAccumulatorLoadOp::create(
                    b, loc, i64, accumulator, NBAField::WriteMask, 0, 8)
                    .getResult();
      schedule::NativeNBAAccumulatorStoreOp::create(
          b, loc,
          arith::SelectOp::create(b, loc, present, mask,
                                  llvmConstant(b, loc, i64, 0)),
          accumulator, NBAField::WriteMask, 0, 8);
      Value valid = arith::ExtUIOp::create(b, loc, i32, present);
      schedule::NativeNBAAccumulatorStoreOp::create(b, loc, valid, accumulator,
                                                    NBAField::Valid, 0, 4);
      Value region =
          llvmConstant(b, loc, i32, plan.generatedCommitRegions[root]);
      schedule::NativeNBAAccumulatorStoreOp::create(b, loc, region, accumulator,
                                                    NBAField::ExecRegion, 0, 4);
      Value page = byteGEP(b, loc, summary, uint64_t{root / 4096} * 8);
      Value old = LLVM::LoadOp::create(b, loc, i64, page, 8);
      Value pageBit =
          llvmConstant(b, loc, i64, uint64_t{1} << ((root / 64) % 64));
      Value noPageBit = llvmConstant(b, loc, i64, 0);
      Value added =
          arith::SelectOp::create(b, loc, present, pageBit, noPageBit);
      LLVM::StoreOp::create(b, loc, arith::OrIOp::create(b, loc, old, added),
                            page, 8);
    }
    LLVM::StoreOp::create(b, loc, bits, shadowAddress, 8);
    cf::BranchOp::create(b, loc, next,
                         ValueRange{arith::OrIOp::create(b, loc, live, bits)});
    b.setInsertionPointToStart(next);
    live = next->getArgument(0);
  }
  Value noneLive = llvmConstant(b, loc, i64, 0);
  Value anyLive = arith::ExtUIOp::create(
      b, loc, i8,
      arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne, live, noneLive));
  LLVM::StoreOp::create(b, loc, anyLive,
                        LLVM::AddressOfOp::create(b, loc, ptr, liveName), 1);
  LLVM::ReturnOp::create(b, loc, ValueRange{});
  // Export while eval still owns its captures: on return, or immediately
  // before its exceptional canonical barrier. The runtime callback also
  // drains runtime-owned accumulators, whose dirty bits do not prove a live
  // generated capture. Exporting there would resurrect a consumed shadow.
  //
  // A coordinator that returns without yielding has committed its staging
  // (talos_rt_native_schedule_plan.runtime_yield), so its return only needs
  // to clear fields an earlier export left live. A yield keeps staging
  // intact for the runtime to inspect and must export it.
  constexpr StringLiteral guardedName =
      "__talos_eval_export_nba_metadata_on_return_v1";
  b.setInsertionPointToEnd(module.getBody());
  auto guarded = LLVM::LLVMFuncOp::create(
      b, loc, guardedName,
      LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(module.getContext()),
                                  {}, false));
  guarded.setLinkage(LLVM::Linkage::Internal);
  Block *guardEntry = guarded.addEntryBlock(b);
  Block *exportBlock = new Block, *done = new Block;
  guarded.getBody().push_back(exportBlock);
  guarded.getBody().push_back(done);
  b.setInsertionPointToStart(guardEntry);
  Value needed = arith::CmpIOp::create(
      b, loc, arith::CmpIPredicate::ne,
      LLVM::LoadOp::create(b, loc, i8,
                           LLVM::AddressOfOp::create(b, loc, ptr, liveName), 1),
      llvmConstant(b, loc, i8, 0));
  if (module.lookupSymbol(evalRuntimeYieldName)) {
    Value word = LLVM::LoadOp::create(
        b, loc, i32, LLVM::AddressOfOp::create(b, loc, ptr, evalRuntimeYieldName),
        alignof(uint32_t));
    for (uint32_t yielded :
         {uint32_t{TALOS_RT_RUNTIME_YIELD_STAGED},
          uint32_t{TALOS_RT_RUNTIME_YIELD_DEFERRED}})
      needed = arith::OrIOp::create(
          b, loc, needed,
          arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, word,
                                llvmConstant(b, loc, i32, yielded)));
  }
  cf::CondBranchOp::create(b, loc, needed, exportBlock, ValueRange{}, done,
                           ValueRange{});
  b.setInsertionPointToStart(exportBlock);
  LLVM::CallOp::create(b, loc, TypeRange{}, name, ValueRange{});
  cf::BranchOp::create(b, loc, done);
  b.setInsertionPointToStart(done);
  LLVM::ReturnOp::create(b, loc, ValueRange{});
  if (auto dispatch = module.lookupSymbol<LLVM::LLVMFuncOp>(evalDispatchName))
    dispatch.walk([&](LLVM::ReturnOp ret) {
      b.setInsertionPoint(ret);
      LLVM::CallOp::create(b, loc, TypeRange{}, guardedName, ValueRange{});
    });
  module.walk([&](LLVM::CallOp call) {
    if (call.getCallee() != "__talos_aot_runtime_nba_commit_v1")
      return;
    b.setInsertionPoint(call);
    LLVM::CallOp::create(b, loc, TypeRange{}, name, ValueRange{});
  });
}

void emitScalarNBACommitLoop(OpBuilder &b, ModuleOp module,
                             LLVM::LLVMFuncOp function, Block *exit,
                             Value region, const NativeStaticNBAPlan &plan,
                             ArrayRef<SmallVector<uint32_t>> rootsByWord,
                             ArrayRef<talos_rt_static_fanout_entry> fanout,
                             Value activatedNodes, Value activatedDirect,
                             unsigned directWords) {
  auto loc = function.getLoc();
  auto *context = b.getContext();
  auto i32 = b.getI32Type(), i64 = b.getI64Type();
  auto ptr = LLVM::LLVMPointerType::get(context);
  auto c = [&](uint64_t n) -> Value { return llvmConstant(b, loc, i64, n); };
  auto block = [&]() {
    auto *result = new Block;
    function.getBody().getBlocks().insert(Region::iterator(exit), result);
    return result;
  };
  auto address = [&](StringRef name) -> Value {
    return LLVM::AddressOfOp::create(b, loc, ptr, name);
  };
  auto gep = [&](Value base, Type type, Value index) -> Value {
    return LLVM::GEPOp::create(b, loc, ptr, type, base, ValueRange{index});
  };
  struct IntegerColumn {
    std::string name;
    std::optional<uint64_t> uniform;
  };
  auto table = [&](StringRef suffix, ArrayRef<uint64_t> data) -> IntegerColumn {
    // Specialize only when every entry agrees, including unselected roots.
    // Doing this before native partitioning keeps the constant available to
    // simplification. The NBA order, four-state values and publication boundary
    // are unchanged (IEEE 1800-2023 4.3, 4.6, 6.3.1, 10.4.2).
    if (!data.empty() && llvm::all_equal(data))
      return {{}, data.front()};
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    std::string name = ("__talos_eval_nba_commit_" + suffix).str();
    auto tensor = RankedTensorType::get({int64_t(data.size())}, i64);
    LLVM::GlobalOp::create(b, loc, LLVM::LLVMArrayType::get(i64, data.size()),
                           true, LLVM::Linkage::Internal, name,
                           DenseIntElementsAttr::get(tensor, data), 8);
    return {std::move(name), std::nullopt};
  };
  auto load = [&](const IntegerColumn &column, Value index) -> Value {
    if (column.uniform)
      return c(*column.uniform);
    return LLVM::LoadOp::create(b, loc, i64,
                                gep(address(column.name), i64, index), 8);
  };
  auto band = [&](Value a, Value d) -> Value {
    return arith::AndIOp::create(b, loc, a, d);
  };
  auto bor = [&](Value a, Value d) -> Value {
    return arith::OrIOp::create(b, loc, a, d);
  };
  auto inv = [&](Value a) -> Value {
    return arith::XOrIOp::create(b, loc, a, c(UINT64_MAX));
  };
  auto cmp = [&](arith::CmpIPredicate predicate, Value a, Value d) -> Value {
    return arith::CmpIOp::create(b, loc, predicate, a, d);
  };
  auto eq = [&](Value a, Value d) {
    return cmp(arith::CmpIPredicate::eq, a, d);
  };
  auto select = [&](Value condition, Value yes, Value no) -> Value {
    return arith::SelectOp::create(b, loc, condition, yes, no);
  };

  // IEEE 1800-2023 4.5, 4.6, 10.4.2: only the existing merge-safe scalar
  // roots use this path. Visit their dirty bits in the same root order and
  // publish activation after the barrier. Ordered records drain separately.
  size_t count = plan.roots.size();
  SmallVector<uint64_t> masks(rootsByWord.size()), offsets(count),
      widths(count), shifts(count), classes(count), regions(count),
      fixedMasks(count), clear(count), transients(count), starts(count),
      ends(count);
  SmallVector<uint64_t> watchMasks, edges, destinations, direct;
  for (auto [word, roots] : llvm::enumerate(rootsByWord))
    for (uint32_t index : roots) {
      const auto &root = plan.roots[index];
      masks[word] |= uint64_t{1} << (index % 64);
      offsets[index] = plan.generatedOffsets[index] / 8;
      shifts[index] = plan.generatedOffsets[index] % 8;
      widths[index] = root.bit_width == 64
                          ? UINT64_MAX
                          : (uint64_t{1} << root.bit_width) - 1;
      unsigned bits = shifts[index] + root.bit_width;
      classes[index] = bits <= 8    ? 8
                       : bits <= 16 ? 16
                       : bits <= 32 ? 32
                       : bits <= 64 ? 64
                                    : 72;
      regions[index] = plan.generatedCommitRegions[index];
      fixedMasks[index] = plan.generatedFixedWriteMasks[index];
      clear[index] = !plan.generatedCompactStages[index] ||
                     (!fixedMasks[index] && !plan.generatedFullRootStages[index]);
      transients[index] = plan.trackTransients[index] ? widths[index] : 0;
      starts[index] = watchMasks.size();
      for (const auto &entry : fanout) {
        if (entry.static_state != root.static_state ||
            entry.low_bit >= root.bit_width)
          continue;
        uint64_t high =
            std::min(root.bit_width, entry.low_bit + entry.bit_width);
        if (entry.low_bit >= high)
          continue;
        uint64_t width = high - entry.low_bit;
        watchMasks.push_back(
            (width == 64 ? UINT64_MAX : (uint64_t{1} << width) - 1)
            << entry.low_bit);
        edges.push_back(entry.edge);
        bool isDirect = (entry.reserved & TALOS_RT_FANOUT_ROUTE_MASK) ==
                            TALOS_RT_FANOUT_DIRECT &&
                        entry.merged_bit < uint64_t(directWords) * 64;
        direct.push_back(isDirect);
        destinations.push_back(isDirect ? entry.merged_bit
                                        : entry.compute_node);
      }
      ends[index] = watchMasks.size();
    }
  // IEEE 1800-2023 6.3.1: a commit that leaves X/Z in a root reports it to
  // the unknown summary. When each committed root lies in one pattern-free
  // summary root, the loop sets that root's bit itself instead of asking the
  // runtime to search for the roots of a dynamic address.
  SmallVector<uint64_t> summaryWords(count), summaryMasks(count);
  bool inlineSummary = false;
  if (auto summaryRoots =
          module.lookupSymbol<LLVM::GlobalOp>(unknownSummaryRootsName);
      summaryRoots && module.lookupSymbol<LLVM::GlobalOp>(unknownSummaryName))
    if (auto values = dyn_cast_or_null<DenseIntElementsAttr>(
            summaryRoots.getValueOrNull())) {
      SmallVector<uint64_t> records;
      for (const APInt &value : values.getValues<APInt>())
        records.push_back(value.getZExtValue());
      // (begin, end, bit, has pattern), sorted by begin. The roots table is
      // (offset, width, pattern slice) records whose index is the summary bit,
      // as materializeUnknownSummary writes and UnknownSummaryWriteInputs
      // reads it; the pattern count is the slice's upper 32 bits.
      struct SummaryRoot {
        uint64_t begin, end, bit;
        bool pattern;
      };
      SmallVector<SummaryRoot> summary;
      for (size_t index = 0; index + 2 < records.size(); index += 3)
        summary.push_back({records[index], records[index] + records[index + 1],
                           index / 3, (records[index + 2] >> 32) != 0});
      llvm::sort(summary, [](const SummaryRoot &left, const SummaryRoot &right) {
        return left.begin < right.begin;
      });
      inlineSummary = records.size() % 3 == 0;
      for (const auto &roots : rootsByWord)
        for (uint32_t index : roots) {
          if (!inlineSummary)
            break;
          uint64_t begin = plan.generatedOffsets[index];
          uint64_t end = begin + plan.roots[index].bit_width;
          auto first = llvm::partition_point(
              summary, [&](const SummaryRoot &root) { return root.end <= begin; });
          unsigned overlapping = 0;
          for (auto it = first; it != summary.end() && it->begin < end; ++it) {
            ++overlapping;
            if (it->pattern)
              inlineSummary = false;
            summaryWords[index] = it->bit / 64;
            summaryMasks[index] = uint64_t{1} << (it->bit % 64);
          }
          if (overlapping > 1)
            inlineSummary = false;
        }
    }
  auto maskTable = table("masks_v1", masks);
  auto offsetTable = table("offsets_v1", offsets);
  auto widthTable = table("widths_v1", widths);
  auto shiftTable = table("shifts_v1", shifts);
  auto classTable = table("classes_v1", classes);
  auto regionTable = table("regions_v1", regions);
  auto fixedTable = table("fixed_masks_v1", fixedMasks);
  auto clearTable = table("clear_v1", clear);
  auto transientTable = table("transients_v1", transients);
  auto startTable = table("starts_v1", starts);
  auto endTable = table("ends_v1", ends);
  auto watchTable = table("watch_masks_v1", watchMasks);
  auto edgeTable = table("edges_v1", edges);
  auto destinationTable = table("destinations_v1", destinations);
  auto directTable = table("direct_v1", direct);
  std::optional<IntegerColumn> summaryWordTable, summaryMaskTable;
  if (inlineSummary) {
    summaryWordTable = table("summary_words_v1", summaryWords);
    summaryMaskTable = table("summary_masks_v1", summaryMasks);
  }
  // Accumulators are also consumed by runtime handoffs. Keep their ABI storage
  // and use a constant pointer column instead of introducing a shadow payload.
  std::string accumulatorTable = "__talos_eval_nba_commit_accumulators_v1";
  {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    auto type = LLVM::LLVMArrayType::get(ptr, count);
    auto global =
        LLVM::GlobalOp::create(b, loc, type, true, LLVM::Linkage::Internal,
                               accumulatorTable, Attribute{});
    auto *init = new Block;
    global.getInitializerRegion().push_back(init);
    b.setInsertionPointToStart(init);
    Value value = LLVM::ZeroOp::create(b, loc, type);
    for (auto [word, roots] : llvm::enumerate(rootsByWord))
      for (uint32_t index : roots)
        value = LLVM::InsertValueOp::create(
            b, loc, value, address(plan.generatedAccumulators[index]),
            ArrayRef<int64_t>{index});
    LLVM::ReturnOp::create(b, loc, value);
  }

  auto *wordHead = block(), *wordLoad = block(), *rootHead = block(),
       *rootLoad = block(), *advanceWord = block(), *commit = block(),
       *publish = block(), *reset = block(), *watchHead = block(),
       *watchBody = block(), *watchStore = block(), *watchNext = block();
  wordHead->addArgument(i64, loc);
  rootHead->addArgument(i64, loc);
  watchHead->addArgument(i64, loc);
  for (unsigned i = 0; i < 4; ++i)
    publish->addArgument(i64, loc);
  cf::BranchOp::create(b, loc, wordHead, ValueRange{c(0)});
  b.setInsertionPointToStart(wordHead);
  Value word = wordHead->getArgument(0);
  cf::CondBranchOp::create(
      b, loc, cmp(arith::CmpIPredicate::ult, word, c(masks.size())), wordLoad,
      ValueRange{}, exit, ValueRange{});
  b.setInsertionPointToStart(wordLoad);
  Value dirtyAddress =
      gep(address("__talos_aot_nba_dirty_roots_v1"), i64, word);
  Value dirty = LLVM::LoadOp::create(b, loc, i64, dirtyAddress, 8);
  Value selectedMask = load(maskTable, word);
  cf::BranchOp::create(b, loc, rootHead, ValueRange{band(dirty, selectedMask)});
  b.setInsertionPointToStart(rootHead);
  Value remaining = rootHead->getArgument(0);
  cf::CondBranchOp::create(b, loc, eq(remaining, c(0)), advanceWord,
                           ValueRange{}, rootLoad, ValueRange{});
  b.setInsertionPointToStart(advanceWord);
  cf::BranchOp::create(b, loc, wordHead,
                       ValueRange{arith::AddIOp::create(b, loc, word, c(1))});
  b.setInsertionPointToStart(rootLoad);
  Value bit = LLVM::CountTrailingZerosOp::create(b, loc, i64, remaining, true);
  Value index = arith::AddIOp::create(
      b, loc, arith::ShLIOp::create(b, loc, word, c(6)), bit);
  Value rest = band(remaining, arith::SubIOp::create(b, loc, remaining, c(1)));
  Value accumulator = LLVM::LoadOp::create(
      b, loc, ptr, gep(address(accumulatorTable), ptr, index));
  auto field64 = [&](NBAField field) -> Value {
    return schedule::NativeNBAAccumulatorLoadOp::create(
        b, loc, i64, accumulator, field, 0, 8);
  };
  auto region64 = LLVM::ZExtOp::create(b, loc, i64, region);
  Value fixedRegion = load(regionTable, index);
  Value storedRegion = LLVM::ZExtOp::create(
      b, loc, i64,
      schedule::NativeNBAAccumulatorLoadOp::create(b, loc, i32, accumulator,
                                                   NBAField::ExecRegion, 0, 4));
  Value valid = schedule::NativeNBAAccumulatorLoadOp::create(
      b, loc, i32, accumulator, NBAField::Valid, 0, 4);
  Value regionMatches = select(
      eq(fixedRegion, c(UINT32_MAX)),
      band(eq(storedRegion, region64),
           cmp(arith::CmpIPredicate::ne, valid, llvmConstant(b, loc, i32, 0))),
      eq(fixedRegion, region64));
  cf::CondBranchOp::create(b, loc, regionMatches, commit, ValueRange{},
                           rootHead, ValueRange{rest});
  b.setInsertionPointToStart(commit);
  // Match the unrolled barrier: consume only the roots committed here. A
  // root staged in the canonical accumulator by a runtime-executed actor keeps
  // its bit for the canonical index owner (IEEE 1800-2023 4.9.4, 10.4.2).
  LLVM::StoreOp::create(b, loc,
                        band(LLVM::LoadOp::create(b, loc, i64, dirtyAddress, 8),
                             inv(arith::ShLIOp::create(b, loc, c(1), bit))),
                        dirtyAddress, 8);
  Value offset = load(offsetTable, index), shift = load(shiftTable, index),
        widthMask = load(widthTable, index),
        fixedMask = load(fixedTable, index);
  Value writeMask =
      select(eq(fixedMask, c(0)), band(field64(NBAField::WriteMask), widthMask),
             fixedMask);
  Value stagedValue = field64(NBAField::Value);
  // The two-state commit variants read staged X/Z data as zero.
  Value stagedUnknown = field64(NBAField::Unknown);
  // Each plane's window at the root's byte offset.
  constexpr auto valuePlane = schedule::StatePlane::Value;
  constexpr auto unknownPlane = schedule::StatePlane::Unknown;
  SmallVector<APInt> cases;
  SmallVector<Block *> bodies;
  SmallVector<ValueRange> operands;
  constexpr unsigned storageWidths[] = {8, 16, 32, 64, 72};
  for (unsigned bits : storageWidths) {
    cases.emplace_back(64, bits);
    bodies.push_back(block());
    operands.push_back({});
  }
  LLVM::SwitchOp::create(b, loc, load(classTable, index), bodies.back(),
                         ValueRange{}, cases, bodies, operands);
  for (auto [ordinal, bits] : llvm::enumerate(storageWidths)) {
    b.setInsertionPointToStart(bodies[ordinal]);
    auto type = b.getIntegerType(bits);
    auto resize = [&](Value value, Type target) -> Value {
      unsigned from = cast<IntegerType>(value.getType()).getWidth();
      unsigned to = cast<IntegerType>(target).getWidth();
      if (from == to)
        return value;
      if (from < to)
        return LLVM::ZExtOp::create(b, loc, target, value);
      return LLVM::TruncOp::create(b, loc, target, value);
    };
    Value oldRaw = schedule::NativeStateLoadOp::create(b, loc, type, valuePlane,
                                                       offset, 0, 1)
                       ->getResult(0);
    Value unknownRaw = schedule::NativeStateLoadOp::create(
                           b, loc, type, unknownPlane, offset, 0, 1)
                           ->getResult(0);
    Value typedShift = resize(shift, type);
    auto extract = [&](Value raw) {
      return band(resize(arith::ShRUIOp::create(b, loc, raw, typedShift), i64),
                  widthMask);
    };
    Value oldValue = extract(oldRaw), oldUnknown = extract(unknownRaw);
    Value newValue =
        bor(band(oldValue, inv(writeMask)), band(stagedValue, writeMask));
    Value newUnknown =
        bor(band(oldUnknown, inv(writeMask)), band(stagedUnknown, writeMask));
    Value mask =
        arith::ShLIOp::create(b, loc, resize(widthMask, type), typedShift);
    auto store = [&, &bits = bits](Value raw, Value value,
                                   schedule::StatePlane plane) {
      Value keep = arith::XOrIOp::create(
          b, loc, mask,
          LLVM::ConstantOp::create(
              b, loc, type, b.getIntegerAttr(type, APInt::getAllOnes(bits))));
      Value positioned =
          arith::ShLIOp::create(b, loc, resize(value, type), typedShift);
      return schedule::NativeStateStoreOp::create(
          b, loc, bor(band(raw, keep), band(positioned, mask)), plane, offset,
          0, 1);
    };
    store(oldRaw, newValue, valuePlane);
    Operation *unknownStore = store(unknownRaw, newUnknown, unknownPlane);
    if (inlineSummary)
      detail::setNativeSummaryReported(unknownStore);
    cf::BranchOp::create(
        b, loc, publish,
        ValueRange{oldValue, oldUnknown, newValue, newUnknown});
  }
  b.setInsertionPointToStart(publish);
  Value oldValue = publish->getArgument(0),
        oldUnknown = publish->getArgument(1),
        newValue = publish->getArgument(2),
        newUnknown = publish->getArgument(3);
  if (inlineSummary) {
    // Only bits of this root are written; unknown neighbors are preserved, so
    // only this root can have become X/Z.
    Value summaryWord = gep(address(unknownSummaryName), i64,
                            load(*summaryWordTable, index));
    Value reported = LLVM::LoadOp::create(b, loc, i64, summaryWord, 8);
    Value hasUnknown = arith::CmpIOp::create(
        b, loc, arith::CmpIPredicate::ne, newUnknown, c(0));
    Value bit = arith::SelectOp::create(b, loc, hasUnknown,
                                        load(*summaryMaskTable, index), c(0));
    LLVM::StoreOp::create(b, loc, bor(reported, bit), summaryWord, 8);
  }
  Value transient = field64(NBAField::Transient);
  Value changed =
      bor(bor(arith::XOrIOp::create(b, loc, oldValue, newValue),
              arith::XOrIOp::create(b, loc, oldUnknown, newUnknown)),
          band(transient, load(transientTable, index)));
  schedule::NativeNBAAccumulatorStoreOp::create(b, loc, c(0), accumulator,
                                                NBAField::Transient, 0, 8);
  Value oldZero = band(inv(oldUnknown), inv(oldValue)),
        oldOne = band(inv(oldUnknown), oldValue),
        newZero = band(inv(newUnknown), inv(newValue)),
        newOne = band(inv(newUnknown), newValue);
  Value posedge = bor(band(oldZero, inv(newZero)), band(oldUnknown, newOne));
  Value negedge = bor(band(oldOne, inv(newOne)), band(oldUnknown, newZero));
  Value start = load(startTable, index), end = load(endTable, index);
  cf::CondBranchOp::create(b, loc, eq(load(clearTable, index), c(0)), watchHead,
                           ValueRange{start}, reset, ValueRange{});
  b.setInsertionPointToStart(reset);
  schedule::NativeNBAAccumulatorStoreOp::create(b, loc, c(0), accumulator,
                                                NBAField::WriteMask, 0, 8);
  schedule::NativeNBAAccumulatorStoreOp::create(
      b, loc, llvmConstant(b, loc, i32, 0), accumulator, NBAField::Valid, 0, 4);
  cf::BranchOp::create(b, loc, watchHead, ValueRange{start});
  b.setInsertionPointToStart(watchHead);
  Value watcher = watchHead->getArgument(0);
  cf::CondBranchOp::create(b, loc, cmp(arith::CmpIPredicate::ult, watcher, end),
                           watchBody, ValueRange{}, rootHead, ValueRange{rest});
  b.setInsertionPointToStart(watchBody);
  Value edge = load(edgeTable, watcher);
  Value observed =
      select(eq(edge, c(TALOS_RT_WAIT_EDGE_POSEDGE)), posedge,
             select(eq(edge, c(TALOS_RT_WAIT_EDGE_NEGEDGE)), negedge,
                    select(eq(edge, c(TALOS_RT_WAIT_EDGE_BOTH)),
                           bor(posedge, negedge), changed)));
  cf::CondBranchOp::create(b, loc,
                           eq(band(observed, load(watchTable, watcher)), c(0)),
                           watchNext, ValueRange{}, watchStore, ValueRange{});
  b.setInsertionPointToStart(watchStore);
  Value destination = load(destinationTable, watcher);
  Value target;
  if (activatedNodes && activatedDirect)
    target = select(eq(load(directTable, watcher), c(0)), activatedNodes,
                    activatedDirect);
  else
    target = activatedDirect ? activatedDirect : activatedNodes;
  if (target) {
    Value at =
        gep(target, i64, arith::ShRUIOp::create(b, loc, destination, c(6)));
    Value previous = LLVM::LoadOp::create(b, loc, i64, at, 8);
    Value bitMask =
        arith::ShLIOp::create(b, loc, c(1), band(destination, c(63)));
    LLVM::StoreOp::create(b, loc, bor(previous, bitMask), at, 8);
  }
  cf::BranchOp::create(b, loc, watchNext);
  b.setInsertionPointToStart(watchNext);
  cf::BranchOp::create(
      b, loc, watchHead,
      ValueRange{arith::AddIOp::create(b, loc, watcher, c(1))});
}
} // namespace talos::detail
