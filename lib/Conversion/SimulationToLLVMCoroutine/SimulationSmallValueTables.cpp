//===- SimulationSmallValueTables.cpp - Finite native value functions -----===//

#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Conversion/Passes.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/SaveAndRestore.h"
#include "llvm/Transforms/Utils/Evaluator.h"

using namespace mlir;

namespace talos::detail {
namespace {

constexpr unsigned minCost = 64, maxCost = 2048;

// Lowered logic results often start with a poison aggregate and insert every
// physical field. No undefined field may reach a return, branch or consumer.
bool overwrittenSeed(Value seed) {
  auto type = dyn_cast<LLVM::LLVMStructType>(seed.getType());
  if (!type || type.isOpaque() || type.getBody().empty() ||
      type.getBody().size() > 8)
    return false;
  unsigned all = (1u << type.getBody().size()) - 1;
  SmallVector<std::pair<Value, unsigned>> work{{seed, 0}};
  unsigned visited = 0;
  while (!work.empty()) {
    auto [value, initialized] = work.pop_back_val();
    if (++visited > 64)
      return false;
    for (OpOperand &use : value.getUses()) {
      if (auto extract = dyn_cast<LLVM::ExtractValueOp>(use.getOwner())) {
        auto pos = extract.getPosition();
        if (pos.size() == 1 && uint64_t(pos.front()) < type.getBody().size() &&
            (initialized & (1u << pos.front())))
          continue;
      }
      auto insert = dyn_cast<LLVM::InsertValueOp>(use.getOwner());
      if (!insert || use.getOperandNumber() != 0 ||
          insert.getPosition().size() != 1 ||
          uint64_t(insert.getPosition().front()) >= type.getBody().size())
        return false;
      unsigned next = initialized | (1u << insert.getPosition().front());
      if (next != all)
        work.emplace_back(insert.getResult(), next);
    }
  }
  return true;
}

bool numericType(Type type) {
  auto boundedInteger = [](Type field) {
    auto integer = dyn_cast<IntegerType>(field);
    return integer && integer.getWidth() <= 512;
  };
  if (boundedInteger(type))
    return true;
  auto tuple = dyn_cast<LLVM::LLVMStructType>(type);
  return tuple && !tuple.isOpaque() && !tuple.getBody().empty() &&
         tuple.getBody().size() <= 8 &&
         llvm::all_of(tuple.getBody(), boundedInteger);
}

struct Computation {
  unsigned cost = 0;
  SmallVector<LLVM::LLVMFuncOp> callees;
};

// The evaluation copy contains only closed acyclic integer computations.
// Context pointers may be forwarded into a direct callee, but no instruction
// may inspect them. A global load, an allocation, or a runtime call rules out
// the complete caller, including on rarely taken paths.
class ValueClosures {
public:
  explicit ValueClosures(ModuleOp module) : symbols(module) {}

  const Computation &get(LLVM::LLVMFuncOp f) {
    auto [it, inserted] = info.try_emplace(f);
    if (!inserted)
      return it->second;
    Computation result;
    if (!f.isExternal() && !f.getFunctionType().isVarArg() &&
        !f.getInstrumentFunctionEntryAttr() && !f.getInstrumentFunctionExitAttr() &&
        (f.isPrivate() || f.getLinkage() == LLVM::Linkage::Internal) &&
        numericType(f.getFunctionType().getReturnType()) && analyze(f, result))
      info[f] = std::move(result);
    return info.find(f)->second;
  }

private:
  bool analyze(LLVM::LLVMFuncOp f, Computation &result) {
    // The cost limit bounds the final graph. Also bound the call stack while
    // establishing that cost for a previously unseen chain of callees.
    if (activeDepth >= 64)
      return false;
    llvm::SaveAndRestore<unsigned> depth(activeDepth, activeDepth + 1);
    for (auto scc = llvm::scc_begin(&f.getBody().front()); !scc.isAtEnd();
         ++scc)
      if (scc.hasCycle())
        return false;
    for (Block &block : f.getBody())
      for (Operation &op : block) {
        if (++result.cost > maxCost)
          return false;
        if (isa<LLVM::BrOp, LLVM::CondBrOp, LLVM::ReturnOp, cf::BranchOp,
                cf::CondBranchOp>(op))
          continue;
        if (auto call = dyn_cast<LLVM::CallOp>(op)) {
          auto callee =
              call.getCallee()
                  ? symbols.lookup<LLVM::LLVMFuncOp>(*call.getCallee())
                  : LLVM::LLVMFuncOp{};
          if (!callee ||
              call.getArgOperands().size() != call.getNumOperands() ||
              call.getArgOperands().size() != callee.getNumArguments())
            return false;
          unsigned cost = get(callee).cost;
          if (!cost || cost > maxCost - result.cost)
            return false;
          result.cost += cost;
          result.callees.push_back(callee);
          continue;
        }
        if (isa<LLVM::UndefOp, LLVM::PoisonOp>(op)) {
          if (!overwrittenSeed(op.getResult(0)))
            return false;
          continue;
        }
        if (!isa<LLVM::ConstantOp, LLVM::ZeroOp, LLVM::AndOp, LLVM::OrOp,
                 LLVM::XOrOp, LLVM::AddOp, LLVM::SubOp, LLVM::MulOp,
                 LLVM::ShlOp, LLVM::LShrOp, LLVM::AShrOp, LLVM::ICmpOp,
                 LLVM::SelectOp, LLVM::TruncOp, LLVM::ZExtOp, LLVM::SExtOp,
                 LLVM::InsertValueOp, LLVM::ExtractValueOp, arith::ConstantOp,
                 arith::AndIOp, arith::OrIOp, arith::XOrIOp, arith::AddIOp,
                 arith::SubIOp, arith::MulIOp, arith::ShLIOp, arith::ShRUIOp,
                 arith::ShRSIOp, arith::CmpIOp, arith::SelectOp,
                 arith::TruncIOp, arith::ExtUIOp, arith::ExtSIOp>(op) ||
            !llvm::all_of(op.getOperandTypes(), numericType) ||
            !llvm::all_of(op.getResultTypes(), numericType))
          return false;
      }
    return true;
  }

