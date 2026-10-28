//===- ForwardCopyProcesses.cpp - Substitute single-driver assignments ---===//
//
// A continuous assignment to a net is evaluated whenever an operand changes
// and its result assigned (IEEE 1800-2023 10.3.2); the update is an Active
// event (4.9.1) that may be processed in any order with the other Active
// events (4.7). Where every bit of the net is written by exactly one such
// process (a wire with one driver takes that driver's value, 6.6.1) and
// nothing observes the net itself (VPI off, no strength query, no other
// driver), a reader of the net may evaluate the right-hand sides directly:
// it observes the same values at every point at which the reference
// algorithm could have scheduled the readers (4.3), and an always_comb
// reader's implicit sensitivity follows its reads (9.2.2.2.1), so waits on
// the net become waits on the operands. An edge on a vector is detected on
// its least significant bit (9.4.2), so an edge wait moves to the operand
// bit that drives bit 0. The copy processes and the net are then dead.
//
// The assignment process only ever forwards the value its operands hold
// after a writer's activation. A reader moved onto an operand instead wakes
// on each of its update events (4.4.1, 9.4.2), so the operands must be
// transient-free: every writer stores each bit at most once per activation
// (no `x = 0; ... x = v;`), or the readers keep the net.
//
// This is the substitution Verilator performs in V3Gate; here every pure
// single-write assignment qualifies, relocations (bit taps, slices, packed
// casts) become views of the source and other expressions are cloned into
// each reader. Chains resolve over several rounds (leaves first).
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"
#include "talos/Dialect/Simulation/Transforms/Passes.h"
#include "talos/Runtime/OutputItemFlags.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/Support/raw_ostream.h"

#include <map>
#include <memory>

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_TALOSSIMFORWARDCOPYPROCESSESPASS
#include "talos/Dialect/Simulation/Transforms/Passes.h.inc"

namespace {
namespace sim = ::talos::sim;

/// A root identity: resource kind and descriptor.
struct Root {
  bool net = false;
  uint64_t id = 0;
  bool operator==(const Root &o) const { return net == o.net && id == o.id; }
  bool operator<(const Root &o) const {
    return std::tie(net, id) < std::tie(o.net, o.id);
  }
};

struct SourceRead {
  Operation *read; // ref.load / net.read inside the copy
  Root root;
  uint64_t low = 0, width = 0;
};

struct Copy {
  sim::SimFuncOp function;
  Operation *write = nullptr;
  Root sink;
  uint64_t sinkLow = 0, width = 0;
  SmallVector<SourceRead> reads;
  // Relocation: sink bits == source bits [sourceLow, +width) of reads[0].
  bool relocation = false;
  uint64_t sourceLow = 0;
  unsigned cost = 0; // pure operations cloned per reader for a non-relocation
};

bool isViewOp(Operation *op) {
  return isa<sim::SimRefExtractOp, sim::SimRefSubelementOp, sim::SimNetExtractOp,
             sim::SimDriverExtractOp, sim::SimDriverSubelementOp,
             sim::SimContextStorageOp, sim::SimContextNetOp,
             sim::SimContextDriverOp>(op);
}

std::optional<Root> rootOf(const analysis::HandleFacts &facts, Value v,
                           uint64_t &low, uint64_t &width) {
  auto fact = facts.find(v);
  if (fact == facts.end() || !fact->second.descriptor || fact->second.dynamic ||
      !fact->second.width)
    return std::nullopt;
  if (fact->second.resource != schedule::ComputeResourceKind::Storage &&
      fact->second.resource != schedule::ComputeResourceKind::Net)
    return std::nullopt;
  low = fact->second.low;
  width = fact->second.width;
  return Root{fact->second.resource == schedule::ComputeResourceKind::Net,
              *fact->second.descriptor};
}

/// `cf.br ^b; ^b: views, reads, pure ops, one write; suspend.change/any`.
std::optional<Copy>
matchCopy(sim::SimFuncOp function,
          llvm::function_ref<const analysis::HandleFacts &(sim::SimFuncOp)>
              factsFor,
          std::map<std::string, unsigned> &why) {
  if (function.isExternal() || !function.isPrivate() ||
      function.getHomeRegion() != sim::EventRegion::Active ||
      (function.getEntryKind() != sim::EntryKind::PortInput &&
       function.getEntryKind() != sim::EntryKind::PortOutput &&
       function.getEntryKind() != sim::EntryKind::Continuous))
    return std::nullopt;
  if (function.getBody().getBlocks().size() != 2) {
    ++why["blocks"];
    return std::nullopt;
  }
  // Gate and user-defined primitives keep their terminals (the design
  // database describes them); timing constructs keep their nets.
  for (NamedAttribute attr : function->getAttrs()) {
    StringRef name = attr.getName().getValue();
    if (name.contains("primitive") || name.contains("timing") ||
        name.contains("path") || name.contains("pulse")) {
      ++why["special process"];
      return std::nullopt;
    }
  }
  Block &entry = function.getBody().front();
  Block &body = function.getBody().back();
  auto branch = dyn_cast<cf::BranchOp>(entry.getTerminator());
  if (!branch || branch.getDest() != &body || body.getNumArguments() != 0 ||
      !branch.getDestOperands().empty()) {
    ++why["entry"];
    return std::nullopt;
  }
  for (Operation &op : entry.without_terminator())
    if (!isViewOp(&op) && !(op.getNumResults() == 1 &&
                            op.getNumRegions() == 0 &&
                            isMemoryEffectFree(&op))) {
      ++why["entry op:" + op.getName().getStringRef().str()];
      return std::nullopt;
    }
  Operation *terminator = body.getTerminator();
  bool waitOK = false;
  if (auto wait = dyn_cast<sim::SimSuspendChangeOp>(terminator))
    waitOK = wait.getContinuation() == &body &&
             wait.getContinuationOperands().empty();
  else if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(terminator))
    waitOK = wait.getContinuation() == &body &&
             wait.getContinuationOperands().empty();
  if (!waitOK) {
    ++why["wait"];
    return std::nullopt;
  }
  // Every capture must be a plain context/storage/net/driver capture.
  for (unsigned i = 0; i < entry.getNumArguments(); ++i) {
    auto kind = function.getArgAttrOfType<IntegerAttr>(
        i, sim::metadata::CaptureKind::getNameStr());
    if (!kind || (kind.getInt() != int32_t(sim::CaptureKind::Context) &&
                  kind.getInt() != int32_t(sim::CaptureKind::Storage) &&
                  kind.getInt() != int32_t(sim::CaptureKind::Net) &&
                  kind.getInt() != int32_t(sim::CaptureKind::Driver))) {
      ++why["capture"];
      return std::nullopt;
    }
  }
  Copy copy;
  copy.function = function;
  // Captures must be whole roots (no view attributes) so handles substitute.
  for (unsigned i = 0; i < entry.getNumArguments(); ++i)
    if (DictionaryAttr attrs = function.getArgAttrDict(i))
      for (NamedAttribute attr : attrs)
        if (attr.getName() != sim::metadata::CaptureKind::getNameStr() &&
            attr.getName() != sim::metadata::DescriptorId::getNameStr()) {
          ++why["capture view"];
          return std::nullopt;
        }
  unsigned pure = 0;
  SmallVector<Operation *> reads;
  for (Operation &op : body.without_terminator()) {
    if (isViewOp(&op))
      continue;
    if (isa<sim::SimRefLoadOp, sim::SimNetReadOp>(op)) {
      reads.push_back(&op);
    } else if (isa<sim::SimDriverDriveOp>(op)) {
      if (copy.write) {
        ++why["writes"];
        return std::nullopt;
      }
      copy.write = &op;
    } else if (isa<sim::SimRefStoreOp>(op)) {
      ++why["storage sink"];
      return std::nullopt;
    } else if (op.getNumResults() == 1 && op.getNumRegions() == 0 &&
               isMemoryEffectFree(&op) && op.getNumSuccessors() == 0) {
      ++pure;
    } else {
      ++why["op:" + op.getName().getStringRef().str()];
      return std::nullopt;
    }
  }
  if (!copy.write || reads.empty()) {
    ++why["no read/write"];
    return std::nullopt;
  }
  const analysis::HandleFacts &facts = factsFor(function);
  if (!rootOf(facts, copy.write->getOperand(0), copy.sinkLow, copy.width)) {
    ++why["sink facts"];
    return std::nullopt;
  }
  copy.sink = *rootOf(facts, copy.write->getOperand(0), copy.sinkLow,
                      copy.width);
  for (Operation *read : reads) {
    SourceRead source{read, {}, 0, 0};
    auto root = rootOf(facts, read->getOperand(0), source.low, source.width);
    if (!root) {
      ++why["source facts"];
      return std::nullopt;
    }
    source.root = *root;
    if (source.root == copy.sink) {
      ++why["self"];
      return std::nullopt;
    }
    copy.reads.push_back(source);
  }
  Value value = copy.write->getOperand(1);
  auto width = sim::getPackedWidth(value.getType());
  if (!width || *width != copy.width) {
    ++why["width"];
    return std::nullopt;
  }
  copy.cost = pure;
  // Relocation: one read, and the written value is the loaded value through
  // extracts and packed casts only.
  if (reads.size() == 1) {
    uint64_t offset = 0;
    Value v = value;
    bool relocation = true;
    while (v != reads[0]->getResult(0)) {
      Operation *def = v.getDefiningOp();
      if (!def) {
        relocation = false;
        break;
      }
      if (auto extract = dyn_cast<sim::SimLogicExtractOp>(def)) {
        offset += extract.getLowBit();
        v = extract.getInput();
      } else if (auto extract = dyn_cast<sim::SimAggregateExtractOp>(def)) {
        auto sub = sim::getAggregateProvenanceSubelement(
            extract.getInput().getType(), unsigned(extract.getIndex()));
        if (!sub) {
          relocation = false;
          break;
        }
        offset += sub->first;
        v = extract.getInput();
      } else if (auto cast = dyn_cast<sim::SimPackedFlattenOp>(def)) {
        v = cast.getInput();
      } else if (auto cast = dyn_cast<sim::SimPackedUnflattenOp>(def)) {
        v = cast.getInput();
      } else {
        relocation = false;
        break;
      }
    }
    if (relocation && offset + copy.width <= copy.reads[0].width) {
      copy.relocation = true;
      copy.sourceLow = copy.reads[0].low + offset;
    }
  }
  ++why[copy.relocation ? "relocation" : "expression"];
  return copy;
}

