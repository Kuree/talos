//===- ArmEventCombinational.cpp - Body-first `always @(list)` blocks ----===//
//
// A Verilog-2001 combinational block `always @(a or b) body` waits for its
// first event before running (IEEE 1800-2023 9.4.2), whereas always_comb runs
// once at time zero (9.2.2.2.2). Combinational statement planning admits only
// body-first activations, so such a block otherwise stays a separate process.
//
// This pass gives the block a design bit `armed`, initially 0, and a one-shot
// initial process that waits for the block's own event control once and then
// sets `armed` (9.4.2). The block itself becomes body-first: it runs its body
// only while `armed` is set, then waits on its list and on `armed`.
//
// The rewrite preserves the block's behavior up to the order in which the
// processes woken by one event run, which 4.7 leaves open. Before the first
// event of the list the body never runs, as before. At that event the block
// wakes, and so does the arming process; whichever runs first, the body runs
// once in that time slot, either directly or when `armed` changes. Afterwards
// `armed` stays 1 and the block runs its body on every event of its list, as
// before. Activations that find `armed` clear and the arming write itself are
// not observable: the block reads `armed` only to skip its body, and nothing
// else reads `armed`. A racing reader of the block's outputs woken by the same
// event may see the old values where -O0 shows the new ones; both are legal.
// The arming copy draws its process seed from a private initialization stream
// (18.14.1). The pass leaves designs that can observe the extra process or
// variable (process identity, random-state capture, waveform dumps) alone.
//
// The pass only reshapes blocks that, like always_comb, are the sole writer of
// what they write (9.2.2.2), so a skipped write keeps the block's own old
// value. Whether a body may join a fused combinational activation (complete
// sensitivity, idempotence, ...) is left to the statement planner, which sees
// the result as a body-first activation (schedule.armed_combinational).
// Requires VPI off, since `armed` and the arming process are not source
// objects.
//
//===----------------------------------------------------------------------===//

#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_TALOSSIMARMEVENTCOMBINATIONALPASS
#include "talos/Dialect/Schedule/Transforms/Passes.h.inc"