  SymbolTable symbols;
  DenseMap<Operation *, Computation> info;
  unsigned activeDepth = 0;
};

struct Domain {
  LLVM::LLVMFuncOp function;
  SmallVector<unsigned, 2> keys;
  SmallVector<IntegerType, 3> fields;
  unsigned rows;
  unsigned cost;
};

std::optional<Domain> domainFor(LLVM::LLVMFuncOp f, ValueClosures &closures) {
  auto kind = native::get<native::EntryKind>(f);
  if (f.isExternal() || !kind ||
      kind.getInt() != static_cast<unsigned>(sim::EntryKind::Function))
    return std::nullopt;
  Domain d{f, {}, {}, 0, 0};
  for (auto [index, arg] :
       llvm::enumerate(f.getBody().front().getArguments())) {
    if (isa<LLVM::LLVMPointerType>(arg.getType()))
      continue;
    if (!numericType(arg.getType()))
      return std::nullopt;
    if (arg.use_empty())
      continue;
    auto type = dyn_cast<IntegerType>(arg.getType());
    if (!type || type.getWidth() > 8 || d.keys.size() == 2)
      return std::nullopt;
    if (d.keys.empty())
      d.rows = 1u << type.getWidth();
    d.keys.push_back(index);
  }
  if (d.keys.empty())
    return std::nullopt;
  Type type = f.getFunctionType().getReturnType();
  if (auto integer = dyn_cast<IntegerType>(type))
    d.fields.push_back(integer);
  else if (auto tuple = dyn_cast<LLVM::LLVMStructType>(type);
           tuple && !tuple.isOpaque() && tuple.getBody().size() <= 3) {
    for (Type element : tuple.getBody()) {
      auto field = dyn_cast<IntegerType>(element);
      if (!field)
        return std::nullopt;
      d.fields.push_back(field);
    }
  }
  if (d.fields.empty() || llvm::any_of(d.fields, [](IntegerType field) {
        return field.getWidth() > 64;
      }))
    return std::nullopt;
  d.cost = closures.get(f).cost;
  return d.cost >= minCost ? std::optional(d) : std::nullopt;
}

using Columns = SmallVector<SmallVector<APInt>, 3>;
std::optional<Columns> evaluate(const Domain &d, llvm::Function &f) {
  Columns columns(d.fields.size());
  SmallVector<llvm::Constant *> inputs;
  for (auto &arg : f.args())
    inputs.push_back(llvm::Constant::getNullValue(arg.getType()));
  for (unsigned i = 0; i < d.rows; ++i) {
    unsigned primary = d.keys.front();
    inputs[primary] = llvm::ConstantInt::get(f.getArg(primary)->getType(), i);
    llvm::Evaluator evaluator(f.getParent()->getDataLayout(), nullptr);
    llvm::Constant *result = nullptr;
    if (!evaluator.EvaluateFunction(&f, result, inputs) || !result)
      return std::nullopt;
    for (unsigned j = 0; j < columns.size(); ++j) {
      auto *field = llvm::dyn_cast_or_null<llvm::ConstantInt>(
          result->getType()->isStructTy() ? result->getAggregateElement(j)
                                          : result);
      if (!field)
        return std::nullopt;
      columns[j].push_back(field->getValue());
    }
  }
  return columns;
}

void emitTable(ModuleOp module, SymbolTable &symbols, Domain &d,
               const Columns &columns) {
  auto f = d.function;
  auto loc = f.getLoc();
  OpBuilder b(module.getContext());
  Block *original = &f.getBody().front();
  Block *entry = new Block;
  f.getBody().push_front(entry);
  for (auto arg : original->getArguments())
    entry->addArgument(arg.getType(), arg.getLoc());
  b.setInsertionPointToStart(entry);
  SmallVector<Value> args(entry->getArguments());
  for (unsigned key : d.keys)
    args[key] = LLVM::FreezeOp::create(b, loc, args[key]);
  Value index = LLVM::ZExtOp::create(b, loc, b.getI64Type(), args[d.keys[0]]);
  if (d.keys.size() == 2) {
    // Both physical planes carry the four-state argument (IEEE 1800-2023
    // 6.11.2, 13.5.1).
    // A nonzero secondary operand executes the original computation.
    Value secondary = args[d.keys[1]];
    Value known =
        LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, secondary,
                             LLVM::ZeroOp::create(b, loc, secondary.getType()));
    Block *lookup = new Block;
    f.getBody().push_back(lookup);
    LLVM::CondBrOp::create(b, loc, known, lookup, ValueRange{}, original, args);
    b.setInsertionPointToStart(lookup);
  } else {
    for (auto &block : llvm::drop_begin(f.getBody()))
      block.dropAllReferences();
    while (&f.getBody().back() != entry)
      f.getBody().back().erase();
  }
  Type resultType = f.getFunctionType().getReturnType();
  Value result;
  if (isa<LLVM::LLVMStructType>(resultType))
    result = LLVM::ZeroOp::create(b, loc, resultType);
  for (auto [j, field, values] : llvm::enumerate(d.fields, columns)) {
    Value scalar;
    if (llvm::all_equal(values)) {
      scalar = LLVM::ConstantOp::create(
          b, loc, field, b.getIntegerAttr(field, values.front()));
    } else {
      auto array = LLVM::LLVMArrayType::get(field, d.rows);
      LLVM::GlobalOp global;
      {
        OpBuilder::InsertionGuard guard(b);
        b.setInsertionPointToStart(module.getBody());
        auto tensor = RankedTensorType::get({int64_t(d.rows)}, field);
        global = LLVM::GlobalOp::create(
            b, loc, array, true, LLVM::Linkage::Internal,
            (f.getSymName() + ".__talos_value_table_" + Twine(j)).str(),
            DenseIntElementsAttr::get(tensor, values), 8);
        symbols.insert(global);
        copyNativePartition(f, global);
      }
      auto ptr = LLVM::LLVMPointerType::get(b.getContext());
      Value address = LLVM::AddressOfOp::create(b, loc, global);
      address = LLVM::GEPOp::create(b, loc, ptr, array, address,
                                    ArrayRef<LLVM::GEPArg>{0, index});
      scalar = LLVM::LoadOp::create(b, loc, field, address);
    }
    result = isa<LLVM::LLVMStructType>(resultType)
                 ? LLVM::InsertValueOp::create(b, loc, result, scalar,
                                               ArrayRef<int64_t>{int64_t(j)})
                       .getResult()
                 : scalar;
  }
  LLVM::ReturnOp::create(b, loc, result);
}
} // namespace