struct Piece {
  uint64_t low = 0, width = 0; // within the sink
  const Copy *copy = nullptr;
};

struct Sink {
  Root root;
  uint64_t width = 0;
  Type type; // declared element type
  SmallVector<Piece> pieces;
  unsigned readers = 0, readerProcesses = 0;
  bool blocked = false;
  std::string blocker;
};

/// The handle a write op writes, or null for an op that writes nothing.
/// Plain writes (one update event each) are modeled exactly; any other
/// write of a storage or net resource is reported with an unknown shape.
Value writtenHandle(Operation *op) {
  if (auto store = dyn_cast<sim::SimRefStoreOp>(op))
    return store.getReference();
  if (auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(op))
    return enqueue.getDestination();
  if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op))
    return drive.getDriver();
  if (auto copy = dyn_cast<sim::SimRefCopyOp>(op))
    return copy.getDestination();
  auto effects = dyn_cast<MemoryEffectOpInterface>(op);
  if (!effects)
    return Value();
  SmallVector<MemoryEffects::EffectInstance> instances;
  effects.getEffects(instances);
  for (const MemoryEffects::EffectInstance &instance : instances)
    if (isa<MemoryEffects::Write>(instance.getEffect()) &&
        instance.getValue() &&
        isa<sim::RefType, sim::NetType, sim::DriverType>(
            instance.getValue().getType()))
      return instance.getValue();
  return Value();
}

bool plainWrite(Operation *op) {
  return isa<sim::SimRefStoreOp, sim::SimNBAEnqueueOp, sim::SimDriverDriveOp>(
      op);
}

Type vectorTypeLike(MLIRContext *context, Type scalar, unsigned width) {
  if (isa<sim::LogicType>(scalar))
    return sim::LogicType::get(context, width);
  return IntegerType::get(context, width);
}

class TalosSimForwardCopyProcessesPass
    : public impl::TalosSimForwardCopyProcessesPassBase<
          TalosSimForwardCopyProcessesPass> {
public:
  using Base::Base;

private:
  void runOnOperation() override;
  /// One round: returns the number of eliminated copy processes.
  unsigned round(sim::SimDesignOp design, bool last);
};

