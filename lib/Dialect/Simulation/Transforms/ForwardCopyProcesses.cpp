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
// The assignment process may run only after a writer's activation or an NBA
// drain, filtering intermediate stores. A reader moved onto an operand wakes
// on each of its update events (4.3, 9.4.2), and a reader moved onto
// expression operands also wakes when the expression keeps its value (9.4.2:
// that is no event of the expression). Such an extra activation is invisible
// when the reader is quiet: a combinational process that evaluates on the
// inputs it waits on and on variable bits it stored earlier in the same
// activation, and whose bits nothing else writes, stores the values they
// already hold, which is no update event (4.3). A quiet reader that stores a
// bit twice (`o = 0; if (y) o = 1;`) still publishes a transient, which the
// waiters of that bit must then be quiet about in turn; a cycle of such
// readers could wake forever, so the proof is a least fixed point. A waiter
// on a relocation needs no quietness proof when every blocking writer stores
// each operand bit at most once per activation, and every immediate NBA writer
// at most once between proven positive delays. #0 and event waits can enqueue
// multiple updates for one NBA drain (4.4.2.4). Nonzero or unknown enqueue
// delays can align commits across those issue windows (4.9.4), so they have no
// transient-free certificate. Level waits, `iff` conditions and clocking
// events see intermediate values and keep the net.
//
// The net must be a plain wire whose strong, undelayed drivers partition it
// and are exactly the copies (6.6.1): tri0/tri1 pulls (6.6.5), trireg charge
// (6.6.4), supply strength (6.6.6), wired and user resolution (6.6.3, 6.6.7)
// and net delays (28.16) give the net a value other than its driver's.
// Nothing else may observe the net: VPI, waveform dumps (21.7) and toggle
// coverage keep it. LRM 4.5 drains the Reactive region set before returning
// to the Active set, so a copy pending after a Reactive writer cannot run
// before a Reactive reader: such a reader keeps the net.
//
// The same substitution applies to a continuous variable assignment with
// exclusive, complete writers. Its storage must have design lifetime and no
// observer of its own. Static initialization reads the declaration default
// before continuous assignments begin (6.8), so those reads keep the variable;
// an unconditional, once-only startup spawn proves that its assignment exists
// before scheduled readers can run. State-domain conversions remain part of
// the cloned RHS, before any reader's extraction or packed-value adaptation.
//
// This is the substitution Verilator performs in V3Gate; here every pure
// single-write assignment qualifies, relocations (bit taps, slices, packed
// casts) become views of the source and other expressions are cloned into
// each reader. Chains resolve over several rounds (leaves first).
//
//===----------------------------------------------------------------------===//

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/NetConnectivityAnalysis.h"
#include "talos/Analysis/StorageWriteAnalysis.h"
#include "talos/Dialect/Coverage/CoverageDialect.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"
#include "talos/Dialect/Simulation/Transforms/Passes.h"
#include "talos/Runtime/OutputItemFlags.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/SetVector.h"
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

Value copyDestination(Operation *write) {
  if (auto store = dyn_cast<sim::SimRefStoreOp>(write))
    return store.getReference();
  return write->getOperand(0);
}

Value copyValue(Operation *write) {
  if (auto store = dyn_cast<sim::SimRefStoreOp>(write))
    return store.getValue();
  return write->getOperand(1);
}

bool isViewOp(Operation *op) {
  return isa<sim::SimRefExtractOp, sim::SimRefSubelementOp,
             sim::SimNetExtractOp, sim::SimDriverExtractOp,
             sim::SimDriverSubelementOp, sim::SimContextStorageOp,
             sim::SimContextNetOp, sim::SimContextDriverOp>(op);
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
std::optional<Copy> matchCopy(sim::SimFuncOp function,
                              const analysis::HandleFacts &facts,
                              std::string &why) {
  if (function.isExternal() || !function.isPrivate() ||
      function.getHomeRegion() != sim::EventRegion::Active ||
      (function.getEntryKind() != sim::EntryKind::PortInput &&
       function.getEntryKind() != sim::EntryKind::PortOutput &&
       function.getEntryKind() != sim::EntryKind::Continuous))
    return std::nullopt;
  if (function.getBody().getBlocks().size() != 2) {
    why = "blocks";
    return std::nullopt;
  }
  // Gate and user-defined primitives keep their terminals (the design
  // database describes them); timing constructs keep their nets.
  for (NamedAttribute attr : function->getAttrs()) {
    StringRef name = attr.getName().getValue();
    if (name.contains("primitive") || name.contains("timing") ||
        name.contains("path") || name.contains("pulse")) {
      why = "special process";
      return std::nullopt;
    }
  }
  Block &entry = function.getBody().front();
  Block &body = function.getBody().back();
  auto branch = dyn_cast<cf::BranchOp>(entry.getTerminator());
  if (!branch || branch.getDest() != &body || body.getNumArguments() != 0 ||
      !branch.getDestOperands().empty()) {
    why = "entry";
    return std::nullopt;
  }
  for (Operation &op : entry.without_terminator())
    if (!isViewOp(&op) &&
        !(op.getNumResults() == 1 && op.getNumRegions() == 0 &&
          isMemoryEffectFree(&op))) {
      why = "entry op:" + op.getName().getStringRef().str();
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
    why = "wait";
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
      why = "capture";
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
          why = "capture view";
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
        why = "writes";
        return std::nullopt;
      }
      copy.write = &op;
    } else if (isa<sim::SimRefStoreOp>(op)) {
      if (copy.write) {
        why = "writes";
        return std::nullopt;
      }
      copy.write = &op;
    } else if (op.getNumResults() == 1 && op.getNumRegions() == 0 &&
               isMemoryEffectFree(&op) && op.getNumSuccessors() == 0) {
      ++pure;
    } else {
      why = "op:" + op.getName().getStringRef().str();
      return std::nullopt;
    }
  }
  if (!copy.write || reads.empty()) {
    why = "no read/write";
    return std::nullopt;
  }
  if (!rootOf(facts, copyDestination(copy.write), copy.sinkLow, copy.width)) {
    why = "sink facts";
    return std::nullopt;
  }
  copy.sink =
      *rootOf(facts, copyDestination(copy.write), copy.sinkLow, copy.width);
  for (Operation *read : reads) {
    SourceRead source{read, {}, 0, 0};
    auto root = rootOf(facts, read->getOperand(0), source.low, source.width);
    if (!root) {
      why = "source facts";
      return std::nullopt;
    }
    source.root = *root;
    if (source.root == copy.sink) {
      why = "self";
      return std::nullopt;
    }
    copy.reads.push_back(source);
  }
  Value value = copyValue(copy.write);
  auto width = sim::getPackedWidth(value.getType());
  if (!width || *width != copy.width) {
    why = "width";
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
  why = copy.relocation ? "relocation" : "expression";
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
  unsigned readers = 0;
  bool blocked = false;
  std::string blocker; // the first reason found
  void block(StringRef reason) {
    if (!blocked)
      blocker = reason.str();
    blocked = true;
  }
};

bool isHandle(Value value) {
  return isa<sim::RefType, sim::NetType, sim::DriverType>(value.getType());
}

/// Calls `write(handle, plain)` for each handle `op` may write. Plain writes
/// (one update event each) are modeled exactly. Any other write has an
/// unknown shape, and so has a handle passed to an operation with unknown
/// effects: a task's ref or output formal (IEEE 1800-2023 13.5) may be
/// stored through any number of times on one activation of the caller.
void forEachWrite(Operation *op,
                  llvm::function_ref<void(Value handle, bool plain)> write) {
  if (auto store = dyn_cast<sim::SimRefStoreOp>(op))
    return write(store.getReference(), true);
  if (auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(op)) {
    // Positive producer delays separate immediate NBA windows, but delayed
    // enqueues can still commit together in a later slot (4.9.4). Clocking
    // output scheduling likewise defers publication beyond the issuing code.
    bool immediate = !enqueue.getClockingOutputAttr();
    if (Value delay = enqueue.getDelay()) {
      auto constant = delay.getDefiningOp<sim::SimTimeConstantOp>();
      immediate &= constant && constant.getValue() == 0;
    }
    return write(enqueue.getDestination(), immediate);
  }
  if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op))
    return write(drive.getDriver(), true);
  if (auto copy = dyn_cast<sim::SimRefCopyOp>(op))
    return write(copy.getDestination(), false);
  // Reads, views and captures transport handles; displays read them.
  if (isa<sim::SimRefLoadOp, sim::SimNetReadOp, sim::SimSpawnOp,
          sim::SimDisplayOp>(op) ||
      isViewOp(op))
    return;
  // An operation that writes design storage or nets as a whole (a task call
  // is a terminator with such effects) may write through every handle it
  // receives. Waits write only the scheduler and process resources.
  bool writesState = true;
  if (auto effects = dyn_cast<MemoryEffectOpInterface>(op)) {
    writesState = false;
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    for (const MemoryEffects::EffectInstance &instance : instances) {
      if (!isa<MemoryEffects::Write>(instance.getEffect()))
        continue;
      if (Value value = instance.getValue()) {
        if (isHandle(value))
          write(value, false);
      } else {
        writesState |=
            isa<sim::StorageResource, sim::NetResource>(instance.getResource());
      }
    }
  }
  if (writesState)
    for (Value operand : op->getOperands())
      if (isHandle(operand))
        write(operand, false);
}

