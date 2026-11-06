//===- SimulationNativeMethodTables.cpp - Typed class dispatch ----------===//

#include "SimulationToLLVMCoroutinePrivate.h"

#include "talos/Analysis/ClassDispatchAnalysis.h"
#include "talos/Analysis/SimulationStorageAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeOps.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/DescriptorMap.h"
#include "talos/Runtime/Runtime.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/LLVMContext.h"

#include <array>
#include <map>
#include <tuple>

using namespace mlir;

namespace talos::detail {

std::string managedTypedMethodName(StringRef methodName) {
  return (methodName + ".__talos_typed_entry").str();
}

LLVM::LLVMStructType managedClassDescriptorType(MLIRContext *context) {
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i32 = IntegerType::get(context, 32);
  Type i64 = IntegerType::get(context, 64);
  return LLVM::LLVMStructType::getLiteral(
      context, {i32,     i32,     i64, i64,     i64, pointer, pointer, i64,
                pointer, pointer, i64, pointer, i64, pointer, pointer, i64,
                i32,     i32,     i64, pointer, i64, pointer});
}

namespace {

struct DispatchKey {
  uint64_t interfaceID, slot, signature;
  bool isTask;
  bool operator<(const DispatchKey &other) const {
    return std::tie(interfaceID, slot, signature, isTask) <
           std::tie(other.interfaceID, other.slot, other.signature,
                    other.isTask);
  }
};

// Assign dense ordinals only to native call sites that survived optimization.
// A persistent radix tree shares every inherited subtree unaffected by an
// override. Its depth depends on the number of used keys, not sparse language
// slot numbers or inheritance depth. Interning also shares identical tables
// across unrelated classes. Zero denotes an absent subtree/entry.
class MethodTables {
  using Entries = std::array<uint32_t, 16>;
  struct Node {
    unsigned level;
    Entries entries;
  };
  SmallVector<Node> nodes;
  std::map<std::pair<unsigned, Entries>, uint32_t> interned;

public:
  uint32_t set(uint32_t root, uint32_t ordinal, uint32_t target,
               unsigned level) {
    Entries entries{};
    if (root)
      entries = nodes[root - 1].entries;
    unsigned digit = (ordinal >> (level * 4)) & 15;
    entries[digit] =
        level ? set(entries[digit], ordinal, target, level - 1) : target;
    if (llvm::all_of(entries, [](uint32_t entry) { return entry == 0; }))
      return 0;
    auto [found, inserted] =
        interned.try_emplace(std::pair(level, entries), nodes.size() + 1);
    if (inserted)
      nodes.push_back({level, entries});
    return found->second;
  }

  static std::string name(uint32_t node) {
    return "__talos_native_vtable_" + std::to_string(node);
  }