unsigned TalosSimForwardCopyProcessesPass::round(sim::SimDesignOp design,
                                                 bool last) {
  Block &designBlock = design.getBody().front();
  MLIRContext *context = design.getContext();
  analysis::HandleDataflowAnalysis analysis(design);
  std::map<std::string, unsigned> why;
  SmallVector<Copy> copies;
  unsigned processes = 0;
  DenseMap<Operation *, analysis::HandleFacts> factsOf;
  auto factsFor = [&](sim::SimFuncOp function) -> const analysis::HandleFacts & {
    auto [found, inserted] = factsOf.try_emplace(function);
    if (inserted)
      found->second = analysis.derive(function);
    return found->second;
  };
  for (auto function : designBlock.getOps<sim::SimFuncOp>()) {
    if (function.isExternal())
      continue;
    ++processes;
    if (auto copy = matchCopy(function, factsFor, why))
      copies.push_back(std::move(*copy));
  }
  DenseMap<Operation *, const Copy *> copyOf;
  for (const Copy &copy : copies)
    copyOf[copy.function] = &copy;
  // Declared element types by root.
  std::map<Root, Type> types;
  for (auto decl : designBlock.getOps<sim::SimNetDeclOp>())
    types[Root{true, uint64_t(decl.getId())}] = decl.getType();
  for (auto decl : designBlock.getOps<sim::SimStorageDeclOp>())
    types[Root{false, uint64_t(decl.getId())}] = decl.getType();
  std::map<Root, Sink> sinks;
  for (const Copy &copy : copies) {
    Sink &sink = sinks[copy.sink];
    sink.root = copy.sink;
    auto type = types.find(copy.sink);
    if (type == types.end()) {
      sink.blocked = true;
      sink.blocker = "undeclared";
      continue;
    }
    sink.type = type->second;
    auto width = sim::getPackedWidth(sink.type);
    if (!width) {
      sink.blocked = true;
      sink.blocker = "unpacked";
      continue;
    }
    sink.width = *width;
    if (!sim::getPackedScalarType(sink.type)) {
      sink.blocked = true;
      sink.blocker = "unpacked";
      continue;
    }
    sink.pieces.push_back({copy.sinkLow, copy.width, &copy});
    for (const SourceRead &read : copy.reads) {
      auto source = types.find(read.root);
      if (source == types.end() || !sim::getPackedWidth(source->second) ||
          !sim::getPackedScalarType(source->second)) {
        sink.blocked = true;
        sink.blocker = "source not packed";
      }
    }
  }
  // Coverage and value domains.
  for (auto &[root, sink] : sinks) {
    if (sink.blocked)
      continue;
    llvm::sort(sink.pieces, [](const Piece &a, const Piece &b) {
      return a.low < b.low;
    });
    uint64_t next = 0;
    for (const Piece &piece : sink.pieces) {
      if (piece.low != next) {
        sink.blocked = true;
        sink.blocker = "uncovered bits";
        break;
      }
      next = piece.low + piece.width;
    }
    if (!sink.blocked && next != sink.width) {
      sink.blocked = true;
      sink.blocker = "uncovered bits";
    }
    // A 2-state sink is only substituted whole (no concatenation form).
    if (!sink.blocked &&
        !isa<sim::LogicType>(sim::getPackedScalarType(sink.type)) &&
        sink.pieces.size() != 1) {
      sink.blocked = true;
      sink.blocker = "two-state pieces";
    }
    // Each expression piece must read four-state operands of the same
    // domain as the sink it feeds through concatenation.
    if (!sink.blocked)
      for (const Piece &piece : sink.pieces)
        for (const SourceRead &read : piece.copy->reads)
          if (isa<sim::LogicType>(sim::getPackedScalarType(sink.type)) !=
              isa<sim::LogicType>(
                  sim::getPackedScalarType(types[read.root]))) {
            sink.blocked = true;
            sink.blocker = "domain";
          }
  }
  // Declarations and operations that name a sink net by id: another driver
  // (a second driver.decl, a specify path, a switch), a port collapse
  // (net.connect.decl), a VPI reflection, a resolution query. The copies'
  // own drivers must be plain strong drives (6.6.1; a strength pair or a
  // pulled driver changes the resolved value and is observable, 28.11).
  std::map<uint64_t, unsigned> driverDecls;
  design.walk([&](Operation *op) {
    if (isa<sim::SimNetDeclOp, sim::SimStorageDeclOp>(op))
      return;
    for (NamedAttribute attr : op->getAttrs()) {
      StringRef name = attr.getName().getValue();
      if (!name.ends_with("net_id"))
        continue;
      auto id = dyn_cast<IntegerAttr>(attr.getValue());
      if (!id)
        continue;
      auto found = sinks.find(Root{true, id.getValue().getZExtValue()});
      if (found == sinks.end())
        continue;
      if (auto driver = dyn_cast<sim::SimDriverDeclOp>(op)) {
        ++driverDecls[found->first.id];
        if (driver.getStrength0() != sim::Strength::Strong ||
            driver.getStrength1() != sim::Strength::Strong) {
          found->second.blocked = true;
          found->second.blocker = "driver strength";
        }
        continue;
      }
      found->second.blocked = true;
      found->second.blocker = "named by " + op->getName().getStringRef().str();
    }
  });
  for (auto &[root, sink] : sinks)
    if (root.net && !sink.blocked &&
        driverDecls[root.id] != sink.pieces.size()) {
      sink.blocked = true;
      sink.blocker = "driver count";
    }
  // Uses of the sinks across the design.
  struct ReadSite {
    Operation *op;
    Root sink;
    uint64_t low, width;
  };
  struct WaitSite {
    Operation *op;
    unsigned operand;
    Root sink;
    uint64_t low, width;
  };
  SmallVector<ReadSite> readSites;
  SmallVector<WaitSite> waitSites;
  // Every write of a root: the ranges a process writes (a wait moved onto a
  // source must not watch the waiter's own writes) and, per root, the sites
  // whose activation shape decides whether the root is transient-free.
  struct Written {
    Root root;
    uint64_t low, width;
  };
  struct Writer {
    Operation *op;
    Operation *function;
    uint64_t low, width;
    bool nonblocking;
    bool unknownShape; // a write whose publication shape is not modeled
  };
  DenseMap<Operation *, SmallVector<Written>> writtenOf;
  std::map<Root, SmallVector<Writer>> writersOf;
  // $display items that pass a net handle (printed by value unless the
  // format queries strength with %v, which observes the drivers).
  struct DisplaySite {
    Operation *op;
    unsigned operand, flag;
    Root sink;
    uint64_t low, width;
  };
  SmallVector<DisplaySite> displaySites;
  DenseMap<Operation *, Value> contextOf; // function -> context argument
  for (auto function : designBlock.getOps<sim::SimFuncOp>()) {
    if (function.isExternal())
      continue;
    Value ctx;
    for (unsigned i = 0; i < function.getNumArguments(); ++i) {
      auto kind = function.getArgAttrOfType<IntegerAttr>(
          i, sim::metadata::CaptureKind::getNameStr());
      if (kind && kind.getInt() == int32_t(sim::CaptureKind::Context)) {
        ctx = function.getArgument(i);
        break;
      }
    }
    contextOf[function] = ctx;
    const Copy *asCopy = copyOf.lookup(function);
    const analysis::HandleFacts &facts = factsFor(function);
    std::set<Root> readIn;
    // A wait on an expression sink can only move to the operands when the
    // waiter re-evaluates idempotently: a combinational body without side
    // effects (IEEE 1800-2023 9.2.2.2.1) that reads nothing it writes (an
    // accumulator would count its activations); an explicit `@(y)` with
    // effects observes y's own changes (9.4.2) and so does an edge on an
    // expression.
    bool pureComb =
        (function.getEntryKind() == sim::EntryKind::Continuous ||
         function.getEntryKind() == sim::EntryKind::AlwaysComb ||
         function.getEntryKind() == sim::EntryKind::PortInput ||
         function.getEntryKind() == sim::EntryKind::PortOutput) &&
        function.getHomeRegion() == sim::EventRegion::Active;
    if (pureComb) {
      std::set<Root> loaded, stored;
      auto rootOfHandle = [&](Value handle) -> std::optional<Root> {
        auto fact = facts.find(handle);
        if (fact == facts.end() || !fact->second.descriptor ||
            (fact->second.resource != schedule::ComputeResourceKind::Net &&
             fact->second.resource != schedule::ComputeResourceKind::Storage))
          return std::nullopt;
        return Root{fact->second.resource == schedule::ComputeResourceKind::Net,
                    *fact->second.descriptor};
      };
      function.getBody().walk([&](Operation *op) {
        if (isa<sim::SimRefLoadOp, sim::SimNetReadOp>(op)) {
          if (auto root = rootOfHandle(op->getOperand(0)))
            loaded.insert(*root);
          return;
        }
        if (isa<sim::SimRefStoreOp, sim::SimDriverDriveOp>(op)) {
          if (auto root = rootOfHandle(writtenHandle(op)))
            stored.insert(*root);
          else
            pureComb = false;
          return;
        }
        if (isViewOp(op) || op->hasTrait<OpTrait::IsTerminator>() ||
            (op->getNumRegions() == 0 && isMemoryEffectFree(op)))
          return;
        pureComb = false;
      });
      for (const Root &root : stored)
        pureComb &= !loaded.count(root);
    }
    // Timing checks and specify paths observe the port nets themselves (their
    // coordinators name the captured nets): keep every root such a process
    // captures (IEEE 1800-2023 30, 31).
    auto special = [](StringRef name) {
      return name.contains("timing") || name.contains("inertial") ||
             name.contains("pulse") || name.contains("primitive") ||
             name.contains("path");
    };
    bool timing = false;
    for (NamedAttribute attr : function->getAttrs())
      timing |= special(attr.getName().getValue());
    function.walk([&](Operation *op) {
      timing |= special(op->getName().getStringRef());
      for (NamedAttribute attr : op->getAttrs())
        timing |= special(attr.getName().getValue());
    });
    if (timing)
      for (unsigned i = 0; i < function.getNumArguments(); ++i) {
        auto fact = facts.find(function.getArgument(i));
        if (fact == facts.end() || !fact->second.descriptor)
          continue;
        bool net = fact->second.resource == schedule::ComputeResourceKind::Net;
        auto found = sinks.find(Root{net, *fact->second.descriptor});
        if (found != sinks.end()) {
          found->second.blocked = true;
          found->second.blocker = "timing construct";
        }
      }
    auto hit = [&](Value v, uint64_t &low, uint64_t &width) -> Sink * {
      auto fact = facts.find(v);
      if (fact == facts.end() || !fact->second.descriptor)
        return nullptr;
      bool net = fact->second.resource == schedule::ComputeResourceKind::Net;
      if (!net &&
          fact->second.resource != schedule::ComputeResourceKind::Storage)
        return nullptr;
      auto found = sinks.find(Root{net, *fact->second.descriptor});
      if (found == sinks.end())
        return nullptr;
      if (fact->second.dynamic || !fact->second.width) {
        found->second.blocked = true;
        found->second.blocker = "dynamic access";
      }
      low = fact->second.low;
      width = fact->second.width;
      return &found->second;
    };
    function.walk([&](Operation *op) {
      uint64_t low = 0, width = 0;
      if (Value destination = writtenHandle(op)) {
        auto fact = facts.find(destination);
        if (fact != facts.end() && fact->second.descriptor &&
            (fact->second.resource == schedule::ComputeResourceKind::Net ||
             fact->second.resource ==
                 schedule::ComputeResourceKind::Storage)) {
          Root root{fact->second.resource == schedule::ComputeResourceKind::Net,
                    *fact->second.descriptor};
          // A dynamic write covers the whole root.
          uint64_t writeLow = fact->second.dynamic ? 0 : fact->second.low;
          uint64_t writeWidth = fact->second.dynamic ? fact->second.rootWidth
                                                     : fact->second.width;
          writtenOf[function].push_back({root, writeLow, writeWidth});
          writersOf[root].push_back({op, function, writeLow, writeWidth,
                                     isa<sim::SimNBAEnqueueOp>(op),
                                     !plainWrite(op)});
        }
      }
      if (isa<sim::SimRefLoadOp, sim::SimNetReadOp>(op)) {
        if (Sink *s = hit(op->getOperand(0), low, width)) {
          ++s->readers;
          readIn.insert(s->root);
          if (!ctx) {
            s->blocked = true;
            s->blocker = "reader without context";
          }
          readSites.push_back({op, s->root, low, width});
        }
      } else if (Value destination = writtenHandle(op)) {
        if (Sink *s = hit(destination, low, width))
          if (!asCopy || !(asCopy->sink == s->root)) {
            s->blocked = true;
            s->blocker = "other writer";
          }
      } else if (isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp,
                     sim::SimSuspendEdgeOp>(op)) {
        unsigned watched = isa<sim::SimSuspendAnyOp>(op)
                               ? cast<sim::SimSuspendAnyOp>(op).getEdges().size()
                               : 1;
        for (unsigned i = 0; i < std::min<unsigned>(watched, op->getNumOperands());
             ++i)
          if (Sink *s = hit(op->getOperand(i), low, width)) {
            if (!ctx) {
              s->blocked = true;
              s->blocker = "waiter without context";
            }
            bool expression = llvm::any_of(s->pieces, [](const Piece &piece) {
              return !piece.copy->relocation;
            });
            if (expression && !pureComb) {
              s->blocked = true;
              s->blocker = "wait on expression";
            }
            int32_t edge = int32_t(sim::EdgeKind::Change);
            if (auto wait = dyn_cast<sim::SimSuspendEdgeOp>(op))
              edge = int32_t(wait.getEdge());
            else if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(op))
              edge = wait.getEdges()[i];
            if (edge != int32_t(sim::EdgeKind::Change))
              for (const Piece &piece : s->pieces)
                if (piece.low <= low && low < piece.low + piece.width &&
                    !piece.copy->relocation) {
                  s->blocked = true;
                  s->blocker = "edge on expression";
                }
            waitSites.push_back({op, i, s->root, low, width});
          }
      } else if (auto display = dyn_cast<sim::SimDisplayOp>(op)) {
        bool strength = false;
        for (Value item : display.getItems())
          if (auto literal = item.getDefiningOp<sim::SimBytesConstantOp>())
            strength |= literal.getValue().contains("%v") ||
                        literal.getValue().contains("%V");
        // Each flag entry consumes one operand, none when omitted, and the
        // packed value plus the net handle for a net item.
        ArrayRef<int32_t> flags = display.getItemFlags();
        unsigned operand = 2; // after context and descriptor
        for (auto [flag, bits] : llvm::enumerate(flags)) {
          if (bits & 2)
            continue;
          if (!(bits & TALOS_RT_OUTPUT_ITEM_NET)) {
            ++operand;
            continue;
          }
          unsigned handle = operand + 1;
          operand += 2;
          if (handle >= op->getNumOperands())
            break;
          if (Sink *s = hit(op->getOperand(handle), low, width)) {
            if (strength || !ctx) {
              s->blocked = true;
              s->blocker = "display strength";
              continue;
            }
            displaySites.push_back({display.getOperation(), handle,
                                    unsigned(flag), s->root, low, width});
          }
        }
        for (Value value : display.getItems())
          if (isa<sim::RefType>(value.getType()))
            if (Sink *s = hit(value, low, width)) {
              s->blocked = true;
              s->blocker = "display reference";
            }
      } else if (isa<sim::SimSpawnOp>(op) || isViewOp(op) ||
                 op->hasTrait<OpTrait::IsTerminator>()) {
        // Captures, views and other terminators are not uses of the value.
      } else {
        for (Value v : op->getOperands())
          if (isa<sim::RefType, sim::NetType, sim::DriverType>(v.getType()))
            if (Sink *s = hit(v, low, width)) {
              s->blocked = true;
              s->blocker = "use:" + op->getName().getStringRef().str();
            }
      }
    });
    for (const Root &root : readIn)
      ++sinks[root].readerProcesses;
  }
  // Spawns of copies must be plain (unused result) and the only uses. One
  // symbol-use walk of the design indexes every user (a walk per copy is
  // quadratic in the design).
  llvm::StringMap<SmallVector<Operation *, 2>> usersOf;
  std::optional<SymbolTable::UseRange> allUses =
      SymbolTable::getSymbolUses(&design.getBody());
  if (allUses)
    for (const SymbolTable::SymbolUse &use : *allUses)
      usersOf[use.getSymbolRef().getRootReference().getValue()].push_back(
          use.getUser());
  if (!allUses || usersOf.empty())
    design.walk([&](sim::SimSpawnOp spawn) {
      usersOf[spawn.getCallee()].push_back(spawn);
    });
  for (const Copy &copy : copies) {
    bool plain = allUses.has_value();
    sim::SimFuncOp copyFunction = copy.function;
    for (Operation *user : usersOf.lookup(copyFunction.getSymName())) {
      auto spawn = dyn_cast<sim::SimSpawnOp>(user);
      plain &= spawn && spawn->getResult(0).use_empty();
    }
    if (!plain) {
      Sink &sink = sinks[copy.sink];
      sink.blocked = true;
      sink.blocker = "spawn use";
    }
  }
  // Expression pieces are cloned per reader: bound the duplication.
  for (auto &[root, sink] : sinks) {
    if (sink.blocked)
      continue;
    unsigned cost = 0;
    for (const Piece &piece : sink.pieces)
      if (!piece.copy->relocation)
        cost += piece.copy->cost + piece.copy->reads.size();
    if (cost && cost * sink.readers > maximumClones) {
      sink.blocked = true;
      sink.blocker = "clone budget";
    }
  }
  // A process is a function every use of which is a spawn passing the
  // context first; anything else (a called function) activates with its
  // caller, an unknown number of times.
  DenseMap<Operation *, bool> processOf;
  auto isProcess = [&](Operation *function) {
    auto found = processOf.find(function);
    if (found != processOf.end())
      return found->second;
    auto func = cast<sim::SimFuncOp>(function);
    auto users = usersOf.find(func.getSymName());
    bool ok = allUses.has_value() && users != usersOf.end() &&
              !users->second.empty();
    if (ok)
      for (Operation *user : users->second)
        ok &= isa<sim::SimSpawnOp>(user) && user->getNumOperands() > 0 &&
              isa<sim::ContextType>(user->getOperand(0).getType());
    processOf[function] = ok;
    return ok;
  };
  auto writesOverlap = [&](Operation *function, Root root, uint64_t low,
                           uint64_t width) {
    for (const Written &written : writtenOf.lookup(function))
      if (written.root == root && written.low < low + width &&
          low < written.low + written.width)
        return true;
    return false;
  };
  // Readers gain captures at their spawns: a function reached otherwise
  // keeps its sinks.
  {
    auto blockIn = [&](Operation *op, Root root) {
      if (!isProcess(op->getParentOfType<sim::SimFuncOp>())) {
        sinks[root].blocked = true;
        sinks[root].blocker = "reader not spawned";
      }
    };
    for (const ReadSite &site : readSites)
      blockIn(site.op, site.sink);
    for (const WaitSite &site : waitSites)
      blockIn(site.op, site.sink);
    for (const DisplaySite &site : displaySites)
      blockIn(site.op, site.sink);
  }
  // A waiter on a sink whose source it writes itself was woken by the copy
  // of its own output. Moved onto the source it would watch its own writes;
  // whether a process may wake itself is the scheduler's business, so the
  // copy stays (IEEE 1800-2023 9.2.2.2.1 b, 9.4.2).
  for (const WaitSite &site : waitSites) {
    Sink &sink = sinks[site.sink];
    if (sink.blocked)
      continue;
    Operation *function = site.op->getParentOfType<sim::SimFuncOp>();
    bool self = false;
    for (const Piece &piece : sink.pieces) {
      uint64_t begin = std::max(site.low, piece.low);
      uint64_t end = std::min(site.low + site.width, piece.low + piece.width);
      if (begin >= end)
        continue;
      const Copy &copy = *piece.copy;
      if (copy.relocation)
        self |= writesOverlap(function, copy.reads[0].root,
                              copy.sourceLow + (begin - piece.low), end - begin);
      else
        for (const SourceRead &read : copy.reads)
          self |= writesOverlap(function, read.root, read.low, read.width);
    }
    if (self) {
      sink.blocked = true;
      sink.blocker = "self-sensitive reader";
    }
  }
  // The copy forwards the value its source holds after the writer's
  // activation, so a reader of the sink wakes once per activation that
  // changes the source's final value. Moved onto the source, it wakes on
  // every update event of the source (IEEE 1800-2023 4.4.1, 9.4.2). Both
  // agree exactly when each activation of every writer stores each bit of
  // the source at most once: no transient (default, then override) value is
  // ever published. A store reached twice on one activation path, in a loop,
  // from a called function, or beside a nonblocking write of the same root
  // may publish an intermediate value, which the copy never forwarded.
  struct Reach {
    DenseMap<Block *, unsigned> index;
    SmallVector<llvm::BitVector> reachable; // per block: blocks reached
  };
  DenseMap<Operation *, std::unique_ptr<Reach>> reachOf;
  auto reachabilityOf = [&](Operation *function) -> Reach & {
    auto &reach = reachOf[function];
    if (reach)
      return *reach;
    reach = std::make_unique<Reach>();
    Region &body = cast<sim::SimFuncOp>(function).getBody();
    for (Block &block : body)
      reach->index[&block] = reach->index.size();
    unsigned count = reach->index.size();
    reach->reachable.assign(count, llvm::BitVector(count));
    for (Block &block : body) {
      llvm::BitVector &bits = reach->reachable[reach->index[&block]];
      SmallVector<Block *> work;
      auto push = [&](Block *from) {
        // An activation ends at a suspension: its successors run later.
        Operation *terminator = from->getTerminator();
        if (terminator->getName().getStringRef().starts_with(
                "simulation.suspend"))
          return;
        for (Block *next : from->getSuccessors()) {
          unsigned i = reach->index[next];
          if (!bits.test(i)) {
            bits.set(i);
            work.push_back(next);
          }
        }
      };
      push(&block);
      while (!work.empty())
        push(work.pop_back_val());
    }
    return *reach;
  };
  std::map<Root, bool> transientFreeOf;
  auto transientFree = [&](Root root) {
    auto found = transientFreeOf.find(root);
    if (found != transientFreeOf.end())
      return found->second;
    bool &result = transientFreeOf[root];
    result = true;
    auto writers = writersOf.find(root);
    if (writers == writersOf.end())
      return result;
    bool blocking = false, nonblocking = false;
    for (const Writer &writer : writers->second) {
      (writer.nonblocking ? nonblocking : blocking) = true;
      if (writer.unknownShape || !isProcess(writer.function))
        result = false;
    }
    if (blocking && nonblocking)
      result = false;
    for (size_t i = 0; result && i < writers->second.size(); ++i) {
      const Writer &a = writers->second[i];
      Reach &reach = reachabilityOf(a.function);
      Block *blockA = a.op->getBlock();
      if (reach.reachable[reach.index[blockA]].test(reach.index[blockA])) {
        result = false; // a loop repeats the store
        break;
      }
      for (size_t j = i + 1; j < writers->second.size(); ++j) {
        const Writer &b = writers->second[j];
        if (a.low >= b.low + b.width || b.low >= a.low + a.width)
          continue;
        // Two processes' nonblocking writes of one bit commit in the same
        // NBA region and may round-trip before any Active process runs.
        if (b.function != a.function) {
          if (a.nonblocking && b.nonblocking) {
            result = false;
            break;
          }
          continue;
        }
        Block *blockB = b.op->getBlock();
        if (blockA == blockB ||
            reach.reachable[reach.index[blockA]].test(reach.index[blockB]) ||
            reach.reachable[reach.index[blockB]].test(reach.index[blockA])) {
          result = false;
          break;
        }
      }
    }
    return result;
  };
  for (auto &[root, sink] : sinks) {
    if (sink.blocked)
      continue;
    for (const Piece &piece : sink.pieces)
      for (const SourceRead &read : piece.copy->reads)
        if (!transientFree(read.root)) {
          sink.blocked = true;
          sink.blocker = "transient source";
        }
  }
  // Leaves first: a sink whose source is itself an eligible sink waits for
  // the next round, after that source's readers (this copy) were rewritten.
  std::set<Root> eligible;
  for (auto &[root, sink] : sinks)
    if (!sink.blocked)
      eligible.insert(root);
  std::set<Root> ready;
  for (const Root &root : eligible) {
    bool leaf = true;
    for (const Piece &piece : sinks[root].pieces)
      for (const SourceRead &read : piece.copy->reads)
        leaf &= !eligible.count(read.root);
    if (leaf)
      ready.insert(root);
  }
  if (census ||
      (last && !ready.empty() &&
       native::has<native::DebugTiming>(design->getParentOfType<ModuleOp>()))) {
    std::map<std::string, unsigned> blockers;
    unsigned readySinks = 0, readyCopies = 0;
    for (auto &[root, sink] : sinks) {
      if (sink.blocked)
        ++blockers[sink.blocker];
      if (ready.count(root)) {
        ++readySinks;
        readyCopies += sink.pieces.size();
      }
    }
    llvm::errs() << "talos forward-copies: processes=" << processes
                 << " copies=" << copies.size() << " sinks=" << sinks.size()
                 << " eligible=" << eligible.size() << " ready=" << readySinks
                 << " ready_copies=" << readyCopies << '\n';
    for (auto &[reason, count] : why)
      llvm::errs() << "talos forward-copies match: count=" << count
                   << " reason=" << reason << '\n';
    for (auto &[reason, count] : blockers)
      llvm::errs() << "talos forward-copies blocked: count=" << count
                   << " reason=" << reason << '\n';
  }
  if (census || ready.empty())
    return 0;

  // Rewrite. A source root a function now reads becomes one more capture
  // of that function (the analyses that derive activation inputs, effects
  // and certificates work from captures), bound at every spawn of it.
  DenseMap<std::pair<Operation *, uint64_t>, Value> handles[2];
  auto handleFor = [&](OpBuilder &builder, Location loc, Operation *function,
                       Root root) -> Value {
    auto &cache = handles[root.net][{function, root.id}];
    if (cache)
      return cache;
    auto func = cast<sim::SimFuncOp>(function);
    Block &entry = func.getBody().front();
    Type element = types[root];
    Type handleType = root.net
                          ? Type(sim::NetType::get(context, element))
                          : Type(sim::RefType::get(context, element));
    OpBuilder attrs(context);
    DictionaryAttr captureAttrs = attrs.getDictionaryAttr(
        {attrs.getNamedAttr(
             sim::metadata::CaptureKind::getNameStr(),
             attrs.getI32IntegerAttr(root.net
                                         ? int32_t(sim::CaptureKind::Net)
                                         : int32_t(sim::CaptureKind::Storage))),
         attrs.getNamedAttr(sim::metadata::DescriptorId::getNameStr(),
                            attrs.getI64IntegerAttr(root.id))});
    if (failed(func.insertArgument(entry.getNumArguments(), handleType,
                                   captureAttrs, loc)))
      llvm::report_fatal_error("forward-copies: cannot add a capture to " +
                               func.getSymName());
    for (Operation *user : usersOf.lookup(func.getSymName())) {
      auto spawn = cast<sim::SimSpawnOp>(user);
      OpBuilder spawnBuilder(spawn);
      Value ctx = spawn.getOperands().front();
      Value handle = root.net
                         ? Value(sim::SimContextNetOp::create(
                               spawnBuilder, loc, handleType, ctx, root.id))
                         : Value(sim::SimContextStorageOp::create(
                               spawnBuilder, loc, handleType, ctx, root.id));
      spawn.getOperandsMutable().append(handle);
      if (auto argAttrs = spawn.getArgAttrsAttr()) {
        SmallVector<Attribute> expanded(argAttrs.getValue());
        expanded.push_back(captureAttrs);
        spawn.setArgAttrsAttr(spawnBuilder.getArrayAttr(expanded));
      }
    }
    cache = entry.getArguments().back();
    return cache;
  };
  // A view of `width` bits at `low` of `root`, as a vector of its domain.
  auto viewOf = [&](OpBuilder &builder, Location loc, Operation *function,
                    Root root, uint64_t low, uint64_t width) -> Value {
    if (!types.count(root) || !contextOf[function])
      llvm::report_fatal_error(
          Twine("forward-copies: view of undeclared root net=") +
          Twine(root.net) + " id=" + Twine(root.id) + " ctx=" +
          Twine(contextOf[function] ? 1 : 0) + " in " +
          cast<sim::SimFuncOp>(function).getSymName());
    Value handle = handleFor(builder, loc, function, root);
    Type element = types[root];
    Type scalar = sim::getPackedScalarType(element);
    Type vector = vectorTypeLike(context, scalar, unsigned(width));
    if (low == 0 && *sim::getPackedWidth(element) == width &&
        element == vector)
      return handle;
    if (root.net)
      return sim::SimNetExtractOp::create(
          builder, loc, sim::NetType::get(context, vector), handle, low);
    return sim::SimRefExtractOp::create(
        builder, loc, sim::RefType::get(context, vector), handle, low);
  };
  auto readOf = [&](OpBuilder &builder, Location loc, Value view) -> Value {
    if (auto net = dyn_cast<sim::NetType>(view.getType()))
      return sim::SimNetReadOp::create(builder, loc, net.getElementType(),
                                       view);
    return sim::SimRefLoadOp::create(
        builder, loc, cast<sim::RefType>(view.getType()).getElementType(),
        view);
  };
  auto flatten = [&](OpBuilder &builder, Location loc, Value v) -> Value {
    if (isa<sim::LogicType>(v.getType()))
      return v;
    return sim::SimPackedFlattenOp::create(
        builder, loc,
        sim::LogicType::get(context, *sim::getPackedWidth(v.getType())), v);
  };
  auto adapt = [&](OpBuilder &builder, Location loc, Value v,
                   Type target) -> Value {
    if (v.getType() == target)
      return v;
    if (isa<sim::LogicType>(target))
      return flatten(builder, loc, v);
    return sim::SimPackedUnflattenOp::create(builder, loc, target,
                                             flatten(builder, loc, v));
  };
  // The value of the piece's copy, cloned at the builder (expression) or
  // read through a view (relocation), restricted to [low, low + width) of
  // the piece.
  auto pieceValue = [&](OpBuilder &builder, Location loc, Operation *function,
                        const Piece &piece, uint64_t low,
                        uint64_t width) -> Value {
    const Copy &copy = *piece.copy;
    if (copy.relocation)
      return readOf(builder, loc,
                    viewOf(builder, loc, function, copy.reads[0].root,
                           copy.sourceLow + (low - piece.low), width));
    // Clone the copy's own view, read and expression chain against handles
    // of the same roots, so every value keeps its original type.
    IRMapping mapping;
    sim::SimFuncOp source = copy.function;
    Block &entry = source.getBody().front();
    for (unsigned i = 0; i < entry.getNumArguments(); ++i) {
      auto kind = source.getArgAttrOfType<IntegerAttr>(
          i, sim::metadata::CaptureKind::getNameStr());
      auto descriptor = source.getArgAttrOfType<IntegerAttr>(
          i, sim::metadata::DescriptorId::getNameStr());
      if (kind.getInt() == int32_t(sim::CaptureKind::Context)) {
        mapping.map(entry.getArgument(i), contextOf[function]);
      } else if (descriptor &&
                 (kind.getInt() == int32_t(sim::CaptureKind::Storage) ||
                  kind.getInt() == int32_t(sim::CaptureKind::Net))) {
        Root root{kind.getInt() == int32_t(sim::CaptureKind::Net),
                  descriptor.getValue().getZExtValue()};
        if (types.count(root))
          mapping.map(entry.getArgument(i),
                      handleFor(builder, loc, function, root));
      }
    }
    auto touchesDriver = [](Operation &op) {
      for (Value v : op.getOperands())
        if (isa<sim::DriverType>(v.getType()))
          return true;
      for (Value v : op.getResults())
        if (isa<sim::DriverType>(v.getType()))
          return true;
      return false;
    };
    // Constants and other pure definitions may sit in the entry block.
    for (Block *block : {&entry, &source.getBody().back()})
      for (Operation &op : block->without_terminator()) {
        if (&op == copy.write || touchesDriver(op))
          continue;
        builder.clone(op, mapping);
      }
    Value value = mapping.lookup(copy.write->getOperand(1));
    assert(value && "expression value must be cloned");
    if (low == piece.low && width == piece.width)
      return value;
    return sim::SimLogicExtractOp::create(
        builder, loc, sim::LogicType::get(context, unsigned(width)),
        flatten(builder, loc, value), low - piece.low);
  };
  auto sinkValue = [&](OpBuilder &builder, Location loc, Operation *function,
                       const Sink &sink, uint64_t low, uint64_t width,
                       Type target) -> Value {
    SmallVector<Value> parts; // most significant first
    for (const Piece &piece : llvm::reverse(sink.pieces)) {
      uint64_t begin = std::max(low, piece.low);
      uint64_t end = std::min(low + width, piece.low + piece.width);
      if (begin >= end)
        continue;
      parts.push_back(
          pieceValue(builder, loc, function, piece, begin, end - begin));
    }
    Value value;
    if (parts.size() == 1) {
      value = parts.front();
    } else {
      for (Value &part : parts)
        part = flatten(builder, loc, part);
      value = sim::SimLogicConcatOp::create(
          builder, loc, sim::LogicType::get(context, unsigned(width)), parts);
    }
    return adapt(builder, loc, value, target);
  };
  // The source views a wait on [low, low + width) of the sink must watch.
  auto sourceViews = [&](OpBuilder &builder, Location loc, Operation *function,
                         const Sink &sink, uint64_t low, uint64_t width,
                         SmallVectorImpl<Value> &views) {
    for (const Piece &piece : sink.pieces) {
      uint64_t begin = std::max(low, piece.low);
      uint64_t end = std::min(low + width, piece.low + piece.width);
      if (begin >= end)
        continue;
      const Copy &copy = *piece.copy;
      if (copy.relocation) {
        uint64_t sourceLow = copy.sourceLow + (begin - piece.low);
        views.push_back(viewOf(builder, loc, function, copy.reads[0].root,
                               sourceLow, end - begin));
      } else {
        for (const SourceRead &read : copy.reads)
          views.push_back(viewOf(builder, loc, function, read.root, read.low,
                                 read.width));
      }
    }
  };
  unsigned eliminated = 0, rewrittenReads = 0, rewrittenWaits = 0;
  for (const ReadSite &site : readSites) {
    if (!ready.count(site.sink))
      continue;
    const Sink &sink = sinks[site.sink];
    OpBuilder builder(site.op);
    Value value = sinkValue(builder, site.op->getLoc(),
                            site.op->getParentOfType<sim::SimFuncOp>(), sink,
                            site.low, site.width, site.op->getResult(0).getType());
    site.op->getResult(0).replaceAllUsesWith(value);
    site.op->erase();
    ++rewrittenReads;
  }
  // A net item's packed value operand was already substituted as a read;
  // drop the handle and the net flag so the item prints as a plain value.
  // Sites of one display are removed from the highest operand down.
  llvm::sort(displaySites, [](const DisplaySite &a, const DisplaySite &b) {
    return std::make_pair(a.op, a.operand) > std::make_pair(b.op, b.operand);
  });
  for (const DisplaySite &site : displaySites) {
    if (!ready.count(site.sink))
      continue;
    auto display = cast<sim::SimDisplayOp>(site.op);
    OpBuilder builder(display);
    SmallVector<int32_t> flags(display.getItemFlags());
    flags[site.flag] &= ~int32_t(TALOS_RT_OUTPUT_ITEM_NET);
    display.setItemFlagsAttr(builder.getDenseI32ArrayAttr(flags));
    display->eraseOperand(site.operand);
    ++rewrittenReads;
  }
  // Rewrite each wait once: every watched operand that is a ready sink
  // becomes the views of its operands (an edge on a vector is detected on
  // its least significant bit, IEEE 1800-2023 9.4.2: the operand bit that
  // drives bit 0).
  llvm::MapVector<Operation *, SmallVector<const WaitSite *>> waitsByOp;
  for (const WaitSite &site : waitSites)
    if (ready.count(site.sink))
      waitsByOp[site.op].push_back(&site);
  for (auto &[op, sites] : waitsByOp) {
    OpBuilder builder(op);
    Location loc = op->getLoc();
    Operation *function = op->getParentOfType<sim::SimFuncOp>();
    unsigned watchedCount = 1;
    ArrayRef<int32_t> oldEdges;
    SmallVector<int32_t> edgeStorage;
    if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(op)) {
      oldEdges = wait.getEdges();
      watchedCount = oldEdges.size();
    } else if (auto wait = dyn_cast<sim::SimSuspendEdgeOp>(op)) {
      edgeStorage.push_back(int32_t(wait.getEdge()));
      oldEdges = edgeStorage;
    } else {
      edgeStorage.push_back(int32_t(sim::EdgeKind::Change));
      oldEdges = edgeStorage;
    }
    SmallVector<Value> operands;
    SmallVector<int32_t> edges;
    for (unsigned i = 0; i < watchedCount; ++i) {
      const WaitSite *site = nullptr;
      for (const WaitSite *candidate : sites)
        if (candidate->operand == i)
          site = candidate;
      if (!site) {
        operands.push_back(op->getOperand(i));
        edges.push_back(oldEdges[i]);
        continue;
      }
      const Sink &sink = sinks[site->sink];
      SmallVector<Value> views;
      if (oldEdges[i] == int32_t(sim::EdgeKind::Change))
        sourceViews(builder, loc, function, sink, site->low, site->width,
                    views);
      else
        sourceViews(builder, loc, function, sink, site->low, 1, views);
      for (Value view : views) {
        operands.push_back(view);
        edges.push_back(oldEdges[i]);
      }
    }
    SmallVector<Value> continuation;
    if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(op))
      llvm::append_range(continuation, wait.getContinuationOperands());
    else if (auto wait = dyn_cast<sim::SimSuspendChangeOp>(op))
      llvm::append_range(continuation, wait.getContinuationOperands());
    else
      llvm::append_range(
          continuation, cast<sim::SimSuspendEdgeOp>(op).getContinuationOperands());
    if (operands.size() == 1 && !isa<sim::SimSuspendAnyOp>(op)) {
      op->setOperand(0, operands.front());
    } else {
      llvm::append_range(operands, continuation);
      OperationState state(loc, sim::SimSuspendAnyOp::getOperationName());
      state.addOperands(operands);
      state.addAttribute("edges", builder.getDenseI32ArrayAttr(edges));
      for (NamedAttribute attr : op->getAttrs())
        if (attr.getName() != "edges" && attr.getName() != "edge")
          state.addAttribute(attr.getName(), attr.getValue());
      state.addSuccessors(op->getSuccessor(0));
      builder.create(state);
      op->erase();
    }
    ++rewrittenWaits;
  }
  // The copies are dead: erase their spawns and bodies.
  for (const Copy &copy : copies) {
    if (!ready.count(copy.sink))
      continue;
    sim::SimFuncOp deadCopy = copy.function;
    for (Operation *spawn : usersOf.lookup(deadCopy.getSymName()))
      spawn->erase();
    sim::SimFuncOp dead = copy.function;
    dead.erase();
    ++eliminated;
  }
  if (native::has<native::DebugTiming>(design->getParentOfType<ModuleOp>()))
    llvm::errs() << "talos forward-copies round: eliminated=" << eliminated
                 << " sinks=" << ready.size() << " reads=" << rewrittenReads
                 << " waits=" << rewrittenWaits << '\n';
  numEliminated += eliminated;
  return eliminated;
}

void TalosSimForwardCopyProcessesPass::runOnOperation() {
  sim::SimDesignOp design = getOperation();
  for (unsigned r = 0; r < maximumRounds; ++r)
    if (!round(design, r + 1 == maximumRounds))
      break;
}

} // namespace
} // namespace talos