Type vectorTypeLike(MLIRContext *context, Type scalar, unsigned width) {
  if (isa<sim::LogicType>(scalar))
    return sim::LogicType::get(context, width);
  return IntegerType::get(context, width);
}

/// Half-open bit intervals [first, second).
using Interval = std::pair<uint64_t, uint64_t>;

/// Removes `cut` from every interval of `set`.
void subtract(SmallVectorImpl<Interval> &set, Interval cut) {
  SmallVector<Interval> next;
  for (Interval interval : set) {
    if (interval.second <= cut.first || cut.second <= interval.first) {
      next.push_back(interval);
      continue;
    }
    if (interval.first < cut.first)
      next.push_back({interval.first, cut.first});
    if (cut.second < interval.second)
      next.push_back({cut.second, interval.second});
  }
  set.assign(next.begin(), next.end());
}

bool overlaps(uint64_t low, uint64_t width, uint64_t otherLow,
              uint64_t otherWidth) {
  return low < otherLow + otherWidth && otherLow < low + width;
}

/// A design root a handle selects. A dynamic or unbounded selection covers
/// the whole root.
struct Access {
  Operation *op = nullptr;
  Root root;
  uint64_t low = 0, width = 0;
  bool dynamic = false;
};

struct Write : Access {
  bool plain = false; // one update event, see forEachWrite
  bool nonblocking = false;
};

struct Wait : Access {
  unsigned operand = 0;
  int32_t edge = 0;
};

struct DisplayItem : Access {
  unsigned operand = 0, flag = 0;
  bool strength = false;
};

/// An unresolved handle whose producer gives no bounded design provenance.
/// Resolve this against the design's declarations, independently each round.
struct UnboundedAccess {
  Operation *op = nullptr;
  bool net = false;
  bool write = false;
  bool nonblocking = false;
  /// An entry formal can instead be observed through every closed call site.
  /// Other opaque origins always retain the design-wide fallback.
  std::optional<unsigned> formal;
};

/// What one round needs to know about one function, derived from its body,
/// captures and attributes alone. The summary of a function a round did not
/// edit carries over to the next round, and so do its lazily solved facts.
struct Summary {
  sim::SimFuncOp function;
  std::optional<Copy> copy;
  std::string why; // how matchCopy classified it, for the census
  Value context;
  /// A continuous, port or always_comb process in the Active region whose
  /// body only reads, stores and drives known roots and evaluates pure
  /// operations.
  bool combinational = false;
  bool timing = false;  // a timing check, specify path or primitive
  bool unknown = false; // accesses a handle of no single known root
  /// Suspends other than at change, edge or `suspend.any` waits: a delay, a
  /// level wait, a join, a task call, a return.
  bool otherSuspension = false;
  SmallVector<Root> captured;
  SmallVector<Access> reads;
  SmallVector<Write> writes;
  SmallVector<Wait> waits;
  SmallVector<DisplayItem> displays;
  SmallVector<Access> displayReferences;
  /// Any other operand naming a root: a level wait, the condition of an
  /// `iff`, a clocking event, an unknown operation.
  SmallVector<Access> uses;
  SmallVector<UnboundedAccess> unbounded;
  /// Nets named by a `*net_id` attribute of an operation in the body.
  SmallVector<std::pair<StringRef, uint64_t>> namedNets;
  std::unique_ptr<analysis::WriteExecutionBounds> bounds, nbaBounds;
  std::optional<bool> storesOnce, evaluatesOnInputs;
};

bool isSpecial(StringRef name) {
  return name.contains("timing") || name.contains("inertial") ||
         name.contains("pulse") || name.contains("primitive") ||
         name.contains("path");
}

/// Operand `index` of `op` is forwarded to a successor block.
bool isForwarded(Operation *op, unsigned index) {
  auto branch = dyn_cast<BranchOpInterface>(op);
  if (!branch)
    return false;
  for (unsigned successor = 0; successor < op->getNumSuccessors();
       ++successor) {
    OperandRange forwarded =
        branch.getSuccessorOperands(successor).getForwardedOperands();
    if (!forwarded.empty() && index >= forwarded.getBeginOperandIndex() &&
        index < forwarded.getBeginOperandIndex() + forwarded.size())
      return true;
  }
  return false;
}