void materializeSmallValueTables(ModuleOp module) {
  if (!native::has<native::ClosedExecutable>(module))
    return;
  ValueClosures closures(module);
  SmallVector<Domain> candidates;
  for (auto f : module.getOps<LLVM::LLVMFuncOp>())
    if (auto domain = domainFor(f, closures))
      candidates.push_back(std::move(*domain));
  llvm::stable_sort(candidates, [](const Domain &a, const Domain &b) {
    return a.cost > b.cost;
  });
  // Bound translation work and constant data, independently of design size.
  unsigned work = 0, bytes = 0;
  llvm::erase_if(candidates, [&](const Domain &d) {
    unsigned size = 0;
    for (auto field : d.fields)
      size += llvm::PowerOf2Ceil((field.getWidth() + 7) / 8) * d.rows;
    if (size > 32768 - bytes || d.cost * d.rows > 4000000 - work)
      return true;
    work += d.cost * d.rows;
    bytes += size;
    return false;
  });
  if (candidates.empty())
    return;
  llvm::SetVector<Operation *> functions;
  for (auto &d : candidates)
    functions.insert(d.function);
  for (size_t i = 0; i < functions.size(); ++i)
    for (auto callee :
         closures.get(cast<LLVM::LLVMFuncOp>(functions[i])).callees)
      functions.insert(callee);
  OwningOpRef<ModuleOp> copy = ModuleOp::create(module.getLoc());
  OpBuilder b = OpBuilder::atBlockEnd(copy->getBody());
  for (auto *f : functions) {
    auto clone = cast<LLVM::LLVMFuncOp>(b.clone(*f));
    // The temporary module contains only the arithmetic call closure.
    // Linkage groups and unwind personalities belong to the original module.
    clone.removeComdatAttr();
    clone.removePersonalityAttr();
  }
  PassManager pm(module.getContext());
  pm.addPass(createArithToLLVMConversionPass());
  pm.addPass(createConvertControlFlowToLLVMPass());
  if (failed(pm.run(*copy)))
    return;
  llvm::LLVMContext llvmContext;
  auto ir = translateModuleToLLVMIR(copy->getOperation(), llvmContext,
                                    "talos.value.domains");
  if (!ir)
    return;
  SymbolTable symbols(module);
  unsigned count = 0;
  for (auto &d : candidates)
    if (auto *f = ir->getFunction(d.function.getSymName()))
      if (auto columns = evaluate(d, *f)) {
        emitTable(module, symbols, d, *columns);
        ++count;
      }
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos finite value functions: tables=" << count << '\n';
}
} // namespace talos::detail
