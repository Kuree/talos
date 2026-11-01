//===- OrderedDenseAnalysisTest.cpp - Dense visits in CFG order -----------===//
//
// A dense forward analysis reaches the same fixpoint at every program point
// whether the solver's first-in, first-out worklist or reverse post-order picks
// its visits, and reverse post-order visits an acyclic body's operations once.
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/OrderedDenseAnalysis.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Parser/Parser.h"


#include "gtest/gtest.h"

#include <set>
#include <string>
#include <vector>

using namespace mlir;

namespace {

/// The constants a path may have passed.
class SeenLattice final : public dataflow::AbstractDenseLattice {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SeenLattice)
  using AbstractDenseLattice::AbstractDenseLattice;
  ChangeResult join(const AbstractDenseLattice &rhs) override {
    const auto &other = static_cast<const SeenLattice &>(rhs);
    bool changed = !reachable && other.reachable;
    reachable |= other.reachable;
    for (int64_t value : other.seen)
      changed |= seen.insert(value).second;
    return changed ? ChangeResult::Change : ChangeResult::NoChange;
  }
  void print(raw_ostream &os) const override { os << seen.size(); }
  bool reachable = false;
  std::set<int64_t> seen;
};

template <typename Base> class SeenAnalysis final : public Base {
public:
  SeenAnalysis(DataFlowSolver &solver, uint64_t &visits)
      : Base(solver), visits(visits) {}
  LogicalResult visitOperation(Operation *op, const SeenLattice &before,
                               SeenLattice *after) override {
    ++visits;
    ChangeResult changed = after->join(before);
    if (auto constant = dyn_cast<arith::ConstantIntOp>(op))
      if (after->seen.insert(constant.value()).second)
        changed = ChangeResult::Change;
    this->propagateIfChanged(after, changed);
    return success();
  }

private:
  void setToEntryState(SeenLattice *state) override {
    bool wasReachable = state->reachable;
    state->reachable = true;
    this->propagateIfChanged(state, wasReachable ? ChangeResult::NoChange
                                                 : ChangeResult::Change);
  }
  uint64_t &visits;
};

using Fifo = dataflow::DenseForwardDataFlowAnalysis<SeenLattice>;
using Ordered =
    talos::analysis::OrderedDenseForwardDataFlowAnalysis<SeenLattice>;

template <typename Base>
std::vector<std::set<int64_t>> solve(func::FuncOp function, uint64_t &visits) {
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
  solver.load<dataflow::DeadCodeAnalysis>();
  solver.load<dataflow::SparseConstantPropagation>();
  solver.load<SeenAnalysis<Base>>(visits);
  EXPECT_TRUE(succeeded(solver.initializeAndRun(function)));
  std::vector<std::set<int64_t>> states;
  function.walk([&](Operation *op) {
    if (op == function)
      return;
    const auto *state =
        solver.lookupState<SeenLattice>(solver.getProgramPointAfter(op));
    states.push_back(state ? state->seen : std::set<int64_t>{});
  });
  return states;
}

/// `count` if/then triangles in a row whose then-arm is a chain of `index % 7`
/// blocks more than one, so that updates arrive at each join several worklist
/// generations apart, optionally with a back edge from the last join to the
/// middle one.
std::string buildBody(unsigned count, bool loop, unsigned &operations) {
  std::string body = "func.func @body(%c: i1) {\n  cf.br ^j0\n";
  operations = 1;
  for (unsigned index = 0; index != count; ++index) {
    std::string id = std::to_string(index), next = std::to_string(index + 1);
    body += "^j" + id + ":\n";
    body += "  %v" + id + " = arith.constant " +
            std::to_string(100000 + index) + " : i32\n";
    body += "  cf.cond_br %c, ^a" + id + "_0, ^j" + next + "\n";
    operations += 2;
    unsigned length = 1 + index % 7;
    for (unsigned arm = 0; arm != length; ++arm) {
      std::string suffix = id + "_" + std::to_string(arm);
      body += "^a" + suffix + ":\n";
      body += "  %a" + suffix + " = arith.constant " +
              std::to_string(index * 10 + arm) + " : i32\n";
      body += "  cf.br ";
      body += arm + 1 == length
                  ? "^j" + next + "\n"
                  : "^a" + id + "_" + std::to_string(arm + 1) + "\n";
      operations += 2;
    }
  }
  body += "^j" + std::to_string(count) + ":\n";
  if (loop)
    body +=
        "  cf.cond_br %c, ^j" + std::to_string(count / 2) + ", ^exit\n^exit:\n";
  body += "  return\n}\n";
  operations += loop ? 2 : 1;
  return body;
}

class OrderedDenseAnalysisTest : public testing::Test {
protected:
  OrderedDenseAnalysisTest() {
    context.loadDialect<arith::ArithDialect, cf::ControlFlowDialect,
                        func::FuncDialect>();
  }
  MLIRContext context;
};

TEST_F(OrderedDenseAnalysisTest, AcyclicBodyVisitsEachOperationOnce) {
  unsigned operations = 0;
  std::string body = buildBody(200, /*loop=*/false, operations);
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(body, &context);
  ASSERT_TRUE(module);
  auto function = *module->getOps<func::FuncOp>().begin();
  uint64_t fifoVisits = 0, orderedVisits = 0;
  auto fifo = solve<Fifo>(function, fifoVisits);
  auto ordered = solve<Ordered>(function, orderedVisits);
  EXPECT_EQ(ordered, fifo);
  EXPECT_EQ(orderedVisits, operations);
  // The waves this order exists to avoid.
  EXPECT_GT(fifoVisits, 4 * orderedVisits);
}

TEST_F(OrderedDenseAnalysisTest, LoopReachesTheSameFixpoint) {
  unsigned operations = 0;
  std::string body = buildBody(100, /*loop=*/true, operations);
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(body, &context);
  ASSERT_TRUE(module);
  auto function = *module->getOps<func::FuncOp>().begin();
  uint64_t fifoVisits = 0, orderedVisits = 0;
  auto fifo = solve<Fifo>(function, fifoVisits);
  auto ordered = solve<Ordered>(function, orderedVisits);
  EXPECT_EQ(ordered, fifo);
  EXPECT_LT(orderedVisits, fifoVisits);
}

TEST_F(OrderedDenseAnalysisTest, DeadArmStaysUnvisited) {
  unsigned operations = 0;
  std::string body = buildBody(40, /*loop=*/false, operations);
  // A constant condition leaves every then-arm dead.
  size_t header = body.find("func.func @body(%c: i1) {\n");
  ASSERT_NE(header, std::string::npos);
  body.replace(header, 26,
               "func.func @body() {\n  %c = arith.constant false\n");
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(body, &context);
  ASSERT_TRUE(module);
  auto function = *module->getOps<func::FuncOp>().begin();
  uint64_t fifoVisits = 0, orderedVisits = 0;
  auto fifo = solve<Fifo>(function, fifoVisits);
  auto ordered = solve<Ordered>(function, orderedVisits);
  EXPECT_EQ(ordered, fifo);
  EXPECT_EQ(orderedVisits, fifoVisits);
}

} // namespace