namespace {
class TalosSimArmEventCombinationalPass final
    : public impl::TalosSimArmEventCombinationalPassBase<
          TalosSimArmEventCombinationalPass> {
public:
  using Base::Base;
  void runOnOperation() override;
};

/// The watched values of a change-only event-control wait and the operands it
/// passes to its continuation.
std::pair<ValueRange, ValueRange> splitWait(Operation *wait) {
  if (auto any = dyn_cast<sim::SimSuspendAnyOp>(wait)) {
    ValueRange values = any.getValues();
    size_t watched = any.getEdges().size();
    return {values.take_front(watched), values.drop_front(watched)};
  }
  auto change = cast<sim::SimSuspendChangeOp>(wait);
  return {change->getOperands().take_front(1),
          change.getContinuationOperands()};
}

/// Replaces `wait` by a change-only `suspend.any` on its watched values and
/// `extra` that resumes into `dest` without operands, keeping its site,
/// region and discardable attributes.
Operation *rebuildWait(Operation *wait, ValueRange extra, Block *dest) {
  SmallVector<Value> values(splitWait(wait).first);
  llvm::append_range(values, extra);
  OpBuilder builder(wait);
  auto site = wait->getAttrOfType<schedule::ContinuationSiteAttr>("site");
  auto region = wait->getAttrOfType<sim::EventRegionAttr>("resume_region");
  Operation *rebuilt = sim::SimSuspendAnyOp::create(
      builder, wait->getLoc(), values,
      builder.getDenseI32ArrayAttr(SmallVector<int32_t>(values.size(), 0)),
      site, region, dest);
  for (NamedAttribute attribute : wait->getDiscardableAttrs())
    rebuilt->setDiscardableAttr(attribute.getName(), attribute.getValue());
  wait->erase();
  return rebuilt;
}

/// Moves the pure prefix of `wait`'s block into the entry block, so that every
/// value the wait uses is defined before the first wait (and before the guard
/// the rewrite inserts).
void hoistWaitPrefix(Operation *wait) {
  Block *block = wait->getBlock();
  Block &entry = block->getParent()->front();
  while (&block->front() != wait)
    block->front().moveBefore(entry.getTerminator());
}

/// The operation after which the arming copy of the process spawned by `spawn`
/// starts: the end of the spawn's seed bracket (18.14.1) if it has one, so the
/// copy draws from its own stream, and every spawn operand dominates it.
Operation *getArmingInsertionPoint(sim::SimSpawnOp spawn) {
  for (Operation *next = spawn->getNextNode(); next; next = next->getNextNode()) {
    if (isa<sim::SimRandomInitializationLeaveOp>(next))
      return next;
    if (!isMemoryEffectFree(next))
      break;
  }
  return spawn;
}

/// The single event-control wait of `function` in the shape
///   ^entry: <effect-free ops> cf.br ^wait
///   ^wait:  <pure projections> suspend.any/change <list> to ^start(<values>)
///   ^start...: atomic body whose every path branches back to ^wait
/// with every edge a change, or null.
Operation *getLeadingEventWait(sim::SimFuncOp function) {
  Region &body = function.getBody();
  Block &entry = body.front();
  auto toWait = dyn_cast<cf::BranchOp>(entry.getTerminator());
  if (!toWait || toWait.getNumOperands() != 0 ||
      llvm::any_of(entry.without_terminator(), [](Operation &op) {
        return op.getNumRegions() != 0 || !isMemoryEffectFree(&op);
      }))
    return nullptr;
  Block *wait = toWait.getDest();
  if (wait == &entry || wait->getNumArguments() != 0)
    return nullptr;
  // The wait block may recompute the watched projections; they are pure
  // functions of the entry's values (see hoistWaitPrefix).
  for (Operation &op : wait->without_terminator())
    if (op.getNumRegions() != 0 || !isMemoryEffectFree(&op) ||
        llvm::any_of(op.getOperands(), [&](Value operand) {
          Block *owner = operand.getParentBlock();
          return owner != &entry && owner != wait;
        }))
      return nullptr;
  Operation *suspend = wait->getTerminator();
  if (auto any = dyn_cast<sim::SimSuspendAnyOp>(suspend)) {
    if (any.getResumeRegion() ||
        any.getValues().size() < any.getEdges().size() ||
        llvm::any_of(any.getEdges(), [](int32_t edge) { return edge != 0; }))
      return nullptr;
  } else if (auto change = dyn_cast<sim::SimSuspendChangeOp>(suspend)) {
    if (change.getResumeRegion())
      return nullptr;
  } else {
    return nullptr;
  }
  Block *start = suspend->getSuccessor(0);
  if (start == &entry || start == wait)
    return nullptr;
  // Continuation operands come from the entry or the hoisted wait prefix,
  // which dominate the guard that will forward them.
  if (llvm::any_of(splitWait(suspend).second, [&](Value value) {
        Block *owner = value.getParentBlock();
        return owner != &entry && owner != wait;
      }))
    return nullptr;
  // Every other block belongs to the body: no further suspension, return or
  // nested region, and no edge back into the entry.
  for (Block &block : body) {
    if (&block == &entry || &block == wait)
      continue;
    for (Operation &op : block) {
      if (op.getNumRegions() != 0 ||
          isa<sim::SimReturnOp, sim::SimSpawnOp, sim::SimCallOp>(op) ||
          (op.hasTrait<OpTrait::IsTerminator>() &&
           !isa<cf::BranchOp, cf::CondBranchOp, cf::SwitchOp>(op)))
        return nullptr;
    }
    if (llvm::is_contained(block.getSuccessors(), &entry))
      return nullptr;
  }
  return suspend;
}

void TalosSimArmEventCombinationalPass::runOnOperation() {
  sim::SimDesignOp design = getOperation();
  ModuleOp module = design->getParentOfType<ModuleOp>();
  bool report = module && native::has<native::DebugTiming>(module);
  schedule::ComputeGraphAttr graph = design.getComputeGraphAttr();
  if (!graph || graph.getVpi() != schedule::ComputeVPIMode::Off)
    return;

  // The arming copy is one more process and `armed` one more variable. Keep
  // the design as is where either is observable: process handles by identity
  // (9.7), seeds by random-state capture (18.13), variables by waveform dumps
  // (21.7).
  bool observable = false;
  design.walk([&](Operation *operation) {
    observable |=
        isa<sim::SimProcessCurrentOp, sim::SimProcessControlOp,
            sim::SimProcessRandomStateOp, sim::SimProcessSetRandomStateOp,
            sim::SimDumpOpenOp, sim::SimDumpOpenStringOp, sim::SimDumpVarsOp,
            sim::SimDumpAllOp, sim::SimDumpPortsOp>(operation);
  });
  if (observable)
    return;

  sim::SimFuncOp root;
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>())
    if (function.getEntryKind() == sim::EntryKind::RootInitializer)
      root = function;
  if (!root)
    return;
  DenseMap<StringAttr, SmallVector<sim::SimSpawnOp>> spawns;
  design.walk([&](sim::SimSpawnOp spawn) {
    spawns[spawn.getCalleeAttr().getAttr()].push_back(spawn);
  });
  DenseMap<StringAttr, unsigned> symbolUses;
  if (auto uses = SymbolTable::getSymbolUses(&design.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      ++symbolUses[use.getSymbolRef().getRootReference()];

  int64_t nextStorage = 0;
  for (auto storage : design.getBody().front().getOps<sim::SimStorageDeclOp>())
    nextStorage = std::max<int64_t>(nextStorage, storage.getId() + 1);
  DenseSet<uint64_t> codeUnits;
  DenseMap<uint64_t, sim::SimCodeUnitDeclOp> codeUnitDecls;
  for (auto declaration :
       design.getBody().front().getOps<sim::SimCodeUnitDeclOp>()) {
    codeUnits.insert(declaration.getId());
    codeUnitDecls[declaration.getId()] = declaration;
  }
  design.walk([&](sim::SimFuncOp function) {
    if (IntegerAttr unit = function.getCodeUnitIdAttr())
      codeUnits.insert(unit.getUInt());
  });

  // Design-state writers by root, outside the initializers that run before
  // time zero. The rewritten block declares the exclusivity that always_comb
  // guarantees (9.2.2.2): nothing else writes what it writes, so a skipped
  // write keeps the block's own old value.
  struct Writer {
    Operation *function;
    uint64_t low, width;
    bool dynamic;
  };
  DenseMap<std::pair<unsigned, uint64_t>, SmallVector<Writer>> writers;
  auto isWrite = [](schedule::ComputeEffectAttr effect) {
    return effect.getEffect() == schedule::ComputeEffectKind::Write ||
           effect.getEffect() == schedule::ComputeEffectKind::NBA ||
           effect.getEffect() == schedule::ComputeEffectKind::Drive;
  };
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        function.getEntryKind() == sim::EntryKind::RootInitializer ||
        function.getEntryKind() == sim::EntryKind::Function)
      continue;
    ArrayAttr summary = function.getEffectSummaryAttr();
    if (!summary)
      return;
    for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
      if (!isWrite(effect) ||
          effect.getTarget() == schedule::ComputeTargetKind::Local)
        continue;
      if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor)
        return;
      writers[{static_cast<unsigned>(effect.getResource()),
               effect.getDescriptor()}]
          .push_back({function, effect.getLow(), effect.getWidth(),
                      effect.getDynamic()});
    }
  }
  auto writesExclusively = [&](sim::SimFuncOp function) {
    ArrayAttr summary = function.getEffectSummaryAttr();
    bool any = false;
    for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
      if (!isWrite(effect) ||
          effect.getTarget() == schedule::ComputeTargetKind::Local)
        continue;
      if (effect.getEffect() != schedule::ComputeEffectKind::Write ||
          effect.getTarget() != schedule::ComputeTargetKind::Descriptor)
        return false;
      any = true;
      for (const Writer &other :
           writers.lookup({static_cast<unsigned>(effect.getResource()),
                           effect.getDescriptor()}))
        if (other.function != function.getOperation() &&
            (other.dynamic || effect.getDynamic() || !other.width ||
             !effect.getWidth() ||
             (other.low < effect.getLow() + effect.getWidth() &&
              effect.getLow() < other.low + other.width)))
          return false;
    }
    return any;
  };

  SmallVector<std::pair<sim::SimFuncOp, Operation *>> candidates;
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        function.getEntryKind() != sim::EntryKind::Always ||
        function.getHomeRegion() != sim::EventRegion::Active ||
        !function.getCodeUnitIdAttr() ||
        symbolUses.lookup(function.getSymNameAttr()) != 1)
      continue;
    auto spawned = spawns.find(function.getSymNameAttr());
    if (spawned == spawns.end() || spawned->second.size() != 1 ||
        spawned->second.front()->getParentOp() != root ||
        !spawned->second.front().getResult().use_empty())
      continue;
    if (!codeUnitDecls.count(function.getCodeUnitIdAttr().getUInt()))
      continue;
    if (Operation *wait = getLeadingEventWait(function);
        wait && writesExclusively(function))
      candidates.emplace_back(function, wait);
  }
  if (candidates.empty())
    return;

  // The arming copies draw their process seeds from a private initialization
  // stream (18.14.1), so every source process keeps its seed.
  // Without any binding nothing observes process seeds (the bindings were
  // pruned), and the copy needs no stream either.
  uint64_t privateScope = 0;
  design.walk([&](sim::SimRandomInitializationEnterOp enter) {
    privateScope = std::max<uint64_t>(privateScope, enter.getScope() + 1);
  });

  MLIRContext *context = design.getContext();
  OpBuilder builder(context);
  Type bit = builder.getI1Type();
  Type bitRef = sim::RefType::get(context, bit);
  unsigned rewritten = 0;
  for (auto [function, waitOp] : candidates) {
    sim::SimSpawnOp spawn = spawns.lookup(function.getSymNameAttr()).front();
    Location location = function.getLoc();

    sim::SimCodeUnitDeclOp declaration =
        codeUnitDecls.lookup(function.getCodeUnitIdAttr().getUInt());
    // The armed bit: an invisible two-state design variable in the block's
    // scope, 0 before time zero (6.8).
    int64_t id = nextStorage++;
    builder.setInsertionPoint(function);
    sim::SimStorageDeclOp::create(
        builder, location, id, declaration.getScopeId(), bit,
        sim::Lifetime::Design, StringAttr{}, StringAttr{},
        schedule::ComputeObservabilityKindAttr::get(
            context, schedule::ComputeObservabilityKind::Invisible),
        sim::VPITypeSemanticsAttr{});

    // The root binds it and passes it to both processes.
    builder.setInsertionPointToStart(&root.getBody().front());
    Value context0 = root.getBody().front().getArgument(0);
    Value armedRef =
        sim::SimContextStorageOp::create(builder, location, bitRef, context0,
                                         builder.getI64IntegerAttr(id))
            .getResult();

    hoistWaitPrefix(waitOp);
    // Arming process: a copy of the block that waits once and sets `armed`.
    auto arming = cast<sim::SimFuncOp>(function->clone());
    arming.setSymName((function.getSymName() + ".$arm").str());
    arming.setEntryKind(sim::EntryKind::Initial);
    uint64_t unit = function.getCodeUnitIdAttr().getUInt();
    while (codeUnits.contains(unit))
      ++unit;
    codeUnits.insert(unit);
    arming.setCodeUnitIdAttr(builder.getI64IntegerAttr(unit));
    // Its code unit is an internal initial process under the block's unit.
    {
      OpBuilder declBuilder(declaration);
      declBuilder.setInsertionPointAfter(declaration);
      auto armingUnit =
          cast<sim::SimCodeUnitDeclOp>(declBuilder.clone(*declaration));
      armingUnit.setIdAttr(declBuilder.getI64IntegerAttr(unit));
      armingUnit.setCodeUnitKind(sim::EntryKind::Initial);
      armingUnit.setHierarchicalName(
          (declaration.getHierarchicalName() + ".$arm").str());
      armingUnit.setInternal(true);
      armingUnit.removeSourceProcessAttr();
    }
    design.getBody().front().getOperations().insertAfter(
        Block::iterator(function), arming);

    // A design-storage capture, like the block's other variables.
    DictionaryAttr armedAttrs = builder.getDictionaryAttr(
        {builder.getNamedAttr("simulation.capture_kind",
                              builder.getI32IntegerAttr(3)),
         builder.getNamedAttr("simulation.descriptor_id",
                              builder.getI64IntegerAttr(id))});
    for (sim::SimFuncOp process : {function, arming})
      if (failed(process.insertArgument(process.getNumArguments(), bitRef,
                                        armedAttrs, location)))
        return signalPassFailure();
    auto withArmed = [&](sim::SimFuncOp callee) {
      SmallVector<Value> operands(spawn.getOperands());
      operands.push_back(armedRef);
      return sim::SimSpawnOp::create(builder, location,
                                     callee.getSymNameAttr(), operands,
                                     ArrayAttr{}, ArrayAttr{});
    };
    // The arming copy starts right after the block, on a private stream.
    builder.setInsertionPoint(spawn);
    withArmed(function);
    Operation *after = getArmingInsertionPoint(spawn);
    builder.setInsertionPointAfter(after);
    if (privateScope != 0) {
      Value privateActivation = sim::SimRandomInitializationEnterOp::create(
          builder, location, context0,
          builder.getI64IntegerAttr(privateScope));
      withArmed(arming);
      sim::SimRandomInitializationLeaveOp::create(builder, location, context0,
                                                  privateActivation);
    } else {
      withArmed(arming);
    }
    spawn.erase();

    // The arming copy: ^wait resumes into a block that sets `armed` and ends.
    {
      Region &body = arming.getBody();
      Operation *wait = getLeadingEventWait(arming);
      Block *set = new Block;
      body.push_back(set);
      OpBuilder setBuilder = OpBuilder::atBlockEnd(set);
      Value one = arith::ConstantOp::create(setBuilder, location,
                                            setBuilder.getBoolAttr(true));
      sim::SimRefStoreOp::create(setBuilder, location, one,
                                 arming.getArgument(arming.getNumArguments() -
                                                    1));
      sim::SimReturnOp::create(setBuilder, location, ValueRange{});
      wait = rebuildWait(wait, ValueRange{}, set);
      // The copy waits once; it is not the wait of a repeating always loop.
      schedule::remove<schedule::Field::RepeatingAlwaysWait>(wait);
      // Drop the copied body, now unreachable.
      SmallVector<Block *> dead;
      for (Block &block : body)
        if (&block != &body.front() && &block != wait->getBlock() &&
            &block != set)
          dead.push_back(&block);
      for (Block *block : dead)
        block->dropAllDefinedValueUses();
      for (Block *block : dead)
        block->erase();
    }

    // The block itself: ^entry -> ^guard; ^guard runs the body only while
    // armed; ^wait also watches `armed` and resumes into ^guard.
    {
      Region &body = function.getBody();
      Value armed = function.getArgument(function.getNumArguments() - 1);
      Block *wait = waitOp->getBlock();
      Block *start = waitOp->getSuccessor(0);
      Block *guard = new Block;
      body.getBlocks().insertAfter(Region::iterator(wait), guard);
      OpBuilder guardBuilder = OpBuilder::atBlockEnd(guard);
      Value isArmed =
          sim::SimRefLoadOp::create(guardBuilder, location, bit, armed)
              .getResult();
      // The wait's continuation operands come from the entry, which
      // dominates the guard; the guard passes them on to the body.
      SmallVector<Value> carried(splitWait(waitOp).second);
      cf::CondBranchOp::create(guardBuilder, location, isArmed, start, carried,
                               wait, ValueRange{});
      cast<cf::BranchOp>(body.front().getTerminator()).setDest(guard);
      rebuildWait(waitOp, ValueRange{armed}, guard);
      schedule::set<schedule::Field::ArmedCombinational>(
          function, UnitAttr::get(context));
    }
    ++rewritten;
  }
  if (report)
    llvm::errs() << "talos armed event combinational: blocks=" << rewritten
                 << '\n';
  design.removeComputeGraphAttr();
}
} // namespace
} // namespace talos
