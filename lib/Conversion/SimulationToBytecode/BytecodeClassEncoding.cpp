//===- BytecodeClassEncoding.cpp - Managed class bytecode encoding -------===//

#include "BytecodeEncoder.h"
#include "BytecodeSerialization.h"
#include "talos/Analysis/ManagedClassLayoutAnalysis.h"
#include "talos/Analysis/SimulationStorageAnalysis.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/Support/MathExtras.h"

using namespace mlir;

namespace talos::bytecode {

LogicalResult Encoder::prepareClassLayouts() {
  FailureOr<analysis::ManagedClassLayoutAnalysis> layouts =
      analysis::ManagedClassLayoutAnalysis::compute(design, dataLayout);
  if (failed(layouts) ||
      failed(analysis::materializeManagedClassFieldOffsets(*layouts)))
    return failure();
  for (const analysis::ManagedClassLayoutAnalysis::Class &layout :
       layouts->classes) {
    sim::SimClassDeclOp declaration = layout.declaration;
    classIDs[declaration.getSymName()] = declaration.getId();
    for (const analysis::ManagedClassLayoutAnalysis::Field &field :
         layout.fields) {
      sim::SimClassFieldDeclOp fieldDeclaration = field.declaration;
      classFieldOffsets[fieldDeclaration.getSymName()] = field.offset;
    }
  }
  for (sim::SimClassMethodDeclOp method :
       design.getBody().front().getOps<sim::SimClassMethodDeclOp>()) {
    auto owner = classIDs.find(method.getOwner());
    // The shared layout already indexes every class. A fresh symbol lookup
    // here would scan the whole design for every method declaration.
    const auto *ownerLayout = layouts->lookup(method.getOwner());
    if (owner == classIDs.end() || !ownerLayout)
      return method.emitOpError("managed method owner is missing");
    sim::SimClassDeclOp ownerDeclaration = ownerLayout->declaration;
    classMethodDispatch[method.getSymName()] = {
        owner->second, method.getInterfaceOrdinal().value_or(UINT64_MAX),
        ownerDeclaration.getIsInterface()};
  }
  prepareNativeMethodCalls();
  return success();
}

void Encoder::prepareNativeMethodCalls() {
  // A VPI client can inspect the frame and scope of a running method (IEEE
  // 1800-2023 37.12, 37.43); only its own bytecode body has them.
  if (options.requireBytecode || (vpiProfile & TALOS_RT_DESIGN_PROFILE_READ))
    return;
  SmallVector<sim::SimClassMethodDeclOp> methods;
  for (auto method :
       design.getBody().front().getOps<sim::SimClassMethodDeclOp>())
    if (!method.getIsTask() && method.getImplementation()) {
      methods.push_back(method);
      methodImplementations.try_emplace(*method.getImplementation(), method);
    }
  if (methods.empty())
    return;
  llvm::StringMap<sim::SimFuncOp> functions;
  for (auto function : design.getBody().front().getOps<sim::SimFuncOp>())
    functions[function.getSymName()] = function;
  DenseMap<uint64_t, SmallVector<sim::SimFuncOp>> targets;
  SmallVector<sim::SimFuncOp> pending;
  for (auto method : methods) {
    uint64_t signature = method.getSignatureId().value_or(0);
    auto found = functions.find(*method.getImplementation());
    if (found == functions.end()) {
      bytecodeOnlyMethodSignatures.insert(signature);
      continue;
    }
    if (method.getIsVirtual())
      targets[signature].push_back(found->second);
    pending.push_back(found->second);
  }
  // IEEE 1800-2023 13.4(c) permits function process control. The native
  // callable ABI rejects control of the current process, whereas bytecode
  // unwinds its caller correctly. Preserve that behavior over the complete
  // call closure, including virtual overrides and recursive SCCs. Foreign
  // calls also stay interpreted until their callback/unwind ABI is covered.
  DenseSet<Operation *> visited, unsupported;
  DenseMap<Operation *, SmallVector<Operation *>> callers;
  SmallVector<Operation *> worklist;
  while (!pending.empty()) {
    sim::SimFuncOp function = pending.pop_back_val();
    if (!visited.insert(function).second)
      continue;
    bool needsBytecode = function.isExternal();
    auto edge = [&](sim::SimFuncOp callee) {
      callers[callee].push_back(function);
      pending.push_back(callee);
    };
    function.walk([&](Operation *operation) {
      if (operation == function)
        return;
      needsBytecode |= sim::isSuspensionOp(operation) ||
                       isa<sim::SimControlNonlocalExitOp, sim::SimDPICallOp,
                           sim::SimFinishOp, sim::SimStopOp, sim::SimFatalOp,
                           sim::SimErrorOp, sim::SimProgramExitOp>(operation);
      StringRef callee;
      if (auto call = dyn_cast<sim::SimCallOp>(operation))
        callee = call.getCallee();
      else if (auto call = dyn_cast<sim::SimClassDirectCallOp>(operation))
        callee = call.getCallee();
      if (!callee.empty()) {
        auto found = functions.find(callee);
        if (found == functions.end())
          needsBytecode = true;
        else
          edge(found->second);
      }
      if (auto call = dyn_cast<sim::SimClassVirtualCallOp>(operation)) {
        auto found = targets.find(call.getSignatureId());
        if (found == targets.end())
          needsBytecode = true;
        else
          for (sim::SimFuncOp target : found->second)
            edge(target);
      }
    });
    if (needsBytecode && unsupported.insert(function).second)
      worklist.push_back(function);
  }
  while (!worklist.empty()) {
    Operation *callee = worklist.pop_back_val();
    for (Operation *caller : callers[callee])
      if (unsupported.insert(caller).second)
        worklist.push_back(caller);
  }
  for (Operation *function : unsupported)
    bytecodeOnlyMethodBodies.insert(
        cast<sim::SimFuncOp>(function).getSymName());
  for (auto &entry : targets)
    if (llvm::any_of(entry.second, [&](sim::SimFuncOp target) {
          return unsupported.contains(target);
        }))
      bytecodeOnlyMethodSignatures.insert(entry.first);
}

FailureOr<uint64_t> Encoder::classID(SymbolRefAttr symbol,
                                     Operation *anchor) const {
  auto found = classIDs.find(symbol.getRootReference().getValue());
  if (found == classIDs.end()) {
    anchor->emitOpError("references an unknown managed class");
    return failure();
  }
  return found->second;
}

std::optional<LogicalResult>
Encoder::encodeClassOperation(FunctionPlan &plan, Operation *operation) {
  if (auto op = dyn_cast<sim::SimClassBuiltinUpcastOp>(operation)) {
    emit({Bitcast, 0, reg(plan, op.getResult()), reg(plan, op.getObject())});
    return success();
  }
  if (isa<sim::SimClassNullOp>(operation)) {
    uint32_t destination = reg(plan, operation->getResult(0));
    emit({Constant, 0, destination, 0, 0, 0, 0,
          addZeroConstant(plan.layouts[destination])});
    return success();
  }
  if (auto op = dyn_cast<sim::SimClassAllocOp>(operation)) {
    auto type = cast<sim::ClassHandleType>(op.getResult().getType());
    FailureOr<uint64_t> id = classID(type.getClassName(), operation);
    if (failed(id))
      return failure();
    uint32_t classRegister = emitU64Constant(plan, *id);
    return emitIntrinsicRegisters(plan, kIntrinsicClassAlloc, {classRegister},
                                  {reg(plan, op.getResult())});
  }
  if (auto op = dyn_cast<sim::SimClassCopyOp>(operation)) {
    auto type = cast<sim::ClassHandleType>(op.getResult().getType());
    FailureOr<uint64_t> id = classID(type.getClassName(), operation);
    if (failed(id))
      return failure();
    uint32_t classRegister = emitU64Constant(plan, *id);
    return emitIntrinsicRegisters(plan, kIntrinsicClassCopy,
                                  {reg(plan, op.getSource()), classRegister},
                                  {reg(plan, op.getResult())});
  }
  if (auto op = dyn_cast<sim::SimClassIsInstanceOp>(operation)) {
    FailureOr<uint64_t> id = classID(op.getTargetAttr(), operation);
    if (failed(id))
      return failure();
    uint32_t classRegister = emitU64Constant(plan, *id);
    return emitIntrinsicRegisters(plan, kIntrinsicClassIsInstance,
                                  {reg(plan, op.getObject()), classRegister},
                                  {reg(plan, op.getResult())});
  }
  if (auto op = dyn_cast<sim::SimClassIdOp>(operation))
    return emitIntrinsic(plan, kIntrinsicClassID, {op.getObject()},
                         {op.getResult()});
  if (auto op = dyn_cast<sim::SimClassCastOp>(operation)) {
    auto type = cast<sim::ClassHandleType>(op.getResult().getType());
    FailureOr<uint64_t> id = classID(type.getClassName(), operation);
    if (failed(id))
      return failure();
    uint32_t classRegister = emitU64Constant(plan, *id);
    return emitIntrinsicRegisters(plan, kIntrinsicClassCast,
                                  {reg(plan, op.getObject()), classRegister},
                                  {reg(plan, op.getResult())});
  }
  if (auto op = dyn_cast<sim::SimClassFieldRefOp>(operation)) {
    auto offset = classFieldOffsets.find(op.getField());
    if (offset == classFieldOffsets.end())
      return op.emitOpError("managed field has no bytecode layout");
    uint32_t offsetRegister = emitU64Constant(plan, offset->second);
    return emitIntrinsicRegisters(plan, kIntrinsicClassFieldRef,
                                  {reg(plan, op.getObject()), offsetRegister},
                                  {reg(plan, op.getResult())});
  }
  if (auto op = dyn_cast<sim::SimClassDirectCallOp>(operation))
    return encodeClassDirectCall(plan, op);
  if (auto op = dyn_cast<sim::SimClassVirtualCallOp>(operation))
    return encodeClassVirtualCall(plan, op);
  if (auto op = dyn_cast<sim::SimClassVirtualTaskCallOp>(operation))
    return encodeClassVirtualTaskCall(plan, op);
  if (auto op = dyn_cast<sim::SimWeakCreateOp>(operation)) {
    auto wrapperType = cast<sim::ClassHandleType>(op.getResult().getType());
    FailureOr<uint64_t> id = classID(wrapperType.getClassName(), operation);
    if (failed(id))
      return failure();
    return emitIntrinsicRegisters(
        plan, kIntrinsicWeakCreate,
        {reg(plan, op.getReferent()), emitU64Constant(plan, *id)},
        {reg(plan, op.getResult())});
  }
  return std::nullopt;
}

LogicalResult Encoder::encodeClassDirectCall(FunctionPlan &plan,
                                             sim::SimClassDirectCallOp call) {
  auto found = indices.find(call.getCallee());
  if (found == indices.end())
    return call.emitOpError("class method has no bytecode body");
  FunctionPlan &callee = plans[found->second];
  SmallVector<Value> arguments{plan.function.getBody().front().getArgument(0),
                               call.getReceiver()};
  llvm::append_range(arguments, call.getArguments());
  auto inputs = addMap(callee, callee.function.getBody().front().getArguments(),
                       plan, arguments);
  uint64_t firstOutputs = operandMaps.size();
  for (auto [destination, source] :
       llvm::zip_equal(call.getResults(), callee.resultRegisters))
    operandMaps.push_back({reg(plan, destination), source});
  firstOutputs = internOperandRun(firstOutputs);
  if (encodeNativeDirectCall(plan, call.getCallee(), arguments,
                             call.getResults(), inputs.first, firstOutputs))
    return success();
  emit({Call, 0, 0, callee.index, static_cast<uint32_t>(inputs.first),
        static_cast<uint32_t>(inputs.second),
        static_cast<uint32_t>(firstOutputs), call.getNumResults()});
  return success();
}

bool Encoder::encodeNativeDirectCall(FunctionPlan &plan, StringRef callee,
                                     ValueRange arguments, ValueRange results,
                                     uint32_t firstInputs,
                                     uint32_t firstOutputs) {
  auto found = methodImplementations.find(callee);
  if (found == methodImplementations.end() ||
      bytecodeOnlyMethodBodies.contains(callee) || results.size() > UINT16_MAX)
    return false;
  sim::SimClassMethodDeclOp method = found->second;
  unsigned implicit = method.getIsStatic() ? 1 : 2;
  if (arguments.size() < implicit)
    return false;
  auto site = encodeNativeMethodSite(plan, arguments.drop_front(implicit),
                                     results, firstOutputs);
  if (!site)
    return false;
  uint32_t index = indices.lookup(callee);
  nativeMethodCallees.insert(index);
  // IEEE 1800-2023 8.10/8.20: this binding names the statically chosen method,
  // including base-qualified calls. It must not resolve a derived override.
  emit({NativeDirectCall, static_cast<uint16_t>(results.size()), index,
        method.getIsStatic() ? UINT32_MAX : reg(plan, arguments[1]),
        firstInputs, static_cast<uint32_t>(arguments.size()), *site,
        classIDs.lookup(method.getOwner())});
  return true;
}

LogicalResult Encoder::encodeClassVirtualCall(FunctionPlan &plan,
                                              sim::SimClassVirtualCallOp call) {
  if (call.getSlot() > UINT32_MAX || call.getNumResults() > UINT16_MAX)
    return call.emitOpError("virtual call exceeds the bytecode ABI");
  Opcode opcode = VirtualCall;
  uint32_t dispatch = static_cast<uint32_t>(call.getSlot());
  auto method = classMethodDispatch.find(call.getMethod());
  if (method == classMethodDispatch.end())
    return call.emitOpError("virtual method descriptor is missing");
  if (method->second.isInterface) {
    if (method->second.interfaceOrdinal == UINT64_MAX)
      return call.emitOpError("interface method has no dispatch ordinal");
    if (method->second.ownerID > UINT32_MAX ||
        method->second.interfaceOrdinal > UINT32_MAX ||
        operandMaps.size() >= UINT32_MAX)
      return call.emitOpError("interface dispatch exceeds the bytecode ABI");
    opcode = InterfaceCall;
    dispatch = static_cast<uint32_t>(operandMaps.size());
    operandMaps.push_back(
        {static_cast<uint32_t>(method->second.ownerID),
         static_cast<uint32_t>(method->second.interfaceOrdinal)});
    dispatch = internOperandRun(dispatch);
  }
  SmallVector<Value> arguments{plan.function.getBody().front().getArgument(0),
                               call.getReceiver()};
  llvm::append_range(arguments, call.getArguments());
  if (arguments.size() > UINT32_MAX || operandMaps.size() > UINT32_MAX)
    return call.emitOpError("virtual argument map exceeds the bytecode ABI");
  uint32_t firstInputs = operandMaps.size();
  for (auto [index, argument] : llvm::enumerate(arguments))
    operandMaps.push_back({static_cast<uint32_t>(index), reg(plan, argument)});
  firstInputs = internOperandRun(firstInputs);
  uint32_t firstOutputs = operandMaps.size();
  for (auto [index, result] : llvm::enumerate(call.getResults()))
    operandMaps.push_back(
        {reg(plan, result), static_cast<uint32_t>(arguments.size() + index)});
  firstOutputs = internOperandRun(firstOutputs);
  uint32_t outputs = firstOutputs;
  if (!bytecodeOnlyMethodSignatures.contains(call.getSignatureId()))
    if (auto site = encodeNativeMethodSite(plan, call.getArguments(),
                                           call.getResults(), firstOutputs)) {
      opcode =
          opcode == InterfaceCall ? NativeInterfaceCall : NativeVirtualCall;
      outputs = *site;
    }
  emit({opcode, static_cast<uint16_t>(call.getNumResults()), dispatch,
        reg(plan, call.getReceiver()), firstInputs,
        static_cast<uint32_t>(arguments.size()), outputs,
        call.getSignatureId()});
  return success();
}

std::optional<uint32_t> Encoder::encodeNativeMethodSite(FunctionPlan &plan,
                                                        ValueRange arguments,
                                                        ValueRange results,
                                                        uint32_t firstOutputs) {
  // IEEE 1800-2023 8.6, 8.20, 13.4 and 13.5: a function's native entry
  // executes in the caller's activation, with the same automatic lifetime,
  // dispatch and argument values. Packed integral values (7.4.1) share the
  // scalar plane ABI. Managed values, unpacked values and exact-alias argument
  // references share canonical storage. Ordinary simulation handles need a
  // separate stable-ID conversion from their expanded bytecode records.
  if (options.requireBytecode)
    return std::nullopt;
  SmallVector<uint8_t> records;
  uint32_t argumentPlanes = 0, resultPlanes = 0;
  uint64_t resultSize = 0;
  uint32_t resultAlignment = 1;
  llvm::LLVMContext llvmContext;
  auto append = [&](Value value, bool result) {
    Type type = value.getType();
    uint32_t index = reg(plan, value);
    const Layout &layout = plan.layouts[index];
    switch (layout.kind) {
    case Bits:
    case Logic:
    case Managed:
    case String:
    case Real32:
    case Real64:
    case ManagedRef:
    case ArgumentRef:
      break;
    default:
      return false;
    }
    auto storage =
        analysis::getSimulationStorageProperties(type, dataLayout, llvmContext);
    uint64_t nativeSize =
        layout.kind == ManagedRef ? 8 : (uint64_t{layout.width} + 7) / 8;
    if (failed(storage) || storage->size != nativeSize ||
        storage->size > UINT32_MAX ||
        (storage->fourState && layout.kind != Logic) ||
        storage->managedReference != (layout.kind == ManagedRef))
      return false;
    unsigned planes = analysis::getSimulationPhysicalStorageCount(*storage);
    uint64_t planeStride = layout.size / planes;
    if (planeStride > UINT32_MAX || storage->size > planeStride)
      return false;
    for (unsigned plane = 0; plane != planes; ++plane) {
      uint64_t offset = 0;
      if (result) {
        offset = llvm::alignTo(resultSize, storage->alignment);
        if (offset > UINT32_MAX || storage->size > UINT32_MAX - offset)
          return false;
        resultSize = offset + storage->size;
        resultAlignment = std::max(resultAlignment, storage->alignment);
        ++resultPlanes;
      } else {
        ++argumentPlanes;
      }
      append32(records, index);
      append32(records, plane * planeStride);
      append32(records, storage->size);
      append32(records, offset);
    }
    return true;
  };
  for (Value argument : arguments)
    if (!append(argument, false))
      return std::nullopt;
  for (Value result : results)
    if (!append(result, true))
      return std::nullopt;
  resultSize = llvm::alignTo(resultSize, resultAlignment);
  if (resultSize > UINT32_MAX)
    return std::nullopt;
  SmallVector<uint8_t> site;
  append32(site, firstOutputs);
  append32(site, argumentPlanes);
  append32(site, resultPlanes);
  append32(site, 0);
  append64(site, resultSize);
  llvm::append_range(site, records);
  if (constants.size() > UINT32_MAX ||
      site.size() > UINT32_MAX - constants.size())
    return std::nullopt;
  return static_cast<uint32_t>(addRawConstant(site));
}

LogicalResult
Encoder::encodeClassVirtualTaskCall(FunctionPlan &plan,
                                    sim::SimClassVirtualTaskCallOp call) {
  if (!plan.frame)
    return call.emitOpError("virtual task call has no canonical caller frame");
  const ProcessSuspension *suspension =
      plan.frame->getSuspension(call.getOperation());
  if (!suspension)
    return call.emitOpError("virtual task call is missing frame analysis");
  ArrayRef<ProcessFrameValue> slots =
      plan.frame->getContinuationLayout(suspension->continuationID);
  if (slots.size() != call.getContinuationOperands().size())
    return call.emitOpError("virtual task continuation frame arity mismatch");
  for (auto [value, slot] :
       llvm::zip_equal(call.getContinuationOperands(), slots)) {
    if (slot.storageSize > UINT32_MAX ||
        (slot.hasSecondaryStorage() && slot.storageSize > UINT32_MAX / 2))
      return call.emitOpError(
          "canonical frame transfer exceeds the bytecode ABI limit");
    uint64_t transferSize =
        slot.storageSize * (slot.hasSecondaryStorage() ? 2 : 1);
    emitFrameTransfer(plan, StoreFrame, value, slot.valueOffset,
                      static_cast<uint32_t>(transferSize),
                      slot.isFourState() ? slot.unknownOffset : UINT64_MAX);
  }

  if (call.getSlot() > UINT32_MAX || call.getArguments().size() > UINT32_MAX ||
      operandMaps.size() > UINT32_MAX)
    return call.emitOpError("virtual task call exceeds the bytecode ABI");
  Opcode opcode = VirtualTaskCall;
  uint32_t dispatch = static_cast<uint32_t>(call.getSlot());
  auto method = classMethodDispatch.find(call.getMethod());
  if (method == classMethodDispatch.end())
    return call.emitOpError("virtual task descriptor is missing");
  if (method->second.isInterface) {
    if (method->second.interfaceOrdinal == UINT64_MAX)
      return call.emitOpError("interface task has no dispatch ordinal");
    if (method->second.ownerID > UINT32_MAX ||
        method->second.interfaceOrdinal > UINT32_MAX ||
        operandMaps.size() >= UINT32_MAX)
      return call.emitOpError("interface dispatch exceeds the bytecode ABI");
    opcode = InterfaceTaskCall;
    dispatch = static_cast<uint32_t>(operandMaps.size());
    operandMaps.push_back(
        {static_cast<uint32_t>(method->second.ownerID),
         static_cast<uint32_t>(method->second.interfaceOrdinal)});
    dispatch = internOperandRun(dispatch);
  }
  SmallVector<Value> arguments{plan.function.getBody().front().getArgument(0),
                               call.getReceiver()};
  llvm::append_range(arguments, call.getArguments());
  if (arguments.size() > UINT32_MAX)
    return call.emitOpError(
        "virtual task argument map exceeds the bytecode ABI");
  uint32_t firstInputs = operandMaps.size();
  for (auto [index, argument] : llvm::enumerate(arguments))
    operandMaps.push_back({static_cast<uint32_t>(index), reg(plan, argument)});
  firstInputs = internOperandRun(firstInputs);
  emit({opcode, 0, dispatch, reg(plan, call.getReceiver()), firstInputs,
        static_cast<uint32_t>(arguments.size()), suspension->continuationID,
        call.getSignatureId()});
  return success();
}

} // namespace talos::bytecode