/// Reads only `function`: safe to run concurrently with the summaries of
/// other functions.
std::unique_ptr<Summary>
summarize(sim::SimFuncOp function,
          const analysis::HandleDataflowAnalysis &analysis) {
  auto summary = std::make_unique<Summary>();
  summary->function = function;
  analysis::HandleFacts facts = analysis.derive(function);
  summary->copy = matchCopy(function, facts, summary->why);
  for (unsigned i = 0; i < function.getNumArguments(); ++i) {
    auto kind = function.getArgAttrOfType<IntegerAttr>(
        i, sim::metadata::CaptureKind::getNameStr());
    if (kind && kind.getInt() == int32_t(sim::CaptureKind::Context)) {
      summary->context = function.getArgument(i);
      break;
    }
  }
  auto access = [&](Operation *op, Value handle) -> std::optional<Access> {
    auto fact = facts.find(handle);
    if (fact == facts.end() || !fact->second.descriptor ||
        (fact->second.resource != schedule::ComputeResourceKind::Net &&
         fact->second.resource != schedule::ComputeResourceKind::Storage))
      return std::nullopt;
    Access result;
    result.op = op;
    result.root =
        Root{fact->second.resource == schedule::ComputeResourceKind::Net,
             *fact->second.descriptor};
    result.dynamic = fact->second.dynamic || !fact->second.width;
    result.low = result.dynamic ? 0 : fact->second.low;
    result.width = result.dynamic ? fact->second.rootWidth : fact->second.width;
    return result;
  };
  // A join may forget its descriptor while still selecting a live design
  // root. Retain every possible source until that observation can be
  // rewritten. Proven local allocations cannot alias design declarations.
  // Unknown factories (including virtual-interface accessors) and unbound
  // arguments conservatively observe the design roots of the handle's kind.
  auto unresolved = [&](Operation *op, Value handle, bool write = false) {
    summary->unknown = true;
    DenseSet<Value> visited;
    SmallVector<Value> work{handle};
    std::map<Root, uint64_t> roots;
    llvm::SetVector<unsigned> formals;
    bool unbounded = false;
    while (!work.empty()) {
      Value value = work.pop_back_val();
      if (!visited.insert(value).second)
        continue;
      auto fact = facts.find(value);
      if (fact != facts.end()) {
        const auto &target = fact->second;
        if (target.resource == schedule::ComputeResourceKind::Local)
          continue;
        if (target.descriptor && target.rootWidth &&
            (target.resource == schedule::ComputeResourceKind::Storage ||
             target.resource == schedule::ComputeResourceKind::Net)) {
          Root root{target.resource == schedule::ComputeResourceKind::Net,
                    *target.descriptor};
          roots[root] = std::max(roots[root], target.rootWidth);
          continue;
        }
      }
      if (auto argument = dyn_cast<BlockArgument>(value)) {
        Block *block = argument.getOwner();
        if (block == &function.getBody().front()) {
          auto kind = function.getArgAttrOfType<IntegerAttr>(
              argument.getArgNumber(), sim::metadata::CaptureKind::getNameStr());
          if (kind && kind.getInt() == int32_t(sim::CaptureKind::Formal)) {
            formals.insert(argument.getArgNumber());
            continue;
          }
        }
        bool incoming = false;
        for (Block *predecessor : block->getPredecessors()) {
          auto branch = dyn_cast<BranchOpInterface>(predecessor->getTerminator());
          if (!branch) {
            unbounded = true;
            continue;
          }
          for (unsigned i = 0; i < branch->getNumSuccessors(); ++i) {
            if (branch->getSuccessor(i) != block)
              continue;
            incoming = true;
            SuccessorOperands operands = branch.getSuccessorOperands(i);
            unsigned index = argument.getArgNumber();
            if (index < operands.size() && operands[index])
              work.push_back(operands[index]);
            else
              unbounded = true;
          }
        }
        unbounded |= !incoming;
        continue;
      }
      Operation *definition = value.getDefiningOp();
      if (auto select = dyn_cast_or_null<arith::SelectOp>(definition)) {
        work.push_back(select.getTrueValue());
        work.push_back(select.getFalseValue());
        continue;
      }
      if (definition && isViewOp(definition) &&
          definition->getNumOperands() && isHandle(definition->getOperand(0))) {
        work.push_back(definition->getOperand(0));
        continue;
      }
      unbounded = true;
    }
    for (auto [root, width] : roots) {
      Access possible{op, root, 0, width, true};
      if (write) {
        Write possibleWrite;
        static_cast<Access &>(possibleWrite) = possible;
        possibleWrite.nonblocking = isa<sim::SimNBAEnqueueOp>(op);
        summary->writes.push_back(possibleWrite);
      } else {
        summary->uses.push_back(possible);
      }
    }
    if (unbounded)
      summary->unbounded.push_back(
          {op, isa<sim::NetType, sim::DriverType>(handle.getType()), write,
           isa<sim::SimNBAEnqueueOp>(op), std::nullopt});
    for (unsigned formal : formals)
      summary->unbounded.push_back(
          {op, isa<sim::NetType, sim::DriverType>(handle.getType()), write,
           isa<sim::SimNBAEnqueueOp>(op), formal});
  };
  bool combinational =
      (function.getEntryKind() == sim::EntryKind::Continuous ||
       function.getEntryKind() == sim::EntryKind::AlwaysComb ||
       function.getEntryKind() == sim::EntryKind::PortInput ||
       function.getEntryKind() == sim::EntryKind::PortOutput) &&
      function.getHomeRegion() == sim::EventRegion::Active;
  bool timing = false;
  for (NamedAttribute attr : function->getAttrs())
    timing |= isSpecial(attr.getName().getValue());
  function.walk([&](Operation *op) {
    timing |= isSpecial(op->getName().getStringRef());
    for (NamedAttribute attr : op->getAttrs()) {
      timing |= isSpecial(attr.getName().getValue());
      if (attr.getName().getValue().ends_with("net_id"))
        if (auto id = dyn_cast<IntegerAttr>(attr.getValue()))
          summary->namedNets.push_back(
              {op->getName().getStringRef(), id.getValue().getZExtValue()});
    }
    if (op == function.getOperation())
      return;
    if (combinational &&
        !isa<sim::SimRefLoadOp, sim::SimNetReadOp, sim::SimRefStoreOp,
             sim::SimDriverDriveOp>(op) &&
        !isViewOp(op) && !op->hasTrait<OpTrait::IsTerminator>() &&
        !(op->getNumRegions() == 0 && isMemoryEffectFree(op)))
      combinational = false;
    bool writes = false;
    forEachWrite(op, [&](Value destination, bool plain) {
      writes = true;
      std::optional<Access> target = access(op, destination);
      if (!target) {
        combinational = false;
        unresolved(op, destination, /*write=*/true);
        return;
      }
      Write write;
      static_cast<Access &>(write) = *target;
      write.plain = plain;
      write.nonblocking = isa<sim::SimNBAEnqueueOp>(op);
      summary->writes.push_back(write);
    });
    if (isa<sim::SimRefLoadOp, sim::SimNetReadOp>(op)) {
      if (std::optional<Access> source = access(op, op->getOperand(0)))
        summary->reads.push_back(*source);
      else
        unresolved(op, op->getOperand(0));
      return;
    }
    // A packed reference copy reads its source without a ref.load. Keep
    // that source materialized: substituting reads does not rewrite the
    // handle consumed here. Its destination remains an ordinary writer.
    if (auto copy = dyn_cast<sim::SimRefCopyOp>(op)) {
      if (std::optional<Access> source = access(op, copy.getSource()))
        summary->uses.push_back(*source);
      else
        unresolved(op, copy.getSource());
    }
    bool wait = isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp,
                    sim::SimSuspendEdgeOp>(op);
    if (!wait && (sim::isSuspensionOp(op) || isa<sim::SimReturnOp>(op)))
      summary->otherSuspension = true;
    if (writes)
      return;
    if (wait) {
      unsigned watched = 1;
      if (auto any = dyn_cast<sim::SimSuspendAnyOp>(op))
        watched = any.getEdges().size();
      for (unsigned i = 0;
           i < std::min<unsigned>(watched, op->getNumOperands()); ++i) {
        std::optional<Access> target = access(op, op->getOperand(i));
        if (!target) {
          unresolved(op, op->getOperand(i));
          continue;
        }
        Wait wait;
        static_cast<Access &>(wait) = *target;
        wait.operand = i;
        wait.edge = int32_t(sim::EdgeKind::Change);
        if (auto edge = dyn_cast<sim::SimSuspendEdgeOp>(op))
          wait.edge = int32_t(edge.getEdge());
        else if (auto any = dyn_cast<sim::SimSuspendAnyOp>(op))
          wait.edge = any.getEdges()[i];
        summary->waits.push_back(wait);
      }
      return;
    }
    if (auto display = dyn_cast<sim::SimDisplayOp>(op)) {
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
        if (bits & TALOS_RT_OUTPUT_ITEM_OMITTED)
          continue;
        if (!(bits & TALOS_RT_OUTPUT_ITEM_NET)) {
          ++operand;
          continue;
        }
        unsigned handle = operand + 1;
        operand += 2;
        if (handle >= op->getNumOperands())
          break;
        if (std::optional<Access> target = access(op, op->getOperand(handle))) {
          DisplayItem item;
          static_cast<Access &>(item) = *target;
          item.operand = handle;
          item.flag = unsigned(flag);
          item.strength = strength;
          summary->displays.push_back(item);
        } else
          unresolved(op, op->getOperand(handle));
      }
      for (Value value : display.getItems())
        if (isa<sim::RefType>(value.getType())) {
          if (std::optional<Access> target = access(op, value))
            summary->displayReferences.push_back(*target);
          else
            unresolved(op, value);
        }
      return;
    }
    // Captures and views transport handles.
    if (isa<sim::SimSpawnOp>(op) || isViewOp(op))
      return;
    for (OpOperand &operand : op->getOpOperands())
      if (isHandle(operand.get()) &&
          !isForwarded(op, operand.getOperandNumber())) {
        if (std::optional<Access> target = access(op, operand.get()))
          summary->uses.push_back(*target);
        else
          unresolved(op, operand.get());
      }
  });
  summary->combinational = combinational;
  summary->timing = timing;
  // Timing checks and specify paths observe the port nets themselves (their
  // coordinators name the captured nets): such a process keeps every root it
  // captures (IEEE 1800-2023 30, 31).
  if (timing)
    for (BlockArgument argument : function.getArguments())
      if (std::optional<Access> target = access(nullptr, argument))
        summary->captured.push_back(target->root);
      else if (isHandle(argument))
        unresolved(function.getOperation(), argument);
  return summary;
}

uint64_t keyOf(Root root) { return (root.id << 1) | uint64_t(root.net); }

/// Design facts that the rounds share. Declarations and connections never
/// change while copies are forwarded. Symbol users are reindexed after a
/// round edits bodies; function summaries carry over unless a round edited
/// the function.
struct DesignState {
  std::unique_ptr<analysis::HandleDataflowAnalysis> analysis;
  std::map<Root, Type> types; // declared element types
  std::shared_ptr<const analysis::IsolatedWireDriverTopology> topology;
  bool waveforms = false;
  /// Roots whose own update events are observed outside the processes:
  /// visible to VPI, toggle coverage.
  DenseSet<uint64_t> observed;
  /// Fixed roots whose storage exists for the entire simulation.
  DenseSet<uint64_t> permanent;
  /// Once-only, unconditional spawns before scheduled execution begins.
  DenseSet<Operation *> startupSpawns;
  SmallVector<sim::SimNetDeclOp> nets;
  /// Top-level operations other than declarations that name a net by id.
  SmallVector<std::pair<StringRef, uint64_t>> namedNets;
  std::map<uint64_t, unsigned> driverDecls;
  bool usesKnown = false;
  llvm::StringMap<SmallVector<Operation *, 2>> usersOf;
  DenseMap<Operation *, bool> processOf;
  /// Functions that run in, or are called or spawned from, the Reactive
  /// region set.
  DenseSet<Operation *> nonActive;
  DenseMap<Operation *, std::unique_ptr<Summary>> summaries;
};

/// A symbol reference on a spawn need not name its callee: discardable
/// attributes can refer to other functions on the same operation.
sim::SimSpawnOp getSpawnOf(Operation *user, StringRef callee) {
  auto spawn = dyn_cast<sim::SimSpawnOp>(user);
  return spawn && spawn.getCallee() == callee ? spawn : sim::SimSpawnOp();
}

/// Index all symbol users once per round rather than walking the design for
/// each copy. Cloning expressions can transport discardable symbol references,
/// so even non-spawn users must be refreshed after their bodies change.
void indexSymbolUsers(sim::SimDesignOp design, DesignState &state) {
  state.usersOf.clear();
  state.processOf.clear();
  std::optional<SymbolTable::UseRange> allUses =
      SymbolTable::getSymbolUses(&design.getBody());
  state.usesKnown = allUses.has_value();
  if (allUses) {
    // An operation can name the same symbol in several attributes. Consumers
    // mutate each user once, independently of its number of symbol uses.
    DenseSet<std::pair<StringAttr, Operation *>> indexed;
    for (const SymbolTable::SymbolUse &use : *allUses) {
      StringAttr name = use.getSymbolRef().getRootReference();
      if (indexed.insert({name, use.getUser()}).second)
        state.usersOf[name.getValue()].push_back(use.getUser());
    }
  }
  if (!allUses || state.usersOf.empty())
    design.walk([&](sim::SimSpawnOp spawn) {
      state.usersOf[spawn.getCallee()].push_back(spawn);
    });
}