  void emit(ModuleOp module, Location location, ArrayRef<std::string> targets,
            ArrayRef<uint32_t> roots) {
    DenseSet<uint32_t> retained;
    SmallVector<uint32_t> pending(roots);
    while (!pending.empty()) {
      uint32_t index = pending.pop_back_val();
      if (!index || !retained.insert(index).second)
        continue;
      const Node &node = nodes[index - 1];
      if (node.level)
        llvm::append_range(pending, node.entries);
    }
    Type pointer = LLVM::LLVMPointerType::get(module.getContext());
    Type arrayType = LLVM::LLVMArrayType::get(pointer, 16);
    for (auto indexed : llvm::enumerate(nodes)) {
      if (!retained.contains(indexed.index() + 1))
        continue;
      const Node &node = indexed.value();
      makeConstantGlobal(
          module, location, arrayType, name(indexed.index() + 1),
          LLVM::Linkage::Internal, 8, [&](OpBuilder &builder) {
            Value array = LLVM::ZeroOp::create(builder, location, arrayType);
            for (auto [digit, entry] : llvm::enumerate(node.entries)) {
              if (!entry)
                continue;
              std::string symbol =
                  node.level ? name(entry) : targets[entry - 1];
              array = LLVM::InsertValueOp::create(
                  builder, location, array,
                  LLVM::AddressOfOp::create(builder, location, pointer, symbol),
                  ArrayRef<int64_t>{static_cast<int64_t>(digit)});
            }
            return array;
          });
    }
  }
};

} // namespace

FailureOr<llvm::StringMap<std::string>>
materializeNativeMethodTables(ModuleOp module,
                              ArrayRef<sim::SimClassDeclOp> classes,
                              const analysis::ClassDispatchAnalysis &dispatch) {
  llvm::StringMap<std::string> roots;
  if (classes.empty())
    return roots;
  auto design = classes.front()->getParentOfType<sim::SimDesignOp>();
  struct Call {
    Operation *operation;
    FlatSymbolRefAttr method;
    uint64_t slot, signature;
    bool isTask;
  };
  SmallVector<Call> calls;
  // Inventory native task callers before frames are frozen. Only families
  // whose every implementation has a synchronous body receive a table path.
  // The later root-preparation phase can insert calls without replacing the
  // canonical suspension operations held by the frame snapshot.
  DenseSet<uint64_t> taskFamilies, unsupportedTasks;
  for (auto method : design.getOps<sim::SimClassMethodDeclOp>()) {
    if (!method.getIsTask() || !method.getIsVirtual() ||
        !method.getImplementation())
      continue;
    uint64_t signature = method.getSignatureId().value_or(0);
    taskFamilies.insert(signature);
    if (!native::get<native::SynchronousTaskBody>(method))
      unsupportedTasks.insert(signature);
  }
  module.walk([&](Operation *operation) {
    auto append = [&](auto call, bool isTask) {
      native::remove<native::MethodVtablePath>(call);
      calls.push_back({call, call.getMethodAttr(), call.getSlot(),
                       call.getSignatureId(), isTask});
    };
    if (auto call = dyn_cast<sim::SimClassVirtualCallOp>(operation))
      append(call, false);
    else if (auto call =
                 dyn_cast<schedule::NativeSynchronousClassCallOp>(operation))
      append(call, true);
    else if (auto call = dyn_cast<sim::SimClassVirtualTaskCallOp>(operation)) {
      native::remove<native::MethodVtablePath>(call);
      if (taskFamilies.contains(call.getSignatureId()) &&
          !unsupportedTasks.contains(call.getSignatureId()))
        append(call, true);
    }
  });
  if (calls.empty() ||
      runtime::bitEnumContainsAll(runtime::getExecutionFlags(module),
                                  runtime::ExecutionFlags::RequireBytecode))
    return roots;

  SymbolTableCollection symbols;
  std::map<DispatchKey, uint32_t> ordinals;
  SmallVector<DispatchKey> callKeys;
  DenseMap<uint64_t, sim::SimClassDeclOp> interfaces;
  for (auto call : calls) {
    auto method = symbols.lookupNearestSymbolFrom<sim::SimClassMethodDeclOp>(
        call.operation, call.method);
    auto owner =
        method ? dispatch.lookup(method.getOwner()) : sim::SimClassDeclOp{};
    if (!owner)
      return call.operation->emitError("virtual method owner is missing"),
             failure();
    DispatchKey key{owner.getIsInterface() ? owner.getId() : 0,
                    owner.getIsInterface() ? UINT32_MAX : call.slot,
                    call.signature, call.isTask};
    if (owner.getIsInterface())
      interfaces.try_emplace(owner.getId(), owner);
    ordinals.try_emplace(key, 0);
    callKeys.push_back(key);
  }
  if (ordinals.size() > UINT32_MAX)
    return module.emitError("native method table has too many keys"), failure();
  unsigned depth = 1;
  for (uint64_t capacity = 16; capacity < ordinals.size(); capacity *= 16)
    ++depth;
  SmallVector<DispatchKey> keys;
  DenseMap<uint64_t, SmallVector<uint32_t>> bySlot, bySignature, byInterface;
  for (auto &[key, ordinal] : ordinals) {
    ordinal = keys.size();
    keys.push_back(key);
    if (key.interfaceID) {
      bySignature[key.signature].push_back(ordinal);
      byInterface[key.interfaceID].push_back(ordinal);
    } else {
      bySlot[key.slot].push_back(ordinal);
    }
  }
  Builder attributes(module.getContext());
  for (auto [call, key] : llvm::zip_equal(calls, callKeys))
    native::set<native::MethodVtablePath>(
        call.operation,
        attributes.getDenseI32ArrayAttr({static_cast<int32_t>(ordinals.at(key)),
                                         static_cast<int32_t>(depth)}));

  llvm::StringMap<SmallVector<sim::SimClassMethodDeclOp>> methods;
  for (auto method : design.getOps<sim::SimClassMethodDeclOp>())
    if (method.getSlot() && method.getSignatureId())
      methods[method.getOwner()].push_back(method);
  struct State {
    uint32_t root = 0;
    talos::runtime::DescriptorMap<sim::SimClassMethodDeclOp> methods;
  };
  llvm::StringMap<State> states;
  MethodTables tables;
  SmallVector<uint32_t> tableRoots;
  SmallVector<std::string> targets;
  DenseMap<Operation *, uint32_t> targetIndices;
  OpBuilder builder(module.getContext());
  builder.setInsertionPointToStart(module.getBody());
  for (auto declaration : classes) {
    if (declaration.getIsInterface())
      continue;
    State state;
    if (auto base = declaration.getBase())
      state = states[*base];
    llvm::SetVector<uint32_t> affected;
    for (auto method : methods[declaration.getSymName()]) {
      uint64_t slot = *method.getSlot();
      if (const auto *previous = state.methods.find(slot)) {
        auto previousMethod = *previous;
        if (auto signature = previousMethod.getSignatureId())
          affected.insert_range(bySignature[*signature]);
      }
      state.methods = state.methods.set(slot, method);
      affected.insert_range(bySlot[slot]);
      affected.insert_range(bySignature[*method.getSignatureId()]);
    }
    SmallVector<sim::SimClassDeclOp> pendingInterfaces;
    if (ArrayAttr implemented = declaration.getInterfacesAttr())
      for (Attribute attribute : implemented)
        pendingInterfaces.push_back(
            dispatch.lookup(cast<FlatSymbolRefAttr>(attribute).getValue()));
    DenseSet<Operation *> visited;
    while (!pendingInterfaces.empty()) {
      auto interface = pendingInterfaces.pop_back_val();
      if (!interface || !visited.insert(interface).second)
        continue;
      affected.insert_range(byInterface[interface.getId()]);
      if (auto base = interface.getBase())
        pendingInterfaces.push_back(dispatch.lookup(*base));
      if (ArrayAttr bases = interface.getInterfacesAttr())
        for (Attribute attribute : bases)
          pendingInterfaces.push_back(
              dispatch.lookup(cast<FlatSymbolRefAttr>(attribute).getValue()));
    }
    for (uint32_t ordinal : affected) {
      const DispatchKey &key = keys[ordinal];
      auto method = dispatch.resolve(declaration, key.slot, key.signature);
      uint32_t target = 0;
      if (method && !method.getIsPure() && method.getIsTask() == key.isTask &&
          (!key.isTask || native::get<native::SynchronousTaskBody>(method)) &&
          method.getImplementation() &&
          (!key.interfaceID ||
           dispatch.isInstanceOf(declaration,
                                 interfaces.lookup(key.interfaceID)))) {
        auto [found, inserted] =
            targetIndices.try_emplace(method, targets.size() + 1);
        if (inserted) {
          std::string name = managedTypedMethodName(method.getSymName());
          targets.push_back(name);
          // The opaque address is used before ordinary implementation types
          // are converted. Replace this forward declaration with its exact
          // typed ABI when materializing the native entries below.
          LLVM::LLVMFuncOp::create(
              builder, method.getLoc(), name,
              LLVM::LLVMFunctionType::get(
                  LLVM::LLVMVoidType::get(module.getContext()), {}, false));
        }
        target = found->second;
      }
      state.root = tables.set(state.root, ordinal, target, depth - 1);
    }
    if (state.root) {
      roots[declaration.getSymName()] = MethodTables::name(state.root);
      tableRoots.push_back(state.root);
    }
    states[declaration.getSymName()] = std::move(state);
  }
  tables.emit(module, design.getLoc(), targets, tableRoots);
  return roots;
}

LogicalResult
materializeTypedNativeMethodEntries(ModuleOp module,
                                    const llvm::DataLayout &dataLayout) {
  SmallVector<schedule::NativeMethodOp> methods;
  module.walk(
      [&](schedule::NativeMethodOp method) { methods.push_back(method); });
  SymbolTableCollection symbols;
  SymbolTable &moduleSymbols = symbols.getSymbolTable(module);
  Type i32 = IntegerType::get(module.getContext(), 32);
  llvm::DataLayout layout(dataLayout.getStringRepresentation());
  llvm::LLVMContext llvmContext;
  for (auto method : methods) {
    std::string name = managedTypedMethodName(method.getSymName());
    auto declaration = moduleSymbols.lookup<LLVM::LLVMFuncOp>(name);
    if (!declaration)
      continue;
    if (!declaration.isExternal())
      return declaration.emitError("native typed method entry already exists");
    auto implementation = symbols.lookupNearestSymbolFrom<func::FuncOp>(
        method, method.getIsTask()
                    ? native::get<native::SynchronousTaskBody>(method)
                    : method.getImplementationAttr());
    if (!implementation)
      return method.emitError("native typed method implementation is missing");
    FunctionType semantic = cast<FunctionType>(method.getFunctionType());
    unsigned resultCount = 0;
    for (Type type : semantic.getResults()) {
      auto storage =
          analysis::getSimulationStorageProperties(type, layout, llvmContext);
      if (failed(storage))
        return method.emitError("native typed result has no storage layout");
      resultCount += analysis::getSimulationPhysicalStorageCount(*storage);
    }
    FunctionType physical = implementation.getFunctionType();
    if (physical.getNumResults() < resultCount ||
        physical.getNumResults() > resultCount + 1)
      return method.emitError("native typed result flattening is inconsistent");
    SmallVector<Type> results(physical.getResults().take_front(resultCount));
    results.push_back(i32);
    Type resultType =
        results.size() == 1
            ? i32
            : LLVM::LLVMStructType::getLiteral(module.getContext(), results);
    moduleSymbols.erase(declaration);
    OpBuilder builder(module.getContext());
    builder.setInsertionPointToStart(module.getBody());
    auto entry = LLVM::LLVMFuncOp::create(
        builder, method.getLoc(), name,
        LLVM::LLVMFunctionType::get(resultType, physical.getInputs(), false),
        LLVM::Linkage::Internal);
    moduleSymbols.insert(entry);
    copyNativePartition(implementation, entry);
    Block *body = entry.addEntryBlock(builder);
    builder.setInsertionPointToStart(body);
    auto call = func::CallOp::create(builder, method.getLoc(), implementation,
                                     body->getArguments());
    Value status = llvmConstant(builder, method.getLoc(), i32, TALOS_RT_OK);
    if (call.getNumResults() != resultCount) {
      status = call.getResult(resultCount);
      if (isa<runtime::StatusType>(status.getType()))
        status = runtime::RTStatusToBitsOp::create(builder, method.getLoc(),
                                                   i32, status);
      if (status.getType() != i32)
        return method.emitError("native typed method has no status result");
    }
    Value result = status;
    if (resultCount) {
      result = LLVM::ZeroOp::create(builder, method.getLoc(), resultType);
      for (unsigned index = 0; index != resultCount; ++index)
        result = insertValue(builder, method.getLoc(), result,
                             call.getResult(index), index);
      result =
          insertValue(builder, method.getLoc(), result, status, resultCount);
    }
    LLVM::ReturnOp::create(builder, method.getLoc(), result);
  }
  return success();
}

} // namespace talos::detail
