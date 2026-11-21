//===- SimulationRankedGroupMaterialization.cpp - Shared ranked sweeps
//-----===//

#include "SimulationAOTPlanning.h"
#include "SimulationEvalReadySet.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"

#include "talos/Dialect/Simulation/SimulationMetadata.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/bit.h"
#include <optional>

using namespace mlir;

namespace talos::detail {

// Each Active group checks its pending members at entry. Use
// producer/consumer edges to keep connected ranks together for SSA forwarding.
// Missing or conservative order edges only affect profitability: publications
// to another region still set its real ready bits (1800-2023 4.3--4.7).
static SmallVector<unsigned>
connectedRankEnds(ArrayRef<const NativeRankedEvalNode *> members) {
  DenseMap<uint32_t, unsigned> position;
  SmallVector<unsigned> through;
  for (auto [i, member] : llvm::enumerate(members)) {
    position.try_emplace(member->owner, i);
    through.push_back(i);
  }
  for (auto [i, member] : llvm::enumerate(members))
    for (uint32_t successor : member->successors)
      if (auto found = position.find(successor); found != position.end()) {
        unsigned from = std::min<unsigned>(i, found->second);
        through[from] = std::max<unsigned>(
            through[from], std::max<unsigned>(i, found->second));
      }
  SmallVector<unsigned> ends;
  for (unsigned begin = 0; begin < members.size();) {
    unsigned last = through[begin];
    for (unsigned i = begin + 1; i <= last; ++i)
      last = std::max(last, through[i]);
    ends.push_back(last + 1);
    begin = last + 1;
  }
  return ends;
}

// In a canonical two-state body there is no X/Z proof to amortize across
// sibling producers. Start a new chain when no earlier member in this one
// can wake the next rank. In particular, a common downstream consumer does
// not make its independent inputs run together.
static SmallVector<unsigned>
forwardRankEnds(ArrayRef<const NativeRankedEvalNode *> members) {
  SmallVector<unsigned> ends;
  DenseMap<uint32_t, unsigned> predecessors;
  unsigned begin = 0;
  for (auto [i, member] : llvm::enumerate(members)) {
    if (i && predecessors.lookup(member->owner) <= begin) {
      ends.push_back(i);
      begin = i;
    }
    for (uint32_t successor : member->successors)
      predecessors[successor] = i + 1;
  }
  if (!members.empty())
    ends.push_back(members.size());
  return ends;
}

FailureOr<NativeRankedGroupPlan>
planNativeRankedGroups(ModuleOp module, const NativeEvalCoordinatorPlan &plan,
                       ArrayRef<SmallVector<NativePromotionRange>> ranges,
                       uint64_t stateBits) {
  NativeRankedGroupPlan result;
  if (plan.clockKernels.empty() || plan.rankedNodes.empty() || plan.writableVPI)
    return result;
  llvm::StringMap<sim::SimFuncOp> functions;
  ::talos::detail::walkNativeFunctions<sim::SimFuncOp>(
      module, [&](sim::SimFuncOp function) {
        functions.try_emplace(function.getSymName(), function);
      });
  // Only closed, raw-capture computation may bypass its fragment wrapper.
  // Graph effects establish activation safety; the executable body must also
  // have no runtime/status boundary. Unproved bodies keep their executor.
  auto bodyCost = [&](StringRef name) -> uint64_t {
    auto function = functions.lookup(name);
    if (!function ||
        !::talos::schedule::has<::talos::schedule::Field::EvalRawCaptures>(
            function) ||
        !function.getFunctionType().getResults().empty())
      return 0;
    bool safe = true;
    uint64_t cost = 0;
    function.walk([&](Operation *op) {
      // A wake names its ready set; it stands for the set's address and the
      // update, as its LLVM form computes the address at the wake.
      cost += isa<schedule::NativeReadyUpdateOp>(op) ? 2 : 1;
      safe &=
          !isa_and_nonnull<runtime::TalosRuntimeDialect>(op->getDialect()) &&
          !isa<sim::SimCallOp, sim::SimStatusCheckOp, LLVM::CallOp,
               func::CallOp>(op);
    });
    return safe ? cost : 0;
  };
  uint64_t budget = schedule::getMaxInlineOperations(module);
  SmallVector<NativeRankedEvalNode> members;
  uint64_t cost = 0;
  bool invalidRange = false;
  auto appendChunk = [&](ArrayRef<NativeRankedEvalNode> nodes) {
    NativeRankedGroupChunk chunk;
    llvm::append_range(chunk.members, nodes);
    // Profitability only: share a certificate for a substantial candidate
    // with a bounded scan table. These limits do not establish knownness.
    bool eligible = chunk.members.size() >= 8 &&
                    llvm::all_of(chunk.members, [&](const auto &node) {
                      return !node.clocked && !node.twoStateBody.empty() &&
                             !plan.twoStateExecutors[node.owner].empty() &&
                             node.owner < ranges.size() &&
                             !ranges[node.owner].empty();
                    });
    if (eligible) {
      SmallVector<std::pair<uint64_t, uint64_t>> intervals, merged;
      SmallVector<int32_t> identities;
      for (const auto &node : chunk.members) {
        identities.push_back(node.owner);
        if (node.owner >= ranges.size()) {
          invalidRange = true;
          continue;
        }
        for (const auto &range : ranges[node.owner]) {
          if (!range.bitWidth || range.bitOffset > stateBits ||
              range.bitWidth > stateBits - range.bitOffset) {
            invalidRange = true;
            continue;
          }
          intervals.emplace_back(range.bitOffset,
                                 range.bitOffset + range.bitWidth);
        }
      }
      llvm::sort(intervals);
      for (auto [begin, end] : intervals) {
        if (!merged.empty() && begin <= merged.back().second)
          merged.back().second = std::max(merged.back().second, end);
        else
          merged.emplace_back(begin, end);
      }
      if (!merged.empty() && merged.size() <= 64) {
        // IEEE 1800-2023 6.3.1: only these exact bits must exclude X/Z.
        // Reuse every member's complete input/old-destination certificate,
        // merge overlaps without filling holes, and keep runnable identities
        // unchanged. A later dataflow rejection still uses the member proofs.
        SmallVector<int64_t> encoded;
        for (auto [begin, end] : merged) {
          encoded.push_back(begin);
          encoded.push_back(end - begin);
        }
        Builder builder(module.getContext());
        chunk.proof = schedule::GroupProofDependencyAttr::get(
            module.getContext(),
            builder.getI64IntegerAttr(result.domains.size()),
            builder.getDenseI32ArrayAttr(identities),
            builder.getDenseI64ArrayAttr(encoded));
        result.domains.push_back(chunk.proof);
      }
    }
    result.chunks.push_back(std::move(chunk));
  };
  auto emit = [&]() {
    if (members.empty())
      return;
    // A value-domain certificate covers every member it may execute. A
    // permanently unknown operand in one independent chain otherwise forces
    // unrelated, ready chains through member-by-member selection. Split at
    // the existing rank boundaries and keep a single dispatch entry for the
    // original group. The dependency graph chooses cuts only: the wrapper
    // always rereads actual ingress before selecting a child (4.3, 6.3.1).
    SmallVector<unsigned> ends;
    if (!native::has<native::TwoState>(module) &&
        llvm::all_of(members, [&](const auto &node) {
          return !node.clocked && !node.twoStateBody.empty() &&
                 !plan.twoStateExecutors[node.owner].empty();
        })) {
      auto pointers = llvm::map_to_vector(
          members, [](const NativeRankedEvalNode &node) { return &node; });
      unsigned begin = 0;
      bool priorSingleton = false;
      for (unsigned end : connectedRankEnds(pointers)) {
        bool singleton = end == begin + 1;
        // Independent singleton members already have their own readiness
        // predicates. Put adjacent singletons behind one proof and call.
        if (singleton && priorSingleton)
          ends.back() = end;
        else
          ends.push_back(end);
        begin = end;
        priorSingleton = singleton;
      }
    }
    if (ends.size() < 2) {
      appendChunk(members);
    } else {
      unsigned begin = 0;
      for (unsigned end : ends) {
        appendChunk(ArrayRef(members).slice(begin, end - begin));
        begin = end;
      }
      result.chunks.back().proofRegionCount = ends.size();
    }
    cost = 0;
    members.clear();
  };
  auto finishSegment = [&]() {
    if (!result.chunks.empty())
      result.chunks.back().endsSegment = true;
  };
  // Singleton dependency islands have no edges between certified bodies, but
  // often share an NBA activation. Give independent singletons in one ready
  // word a bounded predicated sweep instead of a dispatcher trip per owner.
  // Keep connected islands in their proven topological order. Readiness is
  // still checked at each member, so this never invents an activation.
  DenseMap<uint32_t, unsigned> islandSizes;
  DenseSet<uint32_t> mixedIslands;
  uint32_t nextIsland = 0;
  for (const auto &node : plan.rankedNodes) {
    ++islandSizes[node.island];
    if (node.cyclic || (node.boundary && node.owner != UINT32_MAX))
      mixedIslands.insert(node.island);
    nextIsland = std::max(nextIsland, node.island + 1);
  }
  SmallVector<NativeRankedEvalNode> ordered(plan.rankedNodes);
  for (auto &node : ordered)
    if (!node.boundary && !node.clocked && islandSizes.lookup(node.island) == 1)
      node.island = nextIsland + node.owner / 64;
  llvm::stable_sort(ordered, [](const auto &a, const auto &b) {
    return a.island < b.island;
  });
  std::optional<uint32_t> currentIsland;
  struct ActivityKey {
    uint32_t eventDomain;
    uint32_t cyclicComponent;
    bool repeatable;
    bool twoState;

    bool operator!=(const ActivityKey &other) const {
      return eventDomain != other.eventDomain ||
             cyclicComponent != other.cyclicComponent ||
             repeatable != other.repeatable || twoState != other.twoState;
    }
  };
  std::optional<ActivityKey> currentActivity;
  for (const auto &node : ordered) {
    if (currentIsland && node.island != *currentIsland) {
      emit();
      finishSegment();
    }
    currentIsland = node.island;
    if (node.boundary) {
      emit();
      finishSegment();
      currentActivity.reset();
      continue;
    }
    // Activity partitions are scheduling predicates, independent of the
    // value-domain proof. In particular, an X-bearing component must not
    // disable an unrelated component's two-state computation. A repeatable
    // member takes a place in one DAG: the ordering edges that a cycle sends
    // backward are cut, and their publications survive for another sweep
    // (IEEE 1800-2023 4.3--4.7). Only its certificate permits coarsening
    // external activity; ordinary members retain their full event domains and
    // the feedback of their component.
    bool selective = mixedIslands.contains(node.island);
    ActivityKey activity{
        selective && !node.repeatable ? node.activityDomain : 0,
        !node.repeatable && node.cyclic ? node.component : UINT32_MAX,
        selective && node.repeatable,
        selective && !node.twoStateBody.empty() &&
            !plan.twoStateExecutors[node.owner].empty()};
    if (!node.clocked && currentActivity && *currentActivity != activity) {
      emit();
      finishSegment();
    }
    currentActivity = activity;
    uint64_t four = bodyCost(node.body);
    uint64_t two = node.twoStateBody.empty() ? 0 : bodyCost(node.twoStateBody);
    if (!four || (!node.twoStateBody.empty() && !two)) {
      emit();
      finishSegment();
      continue;
    }
    // Charge both domain bodies and pending/proof control to this helper,
    // rather than spending one model-wide budget on fragment wrappers.
    uint64_t weight = four + two + 64;
    if (weight > budget - cost)
      emit();
    members.push_back(node);
    cost += weight;
    // A large certified body is a direct call in its own bounded helper.
    // The inliner still enforces its budget; code size does not introduce a
    // scheduling boundary or break the surrounding predicated segment.
    if (cost >= budget)
      emit();
  }
  emit();
  finishSegment();
  if (invalidRange)
    return module.emitError("ranked group proof exceeds native state"),
           failure();
  if (!result.domains.empty() && native::has<native::DebugTiming>(module)) {
    uint64_t rangeCount = 0, bits = 0;
    for (auto domain : result.domains) {
      auto entries = domain.getRanges().asArrayRef();
      rangeCount += entries.size() / 2;
      for (size_t i = 1; i < entries.size(); i += 2)
        bits += entries[i];
    }
    llvm::errs() << "talos group proof domains: domains="
                 << result.domains.size() << " ranges=" << rangeCount
                 << " bits=" << bits << '\n';
  }
  return result;
}

FailureOr<SmallVector<std::string>>
materializeNativeRankedGroups(ModuleOp module,
                              const NativeEvalCoordinatorPlan &plan,
                              const NativeRankedGroupPlan &groups) {
  SmallVector<std::string> executors(plan.fragments.size());
  if (plan.clockKernels.empty() || plan.rankedNodes.empty() || plan.writableVPI)
    return executors;
  const SymbolTable promotionSymbols(module);
  llvm::StringMap<sim::SimFuncOp> functions;
  ::talos::detail::walkNativeFunctions<sim::SimFuncOp>(
      module, [&](sim::SimFuncOp function) {
        functions.try_emplace(function.getSymName(), function);
      });
  OpBuilder builder(module.getContext());
  Location loc = module.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(module.getContext());
  Type i64 = builder.getI64Type();
  const EvalReadySetLayout readyLayout(
      std::max<size_t>(64, plan.fragments.size()));
  SmallVector<const NativeRankedEvalNode *> members;
  unsigned groupID = 0;
  unsigned clockedMembers = 0;
  unsigned unconditionalMembers = 0;
  struct Chunk {
    std::string name;
    SmallVector<uint32_t> owners;
    SmallVector<std::pair<unsigned, uint64_t>> words;
  };
  auto indexOwners = [](Chunk &chunk) {
    llvm::sort(chunk.owners);
    for (uint32_t owner : chunk.owners) {
      unsigned word = owner / 64;
      if (chunk.words.empty() || chunk.words.back().first != word)
        chunk.words.push_back({word, 0});
      chunk.words.back().second |= uint64_t{1} << (owner % 64);
    }
  };
  SmallVector<Chunk> chunks;
  unsigned segmentCount = 0;
  auto finishSegment = [&](unsigned proofRegions = 0) {
    // A multi-word ready set is swept word by word by the coordinator, which
    // already calls each chunk at its first pending member in rank order. A
    // wrapper over several words would run their chunks early and leave
    // their dirty words to be revisited.
    // Only children of a single existing dispatch entry can be collected
    // across ready words. Previous code-size chunks keep their executors.
    ArrayRef<Chunk> siblings = chunks;
    if (proofRegions)
      siblings = siblings.take_back(proofRegions);
    if (siblings.size() < 2 || (readyLayout.hasSummaries() && !proofRegions)) {
      chunks.clear();
      return;
    }
    // A code-size split is a direct helper call, not another scheduling
    // boundary. This is the same finite, predicated sweep that an unsplit
    // helper would execute. Each child consumes only its own pending work;
    // publications to an earlier child survive until the shared loop returns.
    builder.setInsertionPointToEnd(module.getBody());
    std::string name = siblings.front().name + ".segment";
    auto segment = LLVM::LLVMFuncOp::create(
        builder, loc, name,
        LLVM::LLVMFunctionType::get(
            LLVM::LLVMVoidType::get(module.getContext()), {pointer}, false));
    ::talos::schedule::set<schedule::metadata::evalCallClosureRoot>(
        segment, builder.getUnitAttr());
    SmallVector<Attribute> helpers;
    for (const Chunk &chunk : siblings)
      helpers.push_back(
          FlatSymbolRefAttr::get(module.getContext(), chunk.name));
    ::talos::schedule::set<::talos::schedule::Field::EvalSegmentHelpers>(
        segment, builder.getArrayAttr(helpers));
    Block *entry = segment.addEntryBlock(builder);
    builder.setInsertionPointToStart(entry);
    Value ready =
        LLVM::AddressOfOp::create(builder, loc, pointer, evalModelIngressName);
    auto emitChunk = [&](const Chunk &chunk) {
      Value dirty;
      for (auto [word, mask] : chunk.words) {
        Value bits = loadOwnerWord(builder, loc, ready, word);
        if (mask != UINT64_MAX)
          bits = arith::AndIOp::create(builder, loc, bits,
                                       llvmConstant(builder, loc, i64, mask));
        dirty = dirty ? arith::OrIOp::create(builder, loc, dirty, bits) : bits;
      }
      Value pending =
          arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne, dirty,
                                llvmConstant(builder, loc, i64, 0));
      Block *execute = new Block, *next = new Block;
      segment.getBody().push_back(execute);
      segment.getBody().push_back(next);
      cf::CondBranchOp::create(builder, loc, pending, execute, ValueRange{},
                               next, ValueRange{});
      builder.setInsertionPointToStart(execute);
      LLVM::CallOp::create(builder, loc, TypeRange{}, chunk.name,
                           entry->getArguments());
      cf::BranchOp::create(builder, loc, next);
      builder.setInsertionPointToStart(next);
      for (uint32_t owner : chunk.owners)
        executors[owner] = name;
    };
    // Owners follow rank order, so a sweep skips the chunks of an idle ready
    // word with one test, and never fetches their branches. A chunk's own test
    // still reads the word after earlier chunks have published into it.
    for (size_t index = 0; index < siblings.size();) {
      size_t end = index + 1;
      auto word = siblings[index].words.front().first;
      auto inWord = [&](const Chunk &chunk) {
        return chunk.words.size() == 1 && chunk.words.front().first == word;
      };
      if (inWord(siblings[index]))
        while (end < siblings.size() && inWord(siblings[end]))
          ++end;
      Block *after = nullptr;
      if (end - index > 1) {
        // Not nested: argument evaluation order would make the emitted IR
        // differ between ABIs (the MSVC ABI evaluates right to left).
        Value bits = loadOwnerWord(builder, loc, ready, word);
        Value active =
            arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne, bits,
                                  llvmConstant(builder, loc, i64, 0));
        Block *body = new Block;
        after = new Block;
        segment.getBody().push_back(body);
        cf::CondBranchOp::create(builder, loc, active, body, ValueRange{},
                                 after, ValueRange{});
        builder.setInsertionPointToStart(body);
      }
      for (; index < end; ++index)
        emitChunk(siblings[index]);
      if (after) {
        cf::BranchOp::create(builder, loc, after);
        segment.getBody().push_back(after);
        builder.setInsertionPointToStart(after);
      }
    }
    LLVM::ReturnOp::create(builder, loc, ValueRange{});
    ++segmentCount;
    if (proofRegions && !readyLayout.hasSummaries()) {
      // The outer small-model sweep still owns the original rank span. Keep
      // its other code-size chunks in order and substitute this one child.
      Chunk parent{name, {}, {}};
      for (const Chunk &child : siblings)
        llvm::append_range(parent.owners, child.owners);
      indexOwners(parent);
      chunks.resize(chunks.size() - proofRegions);
      chunks.push_back(std::move(parent));
    } else {
      chunks.clear();
    }
  };
  auto emit = [&](schedule::GroupProofDependencyAttr proof) {
    if (members.empty()) {
      members.clear();
      return;
    }
    builder.setInsertionPointToEnd(module.getBody());
    std::string name = "__talos_eval_ranked_group_" + std::to_string(groupID++);
    auto group = LLVM::LLVMFuncOp::create(
        builder, loc, name,
        LLVM::LLVMFunctionType::get(
            LLVM::LLVMVoidType::get(module.getContext()), {pointer}, false));
    SmallVector<int32_t> identities;
    for (auto *member : members) {
      identities.push_back(member->owner);
      executors[member->owner] = name;
      clockedMembers += member->clocked;
    }
    Chunk chunk{name, {}, {}};
    for (auto *member : members)
      chunk.owners.push_back(member->owner);
    indexOwners(chunk);
    chunks.push_back(std::move(chunk));
    ::talos::schedule::set<::talos::schedule::Field::EvalRankedMembers>(
        group, builder.getDenseI32ArrayAttr(identities));
    if (proof)
      schedule::set<schedule::Field::EvalGroupProofDomain>(group, proof);
    ::talos::schedule::set<::talos::schedule::Field::EvalReadyWordCount>(
        group, builder.getI64IntegerAttr(readyLayout.counts[0]));
    ::talos::schedule::set<::talos::schedule::Field::EvalGroupIngress>(
        group,
        FlatSymbolRefAttr::get(module.getContext(), evalModelIngressName));
    ::talos::schedule::set<schedule::metadata::evalCallClosureRoot>(
        group, builder.getUnitAttr());
    Block *entry = group.addEntryBlock(builder);
    builder.setInsertionPointToStart(entry);
    Value promotion = LLVM::AddressOfOp::create(
        builder, loc, pointer, "__talos_eval_promotion_pending_mask_v1");
    auto rawCall = [&](StringRef body, uint32_t owner) {
      SmallVector<Value> arguments;
      for (Type type : functions.lookup(body).getFunctionType().getInputs())
        arguments.push_back(
            isa<sim::ContextType>(type)
                ? entry->getArgument(0)
                : LLVM::PoisonOp::create(
                      builder, loc,
                      convertProcessType(type, module.getContext()))
                      .getResult());
      auto call =
          func::CallOp::create(builder, loc, body, TypeRange{}, arguments);
      ::talos::schedule::set<::talos::schedule::Field::EvalDirectCall>(
          call, builder.getUnitAttr());
      ::talos::schedule::set<::talos::schedule::Field::EvalGroupMember>(
          call, builder.getI32IntegerAttr(owner));
      // The group has selected this value-domain branch explicitly. Route
      // lowering must not introduce a mutable function pointer here.
      ::talos::schedule::set<::talos::schedule::Field::EvalGroupDomainSelected>(
          call, builder.getUnitAttr());
    };
    auto markCanonicalNBA = [&](uint32_t owner) {
      LLVM::StoreOp::create(
          builder, loc, llvmConstant(builder, loc, builder.getI8Type(), 1),
          LLVM::AddressOfOp::create(builder, loc, pointer,
                                    "__talos_eval_step_four_state_fallback_v1"),
          1);
      for (unsigned word = 0; word < plan.nbaTaintWordCount; ++word) {
        uint64_t mask = plan.nbaTaintMasks[owner][word];
        if (!mask)
          continue;
        Value base = LLVM::AddressOfOp::create(
            builder, loc, pointer, "__talos_eval_step_four_state_nba_roots_v1");
        updateOwnerWord(builder, loc, base, word,
                        llvmConstant(builder, loc, i64, mask));
      }
    };
    for (const auto *node : members) {
      uint32_t owner = node->owner;
      Value bit = llvmConstant(builder, loc, i64, uint64_t{1} << (owner % 64));
      Value ingress = schedule::NativeReadyReadOp::create(
          builder, loc, schedule::ReadySet::Ingress, readyLayout.capacity,
          owner / 64);
      ::talos::schedule::set<::talos::schedule::Field::EvalActivationEntry>(
          ingress.getDefiningOp(), builder.getI32IntegerAttr(owner));
      Value dirty = arith::AndIOp::create(builder, loc, ingress, bit);
      Value pending =
          arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne, dirty,
                                llvmConstant(builder, loc, i64, 0));
      Block *execute = new Block, *next = new Block;
      group.getBody().push_back(execute);
      group.getBody().push_back(next);
      cf::CondBranchOp::create(builder, loc, pending, execute, ValueRange{},
                               next, ValueRange{});
      builder.setInsertionPointToStart(execute);
      // Consume before execution. Later members may republish this owner;
      // that backward work must survive the sweep (LRM 4.4--4.7). Self-reading
      // sources are excluded by the activation certificate.
      updateEvalReadyWord(builder, loc, schedule::ReadySet::Ingress,
                          readyLayout, owner / 64, bit, /*clear=*/true);
      bool twoState =
          !node->twoStateBody.empty() && !plan.twoStateExecutors[owner].empty();
      Block *four = execute;
      if (twoState) {
        four = new Block;
        Block *check = new Block, *two = new Block;
        group.getBody().push_back(four);
        group.getBody().push_back(check);
        group.getBody().push_back(two);
        Value unknown = arith::AndIOp::create(
            builder, loc, loadOwnerWord(builder, loc, promotion, owner / 64),
            bit);
        Value needsProof =
            arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne,
                                  unknown, llvmConstant(builder, loc, i64, 0));
        cf::CondBranchOp::create(builder, loc, needsProof, check, ValueRange{},
                                 two, ValueRange{});
        builder.setInsertionPointToStart(check);
        Value known = emitOwnerKernelReady(
            builder, loc, owner, node->clockedKernel, promotionSymbols);
        cf::CondBranchOp::create(builder, loc, known, two, ValueRange{}, four,
                                 ValueRange{});
        builder.setInsertionPointToStart(two);
        rawCall(node->twoStateBody, owner);
        cf::BranchOp::create(builder, loc, next);
        builder.setInsertionPointToStart(four);
      }
      markCanonicalNBA(owner);
      rawCall(node->body, owner);
      cf::BranchOp::create(builder, loc, next);
      builder.setInsertionPointToStart(next);
    }
    LLVM::ReturnOp::create(builder, loc, ValueRange{});
    // This is only a candidate. After lowering, control-flow analysis must
    // prove that its computation is finite. Until then the ordinary ranked
    // helper owns entry. A candidate forwards state and readiness between
    // members, so a lone member, even a repeatable one, gets none.
    bool canonicalTwoState = native::has<native::TwoState>(module);
    SmallVector<unsigned> ends = canonicalTwoState ? forwardRankEnds(members)
                                                   : connectedRankEnds(members);
    // In a model already compiled in two-state, the original group already
    // predicates and inlines independent members. Only build a second body
    // when it can forward computation down an actual chain.
    // A pair in one small ingress word already shares a predicated sweep and
    // forwarded state. Making its producer unconditional on a consumer-only
    // wake saves a single bit test and can repeat the entire producer.
    bool canForward = !canonicalTwoState ||
                      (ends.size() < members.size() &&
                       (members.size() > 2 || readyLayout.hasSummaries()));
    if (members.size() > 1 && canForward &&
        llvm::all_of(members, [&](const auto *node) {
          return !node->clocked &&
                 (canonicalTwoState ||
                  (!node->twoStateBody.empty() &&
                   !plan.twoStateExecutors[node->owner].empty()));
        })) {
      builder.setInsertionPointToEnd(module.getBody());
      auto candidate = LLVM::LLVMFuncOp::create(
          builder, loc, name + ".dataflow",
          LLVM::LLVMFunctionType::get(
              LLVM::LLVMVoidType::get(module.getContext()), {pointer}, false));
      ::talos::schedule::set<::talos::schedule::Field::EvalRankedMembers>(
          candidate, builder.getDenseI32ArrayAttr(identities));
      if (proof)
        schedule::set<schedule::Field::EvalGroupProofDomain>(candidate, proof);
      ::talos::schedule::set<::talos::schedule::Field::EvalGroupIngress>(
          candidate,
          ::talos::schedule::get<::talos::schedule::Field::EvalGroupIngress>(
              group));
      ::talos::schedule::set<::talos::schedule::Field::EvalReadyWordCount>(
          candidate,
          ::talos::schedule::get<::talos::schedule::Field::EvalReadyWordCount>(
              group));
      ::talos::schedule::set<::talos::schedule::Field::EvalDataflowCandidate>(
          candidate, FlatSymbolRefAttr::get(module.getContext(), name));
      ::talos::schedule::set<schedule::metadata::evalCallClosureRoot>(
          candidate, builder.getUnitAttr());
      entry = candidate.addEntryBlock(builder);
      builder.setInsertionPointToStart(entry);
      SmallVector<int32_t> unconditional;
      auto emitMember = [&](const NativeRankedEvalNode *node, bool speculate) {
        uint32_t owner = node->owner;
        Value bit =
            llvmConstant(builder, loc, i64, uint64_t{1} << (owner % 64));
        Value ingress = schedule::NativeReadyReadOp::create(
            builder, loc, schedule::ReadySet::Ingress, readyLayout.capacity,
            owner / 64);
        ::talos::schedule::set<::talos::schedule::Field::EvalActivationEntry>(
            ingress.getDefiningOp(), builder.getI32IntegerAttr(owner));
        Value dirty = arith::AndIOp::create(builder, loc, ingress, bit);
        Value active =
            arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne, dirty,
                                  llvmConstant(builder, loc, i64, 0));
        // The source-revision proof covers complete sensitivity, exclusive
        // outputs, and absence of repeated publications. Repeating this pure
        // computation when inactive is observationally inert: it writes the
        // values its outputs already hold, which is no update event (IEEE
        // 1800-2023 4.3, 4.4.1, 4.9.1, 9.2.2.2, 9.4.2). A body with a source
        // call or a runtime boundary never joins a group (bodyCost), so a call
        // the lowering adds only publishes proof metadata or computes a pure
        // value, and repeats just as inertly. An independent group certificate
        // proves knownness, not activation, so it does not change this
        // decision. Such a member runs whenever the group runs,
        // in its proved rank order; publications from earlier members to it
        // are therefore redundant and are removed after inlining (see
        // elideUnconditionalMemberPublications). Its pending bit is still
        // the ingress that selects this group and is consumed here.
        bool captureFree =
            !canonicalTwoState || !plan.nbaTaintWordCount ||
            llvm::none_of(plan.nbaTaintMasks[owner],
                          [](uint64_t mask) { return mask != 0; });
        if (node->repeatable && speculate && captureFree) {
          active = llvmConstant(builder, loc, builder.getI1Type(), 1);
          unconditional.push_back(owner);
          ++unconditionalMembers;
        }
        Block *execute = new Block, *next = new Block;
        candidate.getBody().push_back(execute);
        candidate.getBody().push_back(next);
        cf::CondBranchOp::create(builder, loc, active, execute, ValueRange{},
                                 next, ValueRange{});
        builder.setInsertionPointToStart(execute);
        updateEvalReadyWord(builder, loc, schedule::ReadySet::Ingress,
                            readyLayout, owner / 64, bit, /*clear=*/true);
        if (canonicalTwoState) {
          // The canonical executor is already in the requested two-state
          // domain. Retain its barrier bookkeeping on the selected path.
          markCanonicalNBA(owner);
          rawCall(node->body, owner);
        } else {
          rawCall(node->twoStateBody, owner);
        }
        cf::BranchOp::create(builder, loc, next);
        builder.setInsertionPointToStart(next);
      };
      unsigned begin = 0;
      for (unsigned end : ends) {
        auto part = ArrayRef(members).slice(begin, end - begin);
        Block *after = nullptr;
        if (ends.size() > 1 && part.size() > 1) {
          llvm::SmallMapVector<uint32_t, uint64_t, 4> masks;
          for (const auto *node : part)
            masks[node->owner / 64] |= uint64_t{1} << (node->owner % 64);
          Value dirty;
          for (auto [word, mask] : masks) {
            Value readyWord = schedule::NativeReadyReadOp::create(
                builder, loc, schedule::ReadySet::Ingress, readyLayout.capacity,
                word);
            Value bits = arith::AndIOp::create(
                builder, loc, readyWord, llvmConstant(builder, loc, i64, mask));
            dirty =
                dirty ? arith::OrIOp::create(builder, loc, dirty, bits) : bits;
          }
          Value active =
              arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne,
                                    dirty, llvmConstant(builder, loc, i64, 0));
          Block *execute = new Block;
          after = new Block;
          candidate.getBody().push_back(execute);
          cf::CondBranchOp::create(builder, loc, active, execute, ValueRange{},
                                   after, ValueRange{});
          builder.setInsertionPointToStart(execute);
        }
        for (const auto *node : part)
          emitMember(node, part.size() > 1);
        if (after) {
          cf::BranchOp::create(builder, loc, after);
          candidate.getBody().push_back(after);
          builder.setInsertionPointToStart(after);
        }
        begin = end;
      }
      LLVM::ReturnOp::create(builder, loc, ValueRange{});
      if (!unconditional.empty())
        ::talos::schedule::set<
            ::talos::schedule::Field::EvalUnconditionalMembers>(
            candidate, builder.getDenseI32ArrayAttr(unconditional));
    }
    members.clear();
  };
  for (const auto &chunk : groups.chunks) {
    for (const auto &node : chunk.members)
      members.push_back(&node);
    emit(chunk.proof);
    if (chunk.proofRegionCount)
      finishSegment(chunk.proofRegionCount);
    if (chunk.endsSegment)
      finishSegment();
  }
  if (native::has<native::DebugTiming>(module)) {
    llvm::errs()
        << "talos ranked groups: candidates="
        << llvm::count_if(plan.rankedNodes,
                          [](const auto &node) { return !node.boundary; })
        << " groups=" << groupID << " segments=" << segmentCount << " members="
        << llvm::count_if(executors,
                          [](const auto &name) { return !name.empty(); })
        << " clocked_members=" << clockedMembers << '\n';
    llvm::errs() << "talos repeatable ranked members: "
                 << llvm::count_if(plan.rankedNodes,
                                   [&](const auto &node) {
                                     return node.repeatable &&
                                            !executors[node.owner].empty();
                                   })
                 << " unconditional=" << unconditionalMembers << '\n';
    // Tie runtime entry counts back to the actual native ownership plan.
    // Include owners without direct fragments as well. Their compute-node
    // IDs retain the source graph's global scheduling rank.
    for (auto [index, record] : llvm::enumerate(plan.fragments))
      llvm::errs() << "talos eval owner: bit=" << record.bit
                   << " actor=" << record.actor_slot
                   << " continuation=" << record.continuation
                   << " compute_node=" << record.compute_node << " group="
                   << (executors[index].empty() ? "-" : executors[index])
                   << " executor=" << plan.fourStateExecutors[index]
                   << (record.bit >= plan.firstDeferredBit ? " deferred" : "")
                   << '\n';
    for (const auto &node : plan.rankedNodes) {
      if (node.owner == UINT32_MAX)
        continue;
      llvm::errs() << (node.boundary ? "talos eval boundary: owner="
                                     : "talos eval dependency: owner=")
                   << node.owner << " island=" << node.island
                   << " body=" << node.body << " successors=";
      llvm::interleaveComma(node.successors, llvm::errs());
      llvm::errs() << '\n';
    }
    for (const auto &node : plan.rankedNodes) {
      if (node.owner == UINT32_MAX)
        llvm::errs() << "talos eval runtime boundary: component="
                     << node.component << " body=" << node.body << '\n';
      llvm::errs() << "talos eval component: owner=" << node.owner
                   << " component=" << node.component
                   << " activity=" << node.activityDomain
                   << " cyclic=" << node.cyclic << " successors=";
      llvm::interleaveComma(node.successorComponents, llvm::errs());
      llvm::errs() << " feedback=";
      llvm::interleaveComma(node.feedbackSuccessors, llvm::errs());
      llvm::errs() << '\n';
    }
    llvm::errs() << "talos eval repeatable owners:";
    for (const auto &node : plan.rankedNodes)
      if (node.repeatable)
        llvm::errs() << ' ' << node.owner;
    llvm::errs() << '\n';
  }
  return executors;
}