/// If-convert the pure short-circuit triangles of a small continuous
/// expression. Its i1 branch condition already encodes the four-state
/// controlling-value test, so selecting its original outgoing values keeps
/// X/Z behavior. Only permanent fixed-range reads and speculatable operations
/// can move out of an arm; calls, dynamic accesses and effects stay conditional.
/// The existing expression-cloning budget also bounds this normalization.
bool normalizePureExpression(sim::SimFuncOp function,
                              const analysis::HandleFacts &facts,
                              const DesignState &state, unsigned budget) {
  if (!budget || function.isExternal() || !function.isPrivate() ||
      function.getHomeRegion() != sim::EventRegion::Active ||
      (function.getEntryKind() != sim::EntryKind::Continuous &&
       function.getEntryKind() != sim::EntryKind::PortInput &&
       function.getEntryKind() != sim::EntryKind::PortOutput))
    return false;
  bool special = false;
  uint64_t cost = 0;
  function.walk([&](Operation *op) {
    ++cost;
    special |= isSpecial(op->getName().getStringRef());
    for (NamedAttribute attr : op->getAttrs())
      special |= isSpecial(attr.getName().getValue());
  });
  if (special || cost > budget)
    return false;
  IRRewriter rewriter(function.getContext());
  bool changed = false, again = true;
  while (again) {
    again = false;
    for (Block &head : function.getBody()) {
      auto conditional = dyn_cast<cf::CondBranchOp>(head.getTerminator());
      if (!conditional)
        continue;
      for (bool shortOnTrue : {true, false}) {
        Block *join = shortOnTrue ? conditional.getTrueDest()
                                  : conditional.getFalseDest();
        Block *arm = shortOnTrue ? conditional.getFalseDest()
                                 : conditional.getTrueDest();
        auto shortArgs = shortOnTrue ? conditional.getTrueDestOperands()
                                     : conditional.getFalseDestOperands();
        auto armArgs = shortOnTrue ? conditional.getFalseDestOperands()
                                   : conditional.getTrueDestOperands();
        if (arm == join || arm == &head || join == &head ||
            !arm->hasOneUse() || arm->getNumArguments() || !armArgs.empty() ||
            cost + join->getNumArguments() > budget)
          continue;
        auto toJoin = dyn_cast<cf::BranchOp>(arm->getTerminator());
        if (!toJoin || toJoin.getDest() != join ||
            toJoin.getDestOperands().size() != shortArgs.size())
          continue;
        bool safe = llvm::all_of(arm->without_terminator(), [&](Operation &op) {
          if (op.getNumRegions() || op.getNumSuccessors())
            return false;
          if (isa<sim::SimRefLoadOp, sim::SimNetReadOp>(op)) {
            uint64_t low, width;
            auto root = rootOf(facts, op.getOperand(0), low, width);
            if (!root || !state.permanent.contains(keyOf(*root)))
              return false;
            auto type = state.types.find(*root);
            auto span = type == state.types.end()
                            ? std::nullopt
                            : sim::getPackedWidth(type->second);
            return span && low <= *span && width <= *span - low;
          }
          return isMemoryEffectFree(&op) && isSpeculatable(&op);
        });
        if (!safe)
          continue;
        Value condition = conditional.getCondition();
        Location loc = conditional.getLoc();
        SmallVector<Value> armValues(toJoin.getDestOperands());
        SmallVector<Value> shortValues(shortArgs);
        rewriter.eraseOp(toJoin);
        rewriter.setInsertionPoint(conditional);
        auto branch = rewriter.replaceOpWithNewOp<cf::BranchOp>(
            conditional, join, shortValues);
        if (arm->empty())
          rewriter.eraseBlock(arm);
        else
          rewriter.inlineBlockBefore(arm, branch);
        rewriter.setInsertionPoint(branch);
        SmallVector<Value> values;
        for (auto [shortValue, armValue] : llvm::zip(shortValues, armValues))
          values.push_back(arith::SelectOp::create(
              rewriter, loc, condition, shortOnTrue ? shortValue : armValue,
              shortOnTrue ? armValue : shortValue));
        rewriter.modifyOpInPlace(branch, [&] {
          branch.getDestOperandsMutable().assign(values);
        });
        cost += values.size();
        if (join->hasOneUse()) {
          rewriter.eraseOp(branch);
          rewriter.setInsertionPointToEnd(&head);
          rewriter.mergeBlocks(join, &head, values);
        }
        changed = again = true;
        break;
      }
      if (again)
        break;
    }
  }
  return changed;
}

class TalosSimForwardCopyProcessesPass
    : public impl::TalosSimForwardCopyProcessesPassBase<
          TalosSimForwardCopyProcessesPass> {
public:
  using Base::Base;

private:
  void runOnOperation() override;
  /// One round: returns the number of eliminated copy processes.
  unsigned round(sim::SimDesignOp design, DesignState &state, bool last);
};

unsigned TalosSimForwardCopyProcessesPass::round(sim::SimDesignOp design,
                                                 DesignState &state,
                                                 bool last) {
  Block &designBlock = design.getBody().front();
  MLIRContext *context = design.getContext();
  // Summaries of functions edited by the previous round, solved in parallel.
  SmallVector<Summary *> all;
  {
    SmallVector<sim::SimFuncOp> missing;
    for (auto function : designBlock.getOps<sim::SimFuncOp>())
      if (!function.isExternal() && !state.summaries.count(function))
        missing.push_back(function);
    SmallVector<std::unique_ptr<Summary>> solved(missing.size());
    parallelFor(context, 0, missing.size(), [&](size_t index) {
      solved[index] = summarize(missing[index], *state.analysis);
    });
    for (auto [function, summary] : llvm::zip(missing, solved))
      state.summaries[function] = std::move(summary);
    for (auto function : designBlock.getOps<sim::SimFuncOp>())
      if (!function.isExternal())
        all.push_back(state.summaries[function].get());
  }
  DenseMap<Operation *, Summary *> summaryOf;
  for (Summary *summary : all)
    summaryOf[summary->function] = summary;
  std::map<Root, Type> &types = state.types;
  llvm::StringMap<SmallVector<Operation *, 2>> &usersOf = state.usersOf;
  auto contextOf = [&](Operation *function) {
    return summaryOf.lookup(function)->context;
  };
  std::map<std::string, unsigned> why;
  SmallVector<const Copy *> copies;
  unsigned processes = all.size();
  for (Summary *summary : all) {
    if (!summary->why.empty())
      ++why[summary->why];
    if (summary->copy)
      copies.push_back(&*summary->copy);
  }
  std::map<Root, Sink> sinks;
  for (const Copy *copy : copies) {
    Sink &sink = sinks[copy->sink];
    sink.root = copy->sink;
    auto type = types.find(copy->sink);
    if (type == types.end()) {
      sink.block("undeclared");
      continue;
    }
    sink.type = type->second;
    auto width = sim::getPackedWidth(sink.type);
    if (!width || !sim::getPackedScalarType(sink.type)) {
      sink.block("unpacked");
      continue;
    }
    sink.width = *width;
    if (!copy->sink.net &&
        !state.permanent.contains(keyOf(copy->sink)))
      sink.block("nonpermanent storage");
    if (!copy->sink.net && state.observed.contains(keyOf(copy->sink)))
      sink.block("observable storage");
    if (!copy->sink.net && state.waveforms)
      sink.block("waveform dump");
    sink.pieces.push_back({copy->sinkLow, copy->width, copy});
    for (const SourceRead &read : copy->reads) {
      auto source = types.find(read.root);
      if (source == types.end() || !sim::getPackedWidth(source->second) ||
          !sim::getPackedScalarType(source->second))
        sink.block("source not packed");
    }
  }
  // Coverage and value domains.
  for (auto &[root, sink] : sinks) {
    if (sink.blocked)
      continue;
    llvm::sort(sink.pieces,
               [](const Piece &a, const Piece &b) { return a.low < b.low; });
    uint64_t next = 0;
    for (const Piece &piece : sink.pieces) {
      if (piece.low != next) {
        sink.block("uncovered bits");
        break;
      }
      next = piece.low + piece.width;
    }
    if (next != sink.width)
      sink.block("uncovered bits");
    // A 2-state sink is only substituted whole (no concatenation form).
    if (!isa<sim::LogicType>(sim::getPackedScalarType(sink.type)) &&
        sink.pieces.size() != 1)
      sink.block("two-state pieces");
    // A relocation preserves its source domain. Storage expressions keep
    // their explicit from_bits/to_bits conversions when cloned, so they can
    // cross domains without reinterpreting X/Z as integer value bits. Retain
    // the existing same-domain admission for net expressions.
    for (const Piece &piece : sink.pieces)
      for (const SourceRead &read : piece.copy->reads)
        if ((root.net || piece.copy->relocation) &&
            isa<sim::LogicType>(sim::getPackedScalarType(sink.type)) !=
            isa<sim::LogicType>(sim::getPackedScalarType(types[read.root])))
          sink.block("domain");
  }
  // The net's value must be its drivers' (IEEE 1800-2023 6.6.1): a plain,
  // undelayed wire whose strong drivers partition it, with no collapsed
  // connection, user resolution or pass switch (the shared single-driver
  // topology). Its own observers keep it: VPI, toggle coverage, and waveform
  // dumps, whose scope/depth selections may name any net (21.7).
  for (sim::SimNetDeclOp decl : state.nets) {
    auto found = sinks.find(Root{true, uint64_t(decl.getId())});
    if (found == sinks.end())
      continue;
    Sink &sink = found->second;
    std::optional<schedule::ComputeObservabilityKind> observed =
        decl.getObservability();
    if (!state.topology->partitionedDriverNets.contains(decl.getId()))
      sink.block("not a plain single-driver wire");
    else if (observed &&
             *observed != schedule::ComputeObservabilityKind::Invisible)
      sink.block("observable net");
    else if (cov::has<cov::ToggleObservable>(decl))
      sink.block("toggle coverage");
    else if (state.waveforms)
      sink.block("waveform dump");
  }
  // Declarations and operations that name a sink net by id: a driver that is
  // not one of the copies (a gate, a specify path), a port collapse
  // (net.connect.decl), a resolution query. Port and collapsed-net
  // reflections (port.decl, vpi_net_identity.decl) only name the net for VPI,
  // which is off, and for waveform dumps and toggle coverage, which mark the
  // design or the canonical declaration and were checked above.
  auto namedBy = [&](StringRef name, uint64_t id) {
    auto found = sinks.find(Root{true, id});
    if (found != sinks.end())
      found->second.block("named by " + name.str());
  };
  for (auto [name, id] : state.namedNets)
    namedBy(name, id);
  for (Summary *summary : all)
    for (auto [name, id] : summary->namedNets)
      namedBy(name, id);
  for (auto &[root, sink] : sinks)
    if (root.net && state.driverDecls[root.id] != sink.pieces.size())
      sink.block("driver count");
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
    int32_t edge;
  };
  // $display items that pass a net handle (printed by value unless the
  // format queries strength with %v, which observes the drivers).
  struct DisplaySite {
    Operation *op;
    unsigned operand, flag;
    Root sink;
    uint64_t low, width;
  };
  SmallVector<ReadSite> readSites;
  SmallVector<WaitSite> waitSites;
  SmallVector<DisplaySite> displaySites;
  // Every write of every root: per root, the sites whose activation shape
  // decides whether the root is transient-free.
  struct Writer {
    Operation *op;
    Operation *function;
    uint64_t low, width;
    bool nonblocking;
    bool unknownShape; // a write whose publication shape is not modeled
  };
  DenseMap<uint64_t, SmallVector<Writer, 1>> writersOf;
  // Every operation that observes a root's update events: waits, and the
  // other uses (level waits, `iff` conditions, clocking events).
  struct Watcher {
    Operation *function;
    uint64_t low, width;
    bool change; // a plain change wait (9.4.2), not an edge or level
  };
  DenseMap<uint64_t, SmallVector<Watcher, 1>> watchersOf;
  // Readers that wait on an expression sink: they must be quiet.
  SmallVector<std::pair<Summary *, Root>> expressionWaiters;
  DenseMap<std::pair<Operation *, unsigned>, bool> coveredFormals;
  auto coveredAtCalls = [&](sim::SimFuncOp function, unsigned formal) {
    auto key = std::make_pair(function.getOperation(), formal);
    auto found = coveredFormals.find(key);
    if (found != coveredFormals.end())
      return found->second;
    auto users = usersOf.find(function.getSymName());
    bool covered =
        function.isPrivate() && state.usesKnown &&
        (function.getEntryKind() == sim::EntryKind::Function ||
         function.getEntryKind() == sim::EntryKind::Task) &&
        users != usersOf.end() && !users->second.empty();
    if (covered)
      for (Operation *user : users->second) {
        auto caller = user->getParentOfType<sim::SimFuncOp>();
        if (!caller || !summaryOf.contains(caller)) {
          covered = false;
          break;
        }
        Value actual;
        if (auto call = dyn_cast<sim::SimCallOp>(user)) {
          if (call.getCallee() == function.getSymName() &&
              formal < call.getNumOperands())
            actual = call.getOperand(formal);
        } else if (auto call = dyn_cast<sim::SimTaskCallOp>(user)) {
          if (call.getCallee() == function.getSymName() &&
              formal < call.getArguments().size())
            actual = call.getArguments()[formal];
        }
        covered &= actual && isHandle(actual);
        // The call must account for every reference on this operation:
        // another attribute may expose the helper as more than a callee.
        unsigned references = 0;
        for (NamedAttribute named : user->getAttrs())
          named.getValue().walk([&](SymbolRefAttr reference) {
            if (reference.getRootReference().getValue() == function.getSymName())
              ++references;
          });
        covered &= references == 1;
      }
    coveredFormals[key] = covered;
    return covered;
  };
  for (Summary *summary : all) {
    Operation *function = summary->function;
    const Copy *asCopy = summary->copy ? &*summary->copy : nullptr;
    for (const UnboundedAccess &access : summary->unbounded) {
      // Direct calls and task calls conservatively read and write every
      // handle actual (forEachWrite). For a closed private helper, those
      // caller summaries already pin all possible formal targets and mark
      // their writers' publication shape unknown. Delegate only formal
      // origins: an opaque factory in the same body still needs fallback.
      if (access.formal &&
          coveredAtCalls(summary->function, *access.formal))
        continue;
      for (auto [root, type] : types) {
        if (root.net != access.net)
          continue;
        auto width = sim::getProvenanceSpan(type);
        if (!width)
          continue;
        if (access.write)
          writersOf[keyOf(root)].push_back(
              {access.op, function, 0, *width, access.nonblocking, true});
        else
          watchersOf[keyOf(root)].push_back({function, 0, *width, false});
        auto found = sinks.find(root);
        if (found != sinks.end())
          found->second.block("unknown handle origin");
      }
    }
    if (summary->timing)
      for (Root root : summary->captured) {
        auto found = sinks.find(root);
        if (found != sinks.end())
          found->second.block("timing construct");
      }
    auto hit = [&](const Access &access) -> Sink * {
      auto found = sinks.find(access.root);
      if (found == sinks.end())
        return nullptr;
      // Final procedures execute after termination (9.2.3, 20.2), when no
      // pending Active continuous assignment can run. A Reactive write just
      // before $finish, or a write in the final procedure itself, may leave
      // the materialized sink at its preceding value (4.4.2, 4.9.1). Reading
      // its RHS here would observe a value the assignment never published.
      if (summary->function.getEntryKind() == sim::EntryKind::Final)
        found->second.block("final observer");
      if (access.dynamic)
        found->second.block("dynamic access");
      return &found->second;
    };
    for (const Write &write : summary->writes) {
      writersOf[keyOf(write.root)].push_back({write.op, function, write.low,
                                              write.width, write.nonblocking,
                                              !write.plain});
      if (Sink *s = hit(write))
        if (!asCopy || !(asCopy->sink == s->root))
          s->block("other writer");
    }
    for (const Access &read : summary->reads) {
      if (Sink *s = hit(read)) {
        // Static initialization precedes continuous assignment activations
        // (6.8, 10.3.2); it must read the variable's original default value.
        // Helpers called by the initializer are also pinned by the existing
        // reader-not-spawned proof below.
        if (!s->root.net && summary->function.getEntryKind() ==
                                 sim::EntryKind::RootInitializer)
          s->block("storage read during initialization");
        ++s->readers;
        if (!summary->context)
          s->block("reader without context");
        readSites.push_back({read.op, s->root, read.low, read.width});
      }
    }
    for (const Wait &wait : summary->waits) {
      watchersOf[keyOf(wait.root)].push_back(
          {function, wait.low, wait.width,
           wait.edge == int32_t(sim::EdgeKind::Change)});
      Sink *s = hit(wait);
      if (!s)
        continue;
      if (!summary->context)
        s->block("waiter without context");
      bool expression = llvm::any_of(s->pieces, [](const Piece &piece) {
        return !piece.copy->relocation;
      });
      // A reader moved onto expression operands re-evaluates when the
      // expression keeps its value (9.4.2: such an operand change is no
      // event of the expression): only a combinational process can, an
      // explicit `@(y)` with effects observes y's own changes and so does an
      // edge on an expression.
      if (expression && !summary->combinational)
        s->block("wait on expression");
      else if (expression)
        expressionWaiters.push_back({summary, s->root});
      if (wait.edge != int32_t(sim::EdgeKind::Change))
        for (const Piece &piece : s->pieces)
          if (piece.low <= wait.low && wait.low < piece.low + piece.width &&
              !piece.copy->relocation)
            s->block("edge on expression");
      waitSites.push_back(
          {wait.op, wait.operand, s->root, wait.low, wait.width, wait.edge});
    }
    for (const DisplayItem &item : summary->displays)
      if (Sink *s = hit(item)) {
        if (item.strength || !summary->context) {
          s->block("display strength");
          continue;
        }
        displaySites.push_back(
            {item.op, item.operand, item.flag, s->root, item.low, item.width});
      }
    for (const Access &reference : summary->displayReferences)
      if (Sink *s = hit(reference))
        s->block("display reference");
    for (const Access &use : summary->uses) {
      watchersOf[keyOf(use.root)].push_back(
          {function, use.low, use.width, false});
      if (Sink *s = hit(use))
        s->block("use:" + use.op->getName().getStringRef().str());
    }
  }
  // Every copy must actually start. Its spawns must be plain (unused
  // result) and the only uses; an unstarted copy never publishes its RHS.
  for (const Copy *copy : copies) {
    sim::SimFuncOp copyFunction = copy->function;
    const auto users = usersOf.lookup(copyFunction.getSymName());
    bool plain = state.usesKnown && !users.empty();
    for (Operation *user : users) {
      auto spawn = getSpawnOf(user, copyFunction.getSymName());
      plain &= spawn && spawn->getResult(0).use_empty();
      if (!copy->sink.net && !state.startupSpawns.contains(user))
        sinks[copy->sink].block("storage copy not started unconditionally");
    }
    if (!plain)
      sinks[copy->sink].block("spawn use");
  }
  // Expression pieces are cloned per reader: bound the duplication.
  for (auto &[root, sink] : sinks) {
    if (sink.blocked)
      continue;
    unsigned cost = 0;
    for (const Piece &piece : sink.pieces)
      if (!piece.copy->relocation)
        cost += piece.copy->cost + piece.copy->reads.size();
    if (cost && cost * sink.readers > maximumClones)
      sink.block("clone budget");
  }
  // A process is a function every use of which is a spawn passing the
  // context first; anything else (a called function) activates with its
  // caller, an unknown number of times.
  auto isProcess = [&](Operation *function) {
    auto found = state.processOf.find(function);
    if (found != state.processOf.end())
      return found->second;
    auto func = cast<sim::SimFuncOp>(function);
    auto users = usersOf.find(func.getSymName());
    bool ok =
        state.usesKnown && users != usersOf.end() && !users->second.empty();
    if (ok)
      for (Operation *user : users->second)
        ok &= bool(getSpawnOf(user, func.getSymName())) &&
              user->getNumOperands() > 0 &&
              isa<sim::ContextType>(user->getOperand(0).getType());
    state.processOf[function] = ok;
    return ok;
  };
  auto writesOverlap = [&](Operation *function, Root root, uint64_t low,
                           uint64_t width) {
    return llvm::any_of(summaryOf.lookup(function)->writes,
                        [&](const Write &write) {
                          return write.root == root &&
                                 overlaps(write.low, write.width, low, width);
                        });
  };
  // Readers gain captures at their spawns: a function reached otherwise
  // keeps its sinks.
  {
    auto blockIn = [&](Operation *op, Root root) {
      if (!isProcess(op->getParentOfType<sim::SimFuncOp>()))
        sinks[root].block("reader not spawned");
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
        self |=
            writesOverlap(function, copy.reads[0].root,
                          copy.sourceLow + (begin - piece.low), end - begin);
      else
        for (const SourceRead &read : copy.reads)
          self |= writesOverlap(function, read.root, read.low, read.width);
    }
    if (self)
      sink.block("self-sensitive reader");
  }
  // Blocking stores publish within each activation (9.4.1-2). Immediate
  // NBAs issued across #0 or event waits can still commit in one NBA drain
  // (4.4.2.4): only a proven positive delay separates their issue windows.
  auto boundsFor =
      [&](Summary &summary,
          bool nonblocking) -> const analysis::WriteExecutionBounds & {
    auto &bounds = nonblocking ? summary.nbaBounds : summary.bounds;
    if (!bounds) {
      SmallVector<Operation *> tracked;
      for (const Write &write : summary.writes)
        tracked.push_back(write.op);
      bounds = std::make_unique<analysis::WriteExecutionBounds>(
          summary.function, tracked, /*unknownCallEffects=*/false,
          nonblocking ? analysis::ExecutionWindow::PositiveDelay
                      : analysis::ExecutionWindow::Activation);
    }
    return *bounds;
  };
  auto onceInWindow = [&](Summary &summary, Operation *a, Operation *b,
                          bool nonblocking) {
    const analysis::WriteExecutionBounds &bounds =
        boundsFor(summary, nonblocking);
    if (a == b)
      return bounds.executesAtMostOnce(a);
    return bounds.mutuallyExclusive(a, b);
  };
  // A copy can filter intermediate stores before its Active evaluation,
  // whereas a waiter moved onto the source observes every update event
  // (IEEE 1800-2023 4.3, 9.4.2). Both
  // agree when every writer stores each bit at most once within the
  // applicable publication window: no transient (default, then override)
  // value is published. Delayed or opaque writes have no such certificate.
  std::map<Root, bool> transientFreeOf;
  auto transientFree = [&](Root root) {
    auto found = transientFreeOf.find(root);
    if (found != transientFreeOf.end())
      return found->second;
    bool &result = transientFreeOf[root];
    result = true;
    auto writers = writersOf.find(keyOf(root));
    if (writers == writersOf.end())
      return result;
    bool blocking = false, nonblocking = false;
    for (const Writer &writer : writers->second) {
      (writer.nonblocking ? nonblocking : blocking) = true;
      if (writer.unknownShape || !isProcess(writer.function) ||
          !onceInWindow(*summaryOf.lookup(writer.function), writer.op,
                        writer.op, writer.nonblocking))
        result = false;
    }
    if (blocking && nonblocking)
      result = false;
    for (size_t i = 0; result && i < writers->second.size(); ++i) {
      const Writer &a = writers->second[i];
      for (size_t j = i + 1; result && j < writers->second.size(); ++j) {
        const Writer &b = writers->second[j];
        if (a.op == b.op || !overlaps(a.low, a.width, b.low, b.width))
          continue;
        // Two processes' nonblocking writes of one bit commit in the same
        // NBA region and may round-trip before any Active process runs.
        if (b.function != a.function)
          result = !(a.nonblocking && b.nonblocking);
        else
          result = onceInWindow(*summaryOf.lookup(a.function), a.op, b.op,
                                a.nonblocking);
      }
    }
    return result;
  };
  // A process stores each bit at most once per activation.
  auto storesOnce = [&](Summary &summary) {
    if (summary.storesOnce)
      return *summary.storesOnce;
    ArrayRef<Write> writes = summary.writes;
    bool once = true;
    for (size_t i = 0; once && i < writes.size(); ++i) {
      once = writes[i].plain &&
             onceInWindow(summary, writes[i].op, writes[i].op,
                          /*nonblocking=*/false);
      for (size_t j = i + 1; once && j < writes.size(); ++j)
        if (writes[i].op != writes[j].op && writes[i].root == writes[j].root &&
            overlaps(writes[i].low, writes[i].width, writes[j].low,
                     writes[j].width))
          once = onceInWindow(summary, writes[i].op, writes[j].op,
                              /*nonblocking=*/false);
    }
    summary.storesOnce = once;
    return once;
  };
  // A combinational process whose activation is a function of the inputs
  // it waits on: every bit it reads is either watched by its own change
  // waits (an always_comb waits on all it reads but its own outputs,
  // 9.2.2.2.1; a continuous assignment on its operands, 10.3.2) or a
  // variable bit it stored earlier on every path of the same activation (a
  // blocking assignment updates before the next statement, 10.4.1; a
  // nonblocking or net update arrives later, 4.9.1, 4.9.4, so those bits
  // must not be read at all). Woken again with unchanged inputs, it then
  // computes the values its previous activation stored. Function-local, so
  // it carries over with the summary.
  auto evaluatesOnInputs = [&](Summary &summary) {
    if (summary.evaluatesOnInputs)
      return *summary.evaluatesOnInputs;
    bool ok = summary.combinational && !summary.unknown &&
              !summary.otherSuspension && summary.uses.empty() &&
              summary.displays.empty() && summary.displayReferences.empty() &&
              llvm::all_of(summary.waits, [](const Wait &wait) {
                return wait.edge == int32_t(sim::EdgeKind::Change);
              });
    std::unique_ptr<analysis::MustDefinitionAnalysis> must;
    auto definition = [](const Write &write) {
      return isa<sim::SimRefStoreOp>(write.op) && write.plain &&
             !write.dynamic && !write.root.net;
    };
    for (const Access &read : summary.reads) {
      if (!ok)
        break;
      SmallVector<Interval> rest{{read.low, read.low + read.width}};
      SmallVector<Interval> own;
      for (const Write &write : summary.writes)
        if (write.root == read.root &&
            overlaps(write.low, write.width, read.low, read.width))
          own.push_back(
              {std::max(write.low, read.low),
               std::min(write.low + write.width, read.low + read.width)});
      for (Interval interval : own)
        subtract(rest, interval);
      if (!own.empty()) {
        if (read.root.net) {
          ok = false;
          break;
        }
        if (!must) {
          SmallVector<Operation *> definitions;
          for (const Write &write : summary.writes)
            if (definition(write))
              definitions.push_back(write.op);
          must = std::make_unique<analysis::MustDefinitionAnalysis>(
              summary.function, definitions,
              [](Operation *op) { return sim::isSuspensionOp(op); });
        }
        for (const Write &write : summary.writes)
          if (definition(write) && write.root == read.root &&
              must->containsBefore(write.op, read.op))
            subtract(own, {write.low, write.low + write.width});
        ok = own.empty();
      }
      for (const Wait &wait : summary.waits)
        if (wait.root == read.root)
          subtract(rest, {wait.low, wait.low + wait.width});
      ok &= rest.empty();
    }
    summary.evaluatesOnInputs = ok;
    return ok;
  };
  // A quiet process may run again at any time without a visible effect: it
  // evaluates on its inputs, nothing else writes its bits (always_comb
  // outputs are exclusive, 9.2.2.2; so are a continuous assignment's, 6.5),
  // so it stores the values they already hold, which is no update event
  // (4.3). Storing a bit twice still publishes a transient (`o = 0; if (y)
  // o = 1;` makes o 1 -> 0 -> 1), which its own waiters then must ignore.
  // Least fixed point: a cycle of such processes may never settle once each
  // wakes the next, so it is not quiet.
  enum class Visit : uint8_t { Active, Quiet, Loud };
  DenseMap<Operation *, Visit> quietOf, transparentOf;
  std::function<bool(Summary &)> quiet;
  std::function<bool(Root, uint64_t, uint64_t)> transientsInvisible;
  quiet = [&](Summary &summary) {
    auto [found, inserted] =
        quietOf.try_emplace(summary.function, Visit::Active);
    if (!inserted)
      return found->second == Visit::Quiet;
    bool result = evaluatesOnInputs(summary);
    for (const Write &write : summary.writes)
      for (const Writer &writer : writersOf.lookup(keyOf(write.root)))
        result &= writer.function == summary.function.getOperation() ||
                  !overlaps(writer.low, writer.width, write.low, write.width);
    if (result && !storesOnce(summary))
      for (const Write &write : summary.writes)
        result =
            result && transientsInvisible(write.root, write.low, write.width);
    quietOf[summary.function] = result ? Visit::Quiet : Visit::Loud;
    return result;
  };
  // A transient of these bits wakes their change waiters (4.3, 9.4.2), each
  // of which must be quiet. Activations may run atomically (4.7), so a
  // reader waiting on another signal cannot sample an extra activation's
  // intermediate stores. Nothing else may watch them: an edge, a level
  // wait (9.4.3) or an `iff` condition sees the intermediate value, and so
  // do VPI, toggle coverage and waveform dumps. A copy filters transients
  // only while it exists: once forwarded, its waiters watch these bits, so a
  // copy passes them on to the waiters of its own sink.
  transientsInvisible = [&](Root root, uint64_t low, uint64_t width) {
    if (state.waveforms || state.observed.contains(keyOf(root)))
      return false;
    for (const Watcher &watcher : watchersOf.lookup(keyOf(root))) {
      if (!overlaps(watcher.low, watcher.width, low, width))
        continue;
      if (!watcher.change)
        return false;
      Summary &summary = *summaryOf.lookup(watcher.function);
      if (!summary.copy) {
        if (!quiet(summary))
          return false;
        continue;
      }
      auto [found, inserted] =
          transparentOf.try_emplace(watcher.function, Visit::Active);
      if (inserted) {
        bool passes = transientsInvisible(
            summary.copy->sink, summary.copy->sinkLow, summary.copy->width);
        transparentOf[watcher.function] = passes ? Visit::Quiet : Visit::Loud;
      }
      if (transparentOf[watcher.function] != Visit::Quiet)
        return false;
    }
    return true;
  };
  // Waiters on a sink whose source publishes transients would see them once
  // moved onto the source.
  for (auto &[root, sink] : sinks) {
    if (sink.blocked)
      continue;
    bool free = llvm::all_of(sink.pieces, [&](const Piece &piece) {
      return llvm::all_of(piece.copy->reads, [&](const SourceRead &read) {
        return transientFree(read.root);
      });
    });
    if (!free && !transientsInvisible(root, 0, sink.width))
      sink.block("transient source");
  }
  // A reader moved onto expression operands also wakes when the expression
  // keeps its value; it must be quiet.
  for (auto [summary, root] : expressionWaiters) {
    Sink &sink = sinks[root];
    if (!sink.blocked && !quiet(*summary))
      sink.block("wait on expression");
  }
  // IEEE 1800-2023 4.5: the Reactive region set (program processes, 24.3,
  // and anything they call or spawn) drains before the Active set resumes.
  // A copy made pending by a Reactive writer of its source therefore runs
  // only after every Reactive reader of the net; such a reader must keep
  // the net. Readers in the Active set and writers there are unaffected:
  // Active events may run in any order (4.7) and the Reactive set starts
  // only after every Active copy ran.
  if (!state.nonActive.empty()) {
    auto resumesOutsideActive = [](Operation *wait) {
      std::optional<sim::EventRegion> region;
      if (auto any = dyn_cast<sim::SimSuspendAnyOp>(wait))
        region = any.getResumeRegion();
      else if (auto change = dyn_cast<sim::SimSuspendChangeOp>(wait))
        region = change.getResumeRegion();
      else if (auto edge = dyn_cast<sim::SimSuspendEdgeOp>(wait))
        region = edge.getResumeRegion();
      return region && *region != sim::EventRegion::Active;
    };
    std::set<Root> reactiveReaders;
    auto noteReader = [&](Operation *op, Root sink) {
      if (state.nonActive.contains(op->getParentOfType<sim::SimFuncOp>()))
        reactiveReaders.insert(sink);
    };
    for (const ReadSite &site : readSites)
      noteReader(site.op, site.sink);
    for (const DisplaySite &site : displaySites)
      noteReader(site.op, site.sink);
    for (const WaitSite &site : waitSites) {
      noteReader(site.op, site.sink);
      if (resumesOutsideActive(site.op))
        reactiveReaders.insert(site.sink);
    }
    for (const Root &root : reactiveReaders) {
      Sink &sink = sinks[root];
      for (const Piece &piece : sink.pieces)
        for (const SourceRead &read : piece.copy->reads)
          if (llvm::any_of(writersOf.lookup(keyOf(read.root)),
                           [&](const Writer &writer) {
                             return state.nonActive.contains(writer.function);
                           }))
            sink.block("reactive reader");
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

  // Functions this round edits; their summaries are solved again next round.
  DenseSet<Operation *> edited;
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
    Type handleType = root.net ? Type(sim::NetType::get(context, element))
                               : Type(sim::RefType::get(context, element));
    OpBuilder attrs(context);
    DictionaryAttr captureAttrs = attrs.getDictionaryAttr(
        {attrs.getNamedAttr(sim::metadata::CaptureKind::getNameStr(),
                            attrs.getI32IntegerAttr(
                                root.net ? int32_t(sim::CaptureKind::Net)
                                         : int32_t(sim::CaptureKind::Storage))),
         attrs.getNamedAttr(sim::metadata::DescriptorId::getNameStr(),
                            attrs.getI64IntegerAttr(root.id))});
    // A function type always admits one more input.
    LogicalResult inserted = func.insertArgument(entry.getNumArguments(),
                                                 handleType, captureAttrs, loc);
    assert(succeeded(inserted) && "sim.func rejected a new capture");
    (void)inserted;
    // A spawn's parent keeps its summary: summaries record neither spawns
    // nor the views that bind captures.
    edited.insert(function);
    for (Operation *user : usersOf.lookup(func.getSymName())) {
      auto spawn = getSpawnOf(user, func.getSymName());
      assert(spawn && "rewritten reader must be used by its own spawns");
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
    // Undeclared or non-packed sources and context-less readers were
    // blocked above.
    assert(types.count(root) && contextOf(function) &&
           "forward-copies: view of an unchecked root");
    Value handle = handleFor(builder, loc, function, root);
    Type element = types[root];
    Type scalar = sim::getPackedScalarType(element);
    Type vector = vectorTypeLike(context, scalar, unsigned(width));
    if (low == 0 && *sim::getPackedWidth(element) == width && element == vector)
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
    Type scalar = sim::getPackedScalarType(v.getType());
    assert(scalar && "copy values must be packed");
    if (v.getType() == scalar)
      return v;
    return sim::SimPackedFlattenOp::create(builder, loc, scalar, v);
  };
  auto adapt = [&](OpBuilder &builder, Location loc, Value v,
                   Type target) -> Value {
    if (v.getType() == target)
      return v;
    v = flatten(builder, loc, v);
    Type scalar = sim::getPackedScalarType(target);
    assert(scalar && "copy reader values must be packed");
    if (v.getType() != scalar) {
      if (isa<sim::LogicType>(scalar))
        v = sim::SimLogicFromBitsOp::create(builder, loc, scalar, v);
      else
        v = sim::SimLogicToBitsOp::create(builder, loc, scalar, v);
    }
    if (target == scalar)
      return v;
    return sim::SimPackedUnflattenOp::create(builder, loc, target, v);
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
        mapping.map(entry.getArgument(i), contextOf(function));
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
    Value value = mapping.lookup(copyValue(copy.write));
    assert(value && "expression value must be cloned");
    if (low == piece.low && width == piece.width)
      return value;
    value = flatten(builder, loc, value);
    if (isa<sim::LogicType>(value.getType()))
      return sim::SimLogicExtractOp::create(
          builder, loc, sim::LogicType::get(context, unsigned(width)), value,
          low - piece.low);
    Type bits = builder.getIntegerType(unsigned(width));
    if (low != piece.low) {
      Value shift = arith::ConstantOp::create(
          builder, loc, value.getType(),
          builder.getIntegerAttr(value.getType(), low - piece.low));
      value = arith::ShRUIOp::create(builder, loc, value, shift);
    }
    if (value.getType() != bits)
      value = arith::TruncIOp::create(builder, loc, bits, value);
    return value;
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
          views.push_back(
              viewOf(builder, loc, function, read.root, read.low, read.width));
      }
    }
  };
  unsigned eliminated = 0, rewrittenReads = 0, rewrittenWaits = 0;
  for (const ReadSite &site : readSites) {
    if (!ready.count(site.sink))
      continue;
    const Sink &sink = sinks[site.sink];
    OpBuilder builder(site.op);
    Value value = sinkValue(
        builder, site.op->getLoc(), site.op->getParentOfType<sim::SimFuncOp>(),
        sink, site.low, site.width, site.op->getResult(0).getType());
    site.op->getResult(0).replaceAllUsesWith(value);
    edited.insert(site.op->getParentOfType<sim::SimFuncOp>());
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
    edited.insert(display->getParentOfType<sim::SimFuncOp>());
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
    edited.insert(function);
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
          continuation,
          cast<sim::SimSuspendEdgeOp>(op).getContinuationOperands());
    if (operands.size() == 1 && !isa<sim::SimSuspendAnyOp>(op)) {
      op->setOperand(0, operands.front());
    } else {
      llvm::append_range(operands, continuation);
      schedule::ContinuationSiteAttr site;
      sim::EventRegionAttr resume;
      if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(op)) {
        site = wait.getSiteAttr();
        resume = wait.getResumeRegionAttr();
      } else if (auto wait = dyn_cast<sim::SimSuspendChangeOp>(op)) {
        site = wait.getSiteAttr();
        resume = wait.getResumeRegionAttr();
      } else {
        auto edge = cast<sim::SimSuspendEdgeOp>(op);
        site = edge.getSiteAttr();
        resume = edge.getResumeRegionAttr();
      }
      auto any = sim::SimSuspendAnyOp::create(
          builder, loc, operands, edges, site, resume, op->getSuccessor(0));
      // Carry the wait's discardable attributes; its inherent ones (edge,
      // site, resume region) were rebuilt above.
      ArrayRef<StringAttr> inherent = op->getName().getAttributeNames();
      for (NamedAttribute attr : op->getAttrs())
        if (!llvm::is_contained(inherent, attr.getName()))
          any->setAttr(attr.getName(), attr.getValue());
      op->erase();
    }
    ++rewrittenWaits;
  }
  // The copies are dead: erase their spawns and bodies.
  SmallVector<sim::SimFuncOp> dead;
  for (const Copy *copy : copies) {
    if (!ready.count(copy->sink))
      continue;
    sim::SimFuncOp function = copy->function;
    for (Operation *user : usersOf.lookup(function.getSymName())) {
      auto spawn = getSpawnOf(user, function.getSymName());
      assert(spawn && "eliminated copy must be used by its own spawns");
      spawn.erase();
    }
    usersOf.erase(function.getSymName());
    state.processOf.erase(function);
    dead.push_back(function);
    ++eliminated;
  }
  // Summaries of edited functions name erased operations; a dead copy's
  // summary owns its Copy record, so it goes last.
  for (Operation *function : edited)
    state.summaries.erase(function);
  for (sim::SimFuncOp function : dead) {
    state.summaries.erase(function);
    function.erase();
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
  Block &designBlock = design.getBody().front();
  DesignState state;
  state.analysis = std::make_unique<analysis::HandleDataflowAnalysis>(design);
  for (auto decl : designBlock.getOps<sim::SimNetDeclOp>()) {
    Root root{true, uint64_t(decl.getId())};
    state.types[root] = decl.getType();
    state.nets.push_back(decl);
    if (decl.getLifetime() == sim::Lifetime::Design)
      state.permanent.insert(keyOf(root));
    std::optional<schedule::ComputeObservabilityKind> observed =
        decl.getObservability();
    if ((observed &&
         *observed != schedule::ComputeObservabilityKind::Invisible) ||
        cov::has<cov::ToggleObservable>(decl))
      state.observed.insert(keyOf(root));
  }
  for (auto decl : designBlock.getOps<sim::SimStorageDeclOp>()) {
    Root root{false, uint64_t(decl.getId())};
    state.types[root] = decl.getType();
    if (decl.getLifetime() == sim::Lifetime::Design)
      state.permanent.insert(keyOf(root));
    std::optional<schedule::ComputeObservabilityKind> observed =
        decl.getObservability();
    if ((observed &&
         *observed != schedule::ComputeObservabilityKind::Invisible) ||
        cov::has<cov::ToggleObservable>(decl))
      state.observed.insert(keyOf(root));
  }
  state.topology = analysis::getIsolatedWireDriverTopology(design);
  // Function bodies are summarized per round; the rest of the design is
  // fixed.
  design.walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (isa<sim::SimFuncOp>(op))
      return WalkResult::skip();
    if (isa<sim::SimDumpVarsOp, sim::SimDumpAllOp, sim::SimDumpControlOp,
            sim::SimDumpPortsOp, sim::SimDumpPortsControlOp>(op))
      state.waveforms = true;
    if (isa<sim::SimNetDeclOp, sim::SimStorageDeclOp, sim::SimPortDeclOp,
            sim::SimVPINetIdentityDeclOp>(op))
      return WalkResult::advance();
    for (NamedAttribute attr : op->getAttrs())
      if (attr.getName().getValue().ends_with("net_id"))
        if (auto id = dyn_cast<IntegerAttr>(attr.getValue())) {
          if (isa<sim::SimDriverDeclOp>(op))
            ++state.driverDecls[id.getValue().getZExtValue()];
          else
            state.namedNets.push_back(
                {op->getName().getStringRef(), id.getValue().getZExtValue()});
        }
    return WalkResult::advance();
  });
  for (auto function : designBlock.getOps<sim::SimFuncOp>())
    if (!function.isExternal())
      state.waveforms |=
          function
              .walk([](Operation *op) {
                return isa<sim::SimDumpVarsOp, sim::SimDumpAllOp,
                           sim::SimDumpControlOp, sim::SimDumpPortsOp,
                           sim::SimDumpPortsControlOp>(op)
                           ? WalkResult::interrupt()
                           : WalkResult::advance();
              })
              .wasInterrupted();
  // Normalize before indexing symbol users: even a branch can carry a
  // discardable symbol reference, and normalization can erase that branch.
  // Census mode uses the same normalized shapes, then restores the bodies so
  // it remains a read-only inventory. Function signatures and attributes
  // remain unchanged; all inventories of body operations are local below.
  SmallVector<std::pair<sim::SimFuncOp, OwningOpRef<Operation *>>> originals;
  for (auto function : designBlock.getOps<sim::SimFuncOp>()) {
    if (function.isExternal() || function.getBody().getBlocks().size() <= 2 ||
        (function.getEntryKind() != sim::EntryKind::Continuous &&
         function.getEntryKind() != sim::EntryKind::PortInput &&
         function.getEntryKind() != sim::EntryKind::PortOutput))
      continue;
    OwningOpRef<Operation *> original;
    if (census)
      original = function->clone();
    if (normalizePureExpression(function, state.analysis->derive(function),
                                state, maximumClones) &&
        census)
      originals.emplace_back(function, std::move(original));
  }
  indexSymbolUsers(design, state);
  // Variables retain their declaration default until their continuous
  // assignment starts. Only a once-only unconditional startup spawn lets a
  // substituted reader choose that assignment's first Active evaluation.
  // Root initialization may contain loops elsewhere: a block outside every
  // cyclic CFG component executes at most once. This structural proof avoids
  // building a dense per-statement counting lattice for all startup spawns.
  for (auto function : designBlock.getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        function.getEntryKind() != sim::EntryKind::RootInitializer ||
        function
            .walk([](Operation *op) {
              return sim::isSuspensionOp(op) ? WalkResult::interrupt()
                                             : WalkResult::advance();
            })
            .wasInterrupted())
      continue;
    SmallVector<Operation *> spawns, exits;
    function.walk([&](sim::SimSpawnOp spawn) {
      if (spawn->getParentRegion() == &function.getBody())
        spawns.push_back(spawn);
    });
    for (Block &block : function.getBody())
      if (block.getNumSuccessors() == 0)
        exits.push_back(block.getTerminator());
    if (spawns.empty() || exits.empty())
      continue;
    if (llvm::any_of(state.usersOf.lookup(function.getSymName()),
                     [](Operation *user) {
                       return isa<sim::SimCallOp, sim::SimTaskCallOp,
                                  sim::SimSpawnOp>(user);
                     }))
      continue;
    DominanceInfo dominance(function);
    DenseSet<Block *> cyclic;
    for (auto component = llvm::scc_begin(&function.getBody().front());
         !component.isAtEnd(); ++component)
      if (component.hasCycle())
        cyclic.insert(component->begin(), component->end());
    for (Operation *spawn : spawns)
      if (!cyclic.contains(spawn->getBlock()) &&
          llvm::all_of(exits, [&](Operation *exit) {
            return dominance.dominates(spawn, exit);
          }))
        state.startupSpawns.insert(spawn);
  }
  // IEEE 1800-2023 4.5: the Reactive region set (program processes, 24.3,
  // and anything they call or spawn).
  {
    llvm::StringMap<Operation *> functions;
    for (auto function : designBlock.getOps<sim::SimFuncOp>())
      functions[function.getSymName()] = function;
    DenseMap<Operation *, SmallVector<Operation *>> calleesOf;
    for (const auto &entry : state.usersOf) {
      Operation *callee = functions.lookup(entry.getKey());
      if (!callee)
        continue;
      for (Operation *user : entry.getValue())
        if (auto caller = user->getParentOfType<sim::SimFuncOp>())
          calleesOf[caller].push_back(callee);
    }
    SmallVector<Operation *> work;
    for (auto function : designBlock.getOps<sim::SimFuncOp>())
      if (!function.isExternal() &&
          function.getHomeRegion() != sim::EventRegion::Active)
        work.push_back(function);
    while (!work.empty()) {
      Operation *function = work.pop_back_val();
      if (state.nonActive.insert(function).second)
        llvm::append_range(work, calleesOf.lookup(function));
    }
  }
  for (unsigned r = 0; r < maximumRounds; ++r) {
    if (r)
      indexSymbolUsers(design, state);
    if (!round(design, state, r + 1 == maximumRounds))
      break;
  }
  for (auto &[function, original] : originals)
    function.getBody().takeBody(cast<sim::SimFuncOp>(*original).getBody());
}

} // namespace
} // namespace talos