unsigned elideUnconditionalMemberPublications(LLVM::LLVMFuncOp function) {
  auto members = ::talos::schedule::get<
      ::talos::schedule::Field::EvalUnconditionalMembers>(function);
  auto ingress =
      ::talos::schedule::get<::talos::schedule::Field::EvalGroupIngress>(
          function);
  if (!members || members.empty() || !ingress)
    return 0;
  // Pending bits of unconditional members, per ingress word.
  DenseMap<uint64_t, uint64_t> unconditional;
  for (int32_t owner : members.asArrayRef()) {
    if (owner < 0)
      return 0;
    unconditional[uint64_t(owner) / 64] |= uint64_t{1} << (owner % 64);
  }
  // SCC condensation orders components, not every edge inside a component.
  // A later member can change an earlier member's inputs; that publication
  // must survive for another sweep (IEEE 1800-2023 4.3-4.5, 4.9.1). Only
  // elide work whose destination will still execute after the publication.
  // Use executable entries rather than owner IDs or inferred graph ranks.
  DenseMap<uint64_t, Operation *> entries;
  function.walk([&](Operation *operation) {
    auto owner = schedule::get<schedule::Field::EvalActivationEntry>(operation);
    if (!owner || !isa<schedule::NativeReadyReadOp, LLVM::LoadOp>(operation))
      return;
    auto [found, inserted] = entries.try_emplace(owner.getUInt(), operation);
    if (!inserted)
      found->second = nullptr;
  });
  PostDominanceInfo order(function);
  // The bits a mask can add: a constant, or a select between constants (the
  // inline publication form `select(triggered, bit, 0)`). Anything else may
  // publish to a member that still has its predicate, so it is kept.
  auto constantBits = [](Value mask) -> std::optional<uint64_t> {
    APInt value;
    if (matchPattern(mask, m_ConstantInt(&value)))
      return value.getZExtValue();
    Value yesValue, noValue;
    if (auto select = mask.getDefiningOp<arith::SelectOp>()) {
      yesValue = select.getTrueValue();
      noValue = select.getFalseValue();
    } else if (auto select = mask.getDefiningOp<LLVM::SelectOp>()) {
      yesValue = select.getTrueValue();
      noValue = select.getFalseValue();
    } else {
      return std::nullopt;
    }
    APInt yes, no;
    if (!matchPattern(yesValue, m_ConstantInt(&yes)) ||
        !matchPattern(noValue, m_ConstantInt(&no)))
      return std::nullopt;
    return (yes | no).getZExtValue();
  };
  SmallVector<schedule::NativeReadyUpdateOp> redundant;
  function.walk([&](schedule::NativeReadyUpdateOp update) {
    if (update.getConsume())
      return;
    // A held wake (an NBA-equivalent store's, see evalNBAHeldWakesName) to a
    // member that still runs later in this sweep is redundant as well: the
    // member reads the stored value there.
    if (update.getSet() != ingress.getValue() &&
        update.getReadySet() != schedule::ReadySet::HeldWakes)
      return;
    std::optional<uint64_t> bits = constantBits(update.getMask());
    auto word = unconditional.find(update.getWord());
    if (!bits || !*bits || word == unconditional.end() ||
        (*bits & ~word->second) != 0)
      return;
    uint64_t pending = *bits;
    while (pending) {
      unsigned bit = llvm::countr_zero(pending);
      pending &= pending - 1;
      Operation *entry = entries.lookup(update.getWord() * 64 + bit);
      if (!entry || !order.properlyPostDominates(entry, update))
        return;
    }
    redundant.push_back(update);
  });
  // The publication's change/edge computation becomes dead with it; ordinary
  // dead-code elimination removes it before the dataflow proof. The member's
  // own store, and every publication to a predicated member, another group,
  // a runtime observer or the four-state fallback, remain (IEEE 1800-2023
  // 4.6, 9.4.2).
  for (auto update : redundant)
    update.erase();
  return redundant.size();
}

} // namespace talos::detail
