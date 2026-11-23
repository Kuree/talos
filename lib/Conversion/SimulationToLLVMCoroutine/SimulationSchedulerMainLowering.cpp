//===- SimulationSchedulerMainLowering.cpp - Native scheduler entry ----===//

#include "NativeStateAccess.h"
#include "SimulationToLLVMCoroutinePrivate.h"

#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/SAIF/SAIFDialect.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/Support/Endian.h"

using namespace mlir;

namespace talos::detail {

// Reserved names for the final-simulation-time channel. The accessors are
// exported so a standalone host can read the value after main returns; the
// storage itself stays internal.
static constexpr llvm::StringLiteral kFinalTimeName = "__talos_final_time";
static constexpr llvm::StringLiteral kFinalTimeAccessorName =
    "talos_final_time";
static constexpr llvm::StringLiteral kTimePrecisionAccessorName =
    "talos_time_precision_fs";

static LogicalResult bindWaveformAliases(ModuleOp module, OpBuilder &builder,
                                         const NativeStateLayout &layout,
                                         Value runtimeContext) {
  SmallVector<std::array<uint64_t, 3>> rows;
  WalkResult result = module.walk([&](sim::SimStorageDeclOp storage) {
    auto alias = sim::get<sim::metadata::PostponedWaveformAlias>(storage);
    if (!alias)
      return WalkResult::advance();
    auto width = sim::getPackedWidth(storage.getType());
    if (!width || !*width)
      return WalkResult::advance();
    if (alias.size() != 2 || alias[0] < 0 || alias[1] < 0)
      return WalkResult::interrupt();
    auto dst = layout.storageOffsets.find(storage.getId());
    auto src = layout.storageOffsets.find(alias[0]);
    auto handle = layout.storage.find(alias[0]);
    talos_rt_stable_handle_v1 physical{};
    const auto *bound =
        handle != layout.storage.end() &&
                talos_rt_stable_handle_decode(handle->second, &physical) &&
                physical.kind == TALOS_RT_STABLE_HANDLE_STATIC
            ? layout.findBound(physical.id)
            : nullptr;
    if (!bound || uint64_t(alias[1]) > bound->width ||
        *width > bound->width - uint64_t(alias[1]))
      return WalkResult::interrupt();
    if (dst == layout.storageOffsets.end() ||
        src == layout.storageOffsets.end() || src->second > layout.bitCount ||
        uint64_t(alias[1]) > layout.bitCount - src->second)
      return WalkResult::interrupt();
    uint64_t source = src->second + alias[1];
    if (dst->second > layout.bitCount ||
        *width > layout.bitCount - dst->second ||
        *width > layout.bitCount - source)
      return WalkResult::interrupt();
    if (source != dst->second)
      rows.push_back({dst->second, source, *width});
    return WalkResult::advance();
  });
  if (result.wasInterrupted())
    return module.emitError("invalid settled VCD alias range");
  // Undelayed, collapsed wire/tri bits are one simulated net (23.3.3.7).
  // Group contiguous mappings only; reversed or scattered bits do not form
  // a vector view. Mixed resolution, pass devices and delayed nets retain
  // independent declarations and sampling.
  if (!layout.hasPassSwitch && !layout.connectivityCanonical.empty()) {
    DenseSet<uint64_t> plain;
    for (const auto &net : layout.netLayouts)
      if (net.fourState &&
          llvm::none_of(net.propagationDelays,
                        [](auto delay) { return delay.has_value(); }) &&
          (net.resolution == sim::NetResolutionKind::Wire ||
           net.resolution == sim::NetResolutionKind::Tri))
        plain.insert(net.id);
    SmallVector<std::pair<uint64_t, uint64_t>> bits;
    for (const auto &[canonical, members] : layout.connectivityComponents) {
      if (!llvm::all_of(members,
                        [&](auto bit) { return plain.contains(bit.net); }))
        continue;
      uint64_t src = layout.netOffsets.at(canonical.first) + canonical.second;
      for (auto bit : members) {
        uint64_t dst = layout.netOffsets.at(bit.net) + bit.offset;
        if (src != dst)
          bits.emplace_back(dst, src);
      }
    }
    llvm::sort(bits);
    size_t first = 0;
    while (first < bits.size()) {
      size_t end = first + 1;
      while (end < bits.size() && bits[end].first == bits[end - 1].first + 1 &&
             bits[end].second == bits[end - 1].second + 1)
        ++end;
      rows.push_back({bits[first].first, bits[first].second, end - first});
      first = end;
    }
  }
  if (rows.empty())
    return success();
  llvm::sort(rows);
  SmallVector<int64_t> values;
  for (const auto &row : rows)
    llvm::append_range(values, row);
  auto loc = module.getLoc();
  auto i64 = builder.getI64Type();
  constexpr StringLiteral name = "__talos_vcd_aliases_v1";
  makeConstantGlobal(module, loc, LLVM::LLVMArrayType::get(i64, values.size()),
                     name, LLVM::Linkage::Internal, 8,
                     DenseElementsAttr::get(
                         RankedTensorType::get({int64_t(values.size())}, i64),
                         ArrayRef(values)));
  declareNativeRuntime(module, NativeRuntimeEntry::DumpBindAliases);
  auto status = LLVM::CallOp::create(
      builder, loc, TypeRange{builder.getI32Type()},
      getNativeRuntimeCallee(module.getContext(),
                             NativeRuntimeEntry::DumpBindAliases),
      ValueRange{runtimeContext,
                 LLVM::AddressOfOp::create(
                     builder, loc,
                     LLVM::LLVMPointerType::get(module.getContext()), name),
                 llvmConstant(builder, loc, i64, rows.size())});
  LLVM::CallOp::create(
      builder, loc, TypeRange{},
      getNativeRuntimeCallee(module.getContext(),
                             NativeRuntimeEntry::SchedulerFail),
      ValueRange{runtimeContext, status.getResult()});
  return success();
}

LogicalResult makeSchedulerMain(ModuleOp module,
                                const NativeStateLayout &stateLayout,
                                bool useAOT, bool directEval,
                                bool hasObserver) {
  if (module.lookupSymbol("main"))
    return success();
  sim::SimFuncOp root;
  bool multipleRoots = false;
  ::talos::detail::walkNativeFunctions<sim::SimFuncOp>(
      module, [&](sim::SimFuncOp function) {
        if (function.getEntryKind() != sim::EntryKind::RootInitializer)
          return;
        multipleRoots |= static_cast<bool>(root);
        if (!root)
          root = function;
      });
  if (multipleRoots)
    return module.emitError("design has multiple root processes");
  if (!root)
    return success();
  // The time precision travels as femtoseconds per tick, matching the design
  // attribute, so a host can render ticks without knowing anything else.
  int64_t precisionFs = 1;
  module.walk([&](sim::SimDesignOp design) {
    if (auto attr = design->getAttrOfType<IntegerAttr>("time_precision_fs"))
      precisionFs = attr.getInt();
  });
  std::string rootSpawnName = root.getSymName().str();
  rootSpawnName += ".__talos_spawn";
  MLIRContext *context = module.getContext();
  OpBuilder builder(context);
  builder.setInsertionPointToEnd(module.getBody());
  Location location = module.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i32 = builder.getI32Type();
  Type i64 = builder.getI64Type();
  Type voidType = LLVM::LLVMVoidType::get(context);
  auto main = LLVM::LLVMFuncOp::create(
      builder, location, "main",
      LLVM::LLVMFunctionType::get(i32, {i32, pointer}, false));
  Block *entry = main.addEntryBlock(builder);
  builder.setInsertionPointToStart(entry);
  Block *ready = new Block;
  Block *failed = new Block;
  main.getBody().push_back(ready);
  main.getBody().push_back(failed);
  Value one = llvmConstant(builder, location, i64, 1);
  Value outContext =
      LLVM::AllocaOp::create(builder, location, pointer, pointer, one, 8);
  LLVM::StoreOp::create(builder, location,
                        LLVM::ZeroOp::create(builder, location, pointer),
                        outContext, 8);
  constexpr StringLiteral executionName = "__talos_execution_descriptor_v1";
  bool hasExecution = module.lookupSymbol(executionName) != nullptr;
  NativeRuntimeEntry createDesign = NativeRuntimeEntry::ContextCreateForDesign;
  uint64_t validatedChecksum = 0, validatedBits = 0;
  if (hasExecution && native::has<native::ClosedExecutable>(module) &&
      native::has<native::ReadableEvalState>(module)) {
    auto blob =
        module.lookupSymbol<LLVM::GlobalOp>("__talos_design_database_v1");
    auto bytes = blob && blob.getConstant()
                     ? dyn_cast_or_null<StringAttr>(blob.getValueOrNull())
                     : StringAttr{};
    if (bytes) {
      talos_rt_execution_descriptor_v1 descriptor{};
      descriptor.version = TALOS_RT_VERSION;
      descriptor.flags =
          static_cast<uint32_t>(runtime::getExecutionFlags(module));
      if (auto bits = runtime::get<runtime::StateBits>(module))
        descriptor.state_bit_count = bits.getUInt();
      descriptor.design_database =
          reinterpret_cast<const uint8_t *>(bytes.getValue().data());
      descriptor.design_database_size = bytes.getValue().size();
      // Validate the final serialized bytes and physical bounds with the
      // runtime validator. All names, relations and range checks are retained.
      if (talos_rt_v1_design_validate(&descriptor) != TALOS_RT_OK)
        return module.emitError(
            "embedded read-only design database failed validation");
      validatedBits = descriptor.state_bit_count;
      validatedChecksum = llvm::support::endian::read64le(
          descriptor.design_database +
          offsetof(talos_rt_design_database_header_v1, checksum));
      createDesign = NativeRuntimeEntry::ContextCreateEmbeddedRead;
    }
  }
  bool hasCoverage = runtime::has<runtime::CoverageSchemaBlob>(module);
  bool hasSAIF = saif::has<saif::Output>(module);
  // A functional schema is also required for covergroup methods used directly
  // by the language.  Its presence therefore does not imply that the user
  // requested persistent coverage output.  The preparation pipeline adds the
  // metrics attribute for explicit --coverage selection and for coverage
  // database system calls, which are the two opt-in persistence paths.
  uint32_t coveragePersistenceMask = 0;
  if (auto metrics = cov::get<cov::Metrics>(module)) {
    for (Attribute attribute : metrics) {
      auto metric = dyn_cast<StringAttr>(attribute);
      if (!metric)
        continue;
      coveragePersistenceMask |=
          llvm::StringSwitch<uint32_t>(metric.getValue())
              .Case("line", TALOS_RT_COVERAGE_PERSIST_LINE)
              .Case("toggle", TALOS_RT_COVERAGE_PERSIST_TOGGLE)
              .Case("functional", TALOS_RT_COVERAGE_PERSIST_FUNCTIONAL)
              .Case("assertion", TALOS_RT_COVERAGE_PERSIST_ASSERTION)
              .Case("fsm", TALOS_RT_COVERAGE_PERSIST_FSM)
              .Default(0);
    }
  }
  bool shouldDumpCoverage = hasCoverage && coveragePersistenceMask != 0;
  bool hasDesignBytecode = false;
  if (runtime::has<runtime::ExecutionFlagSet>(module)) {
    runtime::ExecutionFlags flags = runtime::getExecutionFlags(module);
    hasDesignBytecode = runtime::bitEnumContainsAll(
        flags, runtime::ExecutionFlags::HasBytecode);
  }
  // Observer capability is a source-level scheduling fact retained by the
  // plan even after evaluator functions acquire their native signatures.
  // IEEE 1800-2023 4.6(a), 9.4.2: observers may require the canonical
  // source-order publication image even after generated stores run ahead.
  // Keep that image for observation-capable designs. A closed eval design
  // without those readers can let all tiers address the generated storage.
  // A DPI export runs in its importing caller's call chain (IEEE 1800-2023
  // 35.5.3) and must see that caller's stores, which the shared storage
  // already holds; it needs no separate image.
  bool sharedNativeState = hasExecution && useAOT && directEval &&
                           stateLayout.bitCount && !hasObserver &&
                           !hasCoverage && !hasSAIF;
  // Shared packed storage uses the module's private zero-initialized planes.
  // A closed main can retain the loader's demand-zero backing on first entry.
  auto initializePlanes =
      sharedNativeState && native::has<native::ClosedExecutable>(module)
          ? NativeRuntimeEntry::NativeStateInitializeBSS
          : NativeRuntimeEntry::NativeStateInitialize;
  uint64_t linePointCount = 0;
  uint64_t toggleBitCount = 0;
  if (hasCoverage) {
    if (auto count = cov::get<cov::LinePointCount>(module))
      linePointCount = count.getValue().getZExtValue();
    if (auto count = cov::get<cov::ToggleBitCount>(module))
      toggleBitCount = count.getValue().getZExtValue();
  }
  bool requiresNativeStateSync =
      stateLayout.bitCount &&
      (hasDesignBytecode || hasSAIF || toggleBitCount != 0 ||
       stateLayout.directContinuous);
  bool bindStateSpecialization =
      (requiresNativeStateSync || sharedNativeState) &&
      !stateLayout.guardedHandles.empty();
  if (hasExecution) {
    Value execution =
        LLVM::AddressOfOp::create(builder, location, pointer, executionName);
    SmallVector<Value> args{execution, outContext};
    if (validatedChecksum) {
      args.push_back(llvmConstant(builder, location, i64, validatedChecksum));
      args.push_back(llvmConstant(builder, location, i64, validatedBits));
      args.push_back(llvmConstant(builder, location, i32, sharedNativeState));
    }
    auto create = LLVM::CallOp::create(
        builder, location, TypeRange{i32},
        getNativeRuntimeCallee(context, createDesign), args);
    Value succeeded = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, create.getResult(),
        llvmConstant(builder, location, i32, 0));
    LLVM::CondBrOp::create(builder, location, succeeded, ready, failed,
                           create.getResult());
  } else {
    auto create = LLVM::CallOp::create(
        builder, location, TypeRange{i32},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::ContextCreate),
        outContext);
    Value succeeded = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, create.getResult(),
        llvmConstant(builder, location, i32, 0));
    LLVM::CondBrOp::create(builder, location, succeeded, ready, failed,
                           create.getResult());
  }
  failed->addArgument(i32, location);
  builder.setInsertionPointToStart(failed);
  LLVM::ReturnOp::create(builder, location, failed->getArgument(0));

  builder.setInsertionPointToStart(ready);
  Value runtimeContext =
      LLVM::LoadOp::create(builder, location, pointer, outContext, 8);
  if (hasExecution &&
      !runtime::bitEnumContainsAny(runtime::getExecutionFlags(module),
                                   runtime::ExecutionFlags::VPIWrite) &&
      runtime::bitEnumContainsAll(
          runtime::getExecutionFlags(module),
          runtime::ExecutionFlags::VPIRead |
              runtime::ExecutionFlags::WaveformMetadata) &&
      mlir::failed(
          bindWaveformAliases(module, builder, stateLayout, runtimeContext)))
    return failure();
  auto initializers =
      module.lookupSymbol<LLVM::GlobalOp>("__talos_state_initializers_v1");
  if (!initializers)
    return module.emitError("native state initializers are missing");
  uint64_t fillCount =
      cast<LLVM::LLVMArrayType>(initializers.getGlobalType()).getNumElements() /
      4;
  auto initialized = LLVM::CallOp::create(
      builder, location, TypeRange{i32},
      getNativeRuntimeCallee(context, initializePlanes),
      ValueRange{runtimeContext,
                 detail::createStatePlaneAddress(builder, location,
                                                 schedule::StatePlane::Value),
                 detail::createStatePlaneAddress(builder, location,
                                                 schedule::StatePlane::Unknown),
                 llvmConstant(builder, location, i64, stateLayout.bitCount),
                 LLVM::AddressOfOp::create(builder, location, pointer,
                                           initializers.getSymName()),
                 llvmConstant(builder, location, i64, fillCount)});
  Block *initializedReady = new Block, *initializeFailed = new Block;
  main.getBody().push_back(initializedReady);
  main.getBody().push_back(initializeFailed);
  LLVM::CondBrOp::create(
      builder, location,
      arith::CmpIOp::create(builder, location, arith::CmpIPredicate::eq,
                            initialized.getResult(),
                            llvmConstant(builder, location, i32, 0)),
      initializedReady, initializeFailed);
  builder.setInsertionPointToStart(initializeFailed);
  LLVM::CallOp::create(
      builder, location, TypeRange{},
      getNativeRuntimeCallee(context, NativeRuntimeEntry::ContextDestroy),
      runtimeContext);
  LLVM::ReturnOp::create(builder, location, initialized.getResult());
  builder.setInsertionPointToStart(initializedReady);
  if (sharedNativeState) {
    Value value = detail::createStatePlaneAddress(builder, location,
                                                  schedule::StatePlane::Value);
    Value unknown = detail::createStatePlaneAddress(
        builder, location, schedule::StatePlane::Unknown);
    Value status = LLVM::CallOp::create(
                       builder, location, TypeRange{i32},
                       getNativeRuntimeCallee(
                           context, NativeRuntimeEntry::NativeStateBindShared),
                       ValueRange{runtimeContext, value, unknown,
                                  llvmConstant(builder, location, i64,
                                               stateLayout.bitCount)})
                       .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  runtime::Features features = runtime::getFeatures(module);
  auto needs = [&](runtime::Features feature) {
    return runtime::bitEnumContainsAll(features, feature);
  };
  bool requiresDynamicScanFeature = needs(runtime::Features::DynamicScan);
  bool requiresEventSnapshotFeature = needs(runtime::Features::EventSnapshots);
  bool requiresContainerBitstreamFeature =
      needs(runtime::Features::ContainerBitstream);
  bool requiresRecursiveBitstreamFeature =
      needs(runtime::Features::RecursiveBitstream);
  bool requiresClassBitstreamFeature = needs(runtime::Features::ClassBitstream);
  bool requiresClassBitstreamBytecodeFeature =
      needs(runtime::Features::ClassBitstreamBytecode);
  bool requiresDPIExportBytecodeFeature =
      needs(runtime::Features::DPIExportBytecode);
  bool requiresDPIImportBytecodeFeature =
      needs(runtime::Features::DPIImportBytecode);
  if (requiresEventSnapshotFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::EventSnapshotLinkAnchor),
        ValueRange{});
  // Track cohorts from before the first activation. A design without cohort
  // queries leaves the scheduler's hooks disabled.
  if (needs(runtime::Features::SchedulerCohort))
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::SchedulerTrackCohorts),
        ValueRange{runtimeContext});
  if (requiresDynamicScanFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::DynamicScanLinkAnchor),
        ValueRange{});
  if (requiresContainerBitstreamFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(
            context, NativeRuntimeEntry::ContainerBitstreamLinkAnchor),
        ValueRange{});
  if (requiresRecursiveBitstreamFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(
            context, NativeRuntimeEntry::RecursiveBitstreamLinkAnchor),
        ValueRange{});
  if (requiresClassBitstreamFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::ClassBitstreamLinkAnchor),
        ValueRange{});
  if (requiresClassBitstreamBytecodeFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(
            context, NativeRuntimeEntry::ClassBitstreamBytecodeLinkAnchor),
        ValueRange{});
  if (requiresDPIExportBytecodeFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::DpiExportBytecodeLinkAnchor),
        ValueRange{});
  if (requiresDPIImportBytecodeFeature)
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::DpiImportBytecodeLinkAnchor),
        ValueRange{});
  Value configureStatus =
      LLVM::CallOp::create(
          builder, location, TypeRange{i32},
          getNativeRuntimeCallee(context,
                                 NativeRuntimeEntry::ContextConfigureArgv),
          ValueRange{runtimeContext, entry->getArgument(0),
                     entry->getArgument(1)})
          .getResult();
  LLVM::CallOp::create(
      builder, location, TypeRange{},
      getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
      ValueRange{runtimeContext, configureStatus});
  Value currentAddress = LLVM::AddressOfOp::create(builder, location, pointer,
                                                   "__talos_current_context");
  LLVM::StoreOp::create(builder, location, runtimeContext, currentAddress, 8);
  SmallVector<sim::SimClassDeclOp> managedClasses;
  module.walk([&](sim::SimClassDeclOp declaration) {
    managedClasses.push_back(declaration);
  });
  llvm::sort(managedClasses,
             [](auto lhs, auto rhs) { return lhs.getId() < rhs.getId(); });
  for (sim::SimClassDeclOp declaration : managedClasses) {
    Value descriptor = LLVM::AddressOfOp::create(
        builder, location, pointer,
        managedClassDescriptorName(
            FlatSymbolRefAttr::get(context, declaration.getSymName())));
    Value status =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            getNativeRuntimeCallee(context, NativeRuntimeEntry::ClassRegister),
            ValueRange{runtimeContext, descriptor})
            .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  // Element defaults must precede the first container of their type, which
  // the root initializer may already create.
  if (ArrayAttr defaults = native::get<native::ElementDefaults>(module))
    for (auto entry : defaults.getAsRange<native::ElementDefaultAttr>()) {
      ArrayRef<int8_t> image = entry.getImage().asArrayRef();
      std::string name =
          "__talos_element_default_" + std::to_string(entry.getTypeId());
      if (!module.lookupSymbol(name)) {
        OpBuilder::InsertionGuard guard(builder);
        builder.setInsertionPointToEnd(module.getBody());
        LLVM::GlobalOp::create(
            builder, location,
            LLVM::LLVMArrayType::get(builder.getI8Type(), image.size()),
            /*isConstant=*/true, LLVM::Linkage::Internal, name,
            builder.getStringAttr(StringRef(
                reinterpret_cast<const char *>(image.data()), image.size())),
            1);
      }
      Value status =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              getNativeRuntimeCallee(
                  context, NativeRuntimeEntry::ElementTypeDefineDefault),
              ValueRange{
                  runtimeContext,
                  LLVM::ConstantOp::create(
                      builder, location, i64,
                      builder.getI64IntegerAttr(
                          static_cast<int64_t>(entry.getTypeId()))),
                  LLVM::AddressOfOp::create(builder, location, pointer, name),
                  LLVM::ConstantOp::create(
                      builder, location, i64,
                      builder.getI64IntegerAttr(
                          static_cast<int64_t>(image.size())))})
              .getResult();
      LLVM::CallOp::create(
          builder, location, TypeRange{},
          getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
          ValueRange{runtimeContext, status});
    }
  if (requiresClassBitstreamFeature) {
    Value status = LLVM::CallOp::create(
                       builder, location, TypeRange{i32},
                       getNativeRuntimeCallee(
                           context, NativeRuntimeEntry::ClassBitstreamFinalize),
                       ValueRange{runtimeContext})
                       .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  SmallVector<LLVM::LLVMFuncOp> dpiThunks;
  ::talos::detail::walkNativeFunctions<LLVM::LLVMFuncOp>(
      module, [&](LLVM::LLVMFuncOp function) {
        if (dpi::has<dpi::ImportId>(function))
          dpiThunks.push_back(function);
      });
  llvm::sort(dpiThunks, [](LLVM::LLVMFuncOp lhs, LLVM::LLVMFuncOp rhs) {
    return dpi::get<dpi::ImportId>(lhs).getInt() <
           dpi::get<dpi::ImportId>(rhs).getInt();
  });
  for (LLVM::LLVMFuncOp thunk : dpiThunks) {
    auto importID = dpi::get<dpi::ImportId>(thunk);
    auto abiHash = dpi::get<dpi::ABIHash>(thunk);
    if (!abiHash)
      return thunk.emitError("DPI thunk is missing its ABI signature hash");
    Value callback = LLVM::AddressOfOp::create(builder, location, pointer,
                                               thunk.getSymName());
    Value userData = LLVM::ZeroOp::create(builder, location, pointer);
    Value status =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            getNativeRuntimeCallee(
                context, NativeRuntimeEntry::ContextRegisterImportSignature),
            ValueRange{runtimeContext,
                       llvmConstant(builder, location, i32,
                                    importID.getValue().getZExtValue()),
                       llvmConstant(builder, location, i64,
                                    abiHash.getValue().getZExtValue()),
                       callback, userData})
            .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  auto emitBoundRegistration =
      [&](OpBuilder &builder, Value runtimeContext,
          const NativeStateLayout::Bound &bound) -> LogicalResult {
    auto status = LLVM::CallOp::create(
        builder, location, TypeRange{i32},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::NativeStateRegisterStatic),
        ValueRange{runtimeContext,
                   llvmConstant(builder, location, i32, bound.handleID),
                   llvmConstant(builder, location, i64, bound.offset),
                   llvmConstant(builder, location, i64, bound.width)});
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status.getResult()});
    for (const sim::ManagedHandleSlot &root : bound.managedRootSlots) {
      uint64_t rootOffset = root.bitOffset;
      if ((bound.offset + rootOffset) & 7)
        return module.emitError("managed static root is not byte aligned");
      Value state = detail::createStatePlaneAddress(
          builder, location, schedule::StatePlane::Value);
      Value slot =
          byteGEP(builder, location, state, (bound.offset + rootOffset) / 8);
      SmallVector<Value> rootArguments{
          runtimeContext, slot,
          llvmConstant(builder, location, i32, root.kindMask)};
      Value rootStatus =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              getNativeRuntimeCallee(
                  context, NativeRuntimeEntry::GcCandidateStaticRootRegister),
              rootArguments)
              .getResult();
      LLVM::CallOp::create(
          builder, location, TypeRange{},
          getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
          ValueRange{runtimeContext, rootStatus});
      if (hasDesignBytecode && !sharedNativeState) {
        SmallVector<Value> designRootArguments{
            runtimeContext,
            llvmConstant(builder, location, i64, bound.offset + rootOffset),
            llvmConstant(builder, location, i32, root.kindMask)};
        Value designRootStatus =
            LLVM::CallOp::create(
                builder, location, TypeRange{i32},
                getNativeRuntimeCallee(
                    context, NativeRuntimeEntry::GcDesignCandidateRootRegister),
                designRootArguments)
                .getResult();
        LLVM::CallOp::create(
            builder, location, TypeRange{},
            getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
            ValueRange{runtimeContext, designRootStatus});
      }
    }
    return success();
  };
  // Registration is ordered initialization, not a scheduling boundary. Keep
  // large designs from producing a single basic block with tens of thousands
  // of calls (and quadratic register-allocation work). The helpers preserve
  // each bound's registration, managed roots and status reporting in place.
  constexpr size_t registrationBatchSize = 256;
  if (stateLayout.bounds.size() <= registrationBatchSize) {
    for (const NativeStateLayout::Bound &bound : stateLayout.bounds)
      if (mlir::failed(emitBoundRegistration(builder, runtimeContext, bound)))
        return failure();
  } else {
    // Large designs register from two constant tables in one loop: bounds
    // {handle, end of its roots, bit offset, width} and managed roots {byte
    // offset, kind mask}. The order of runtime calls and their status checks
    // is the same as the unrolled form, without a call sequence per bound.
    auto boundType =
        LLVM::LLVMStructType::getLiteral(context, {i32, i32, i64, i64});
    auto rootType = LLVM::LLVMStructType::getLiteral(context, {i64, i32, i32});
    SmallVector<Attribute> boundRows, rootRows;
    boundRows.reserve(stateLayout.bounds.size());
    for (const NativeStateLayout::Bound &bound : stateLayout.bounds) {
      for (const sim::ManagedHandleSlot &root : bound.managedRootSlots) {
        uint64_t bit = bound.offset + root.bitOffset;
        if (bit & 7)
          return module.emitError("managed static root is not byte aligned");
        rootRows.push_back(
            integerStructAttr(rootType, {bit / 8, root.kindMask, 0}));
      }
      boundRows.push_back(
          integerStructAttr(boundType, {bound.handleID, rootRows.size(),
                                        bound.offset, bound.width}));
    }
    constexpr StringLiteral boundsName = "__talos_static_state_bounds_v1";
    constexpr StringLiteral rootsName = "__talos_static_state_roots_v1";
    makeConstantGlobal(module, location,
                       LLVM::LLVMArrayType::get(boundType, boundRows.size()),
                       boundsName, LLVM::Linkage::Internal, 8,
                       ArrayAttr::get(context, boundRows));
    makeConstantGlobal(module, location,
                       LLVM::LLVMArrayType::get(rootType, rootRows.size()),
                       rootsName, LLVM::Linkage::Internal, 8,
                       ArrayAttr::get(context, rootRows));
    LLVM::LLVMFuncOp helper;
    {
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPointToEnd(module.getBody());
      helper = LLVM::LLVMFuncOp::create(
          builder, location, "__talos_register_static_state",
          LLVM::LLVMFunctionType::get(voidType, {pointer}, false),
          LLVM::Linkage::Internal);
      helper.setNoInline(true);
      Block *entry = helper.addEntryBlock(builder);
      Value helperContext = entry->getArgument(0);
      Region &body = helper.getBody();
      auto *boundHeader = new Block, *boundBody = new Block,
           *rootHeader = new Block, *rootBody = new Block, *exit = new Block;
      for (Block *block : {boundHeader, boundBody, rootHeader, rootBody, exit})
        body.push_back(block);
      Value bound = boundHeader->addArgument(i64, location);
      Value firstRoot = boundHeader->addArgument(i64, location);
      Value root = rootHeader->addArgument(i64, location);
      Value nextBound = rootHeader->addArgument(i64, location);
      Value rootEnd = rootHeader->addArgument(i64, location);
      auto fail = [&](Value status) {
        LLVM::CallOp::create(
            builder, location, TypeRange{},
            getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
            ValueRange{helperContext, status});
      };
      auto field = [&](StringRef table, Type rowType, Value row, int32_t index,
                       Type type) -> Value {
        Value address = LLVM::GEPOp::create(
            builder, location, pointer, rowType,
            LLVM::AddressOfOp::create(builder, location, pointer, table),
            ArrayRef<LLVM::GEPArg>{row, index});
        return LLVM::LoadOp::create(builder, location, type, address,
                                    type == i64 ? 8 : 4);
      };

      builder.setInsertionPointToStart(entry);
      Value zero = llvmConstant(builder, location, i64, 0);
      LLVM::BrOp::create(builder, location, ValueRange{zero, zero},
                         boundHeader);

      builder.setInsertionPointToStart(boundHeader);
      Value more = LLVM::ICmpOp::create(
          builder, location, LLVM::ICmpPredicate::ult, bound,
          llvmConstant(builder, location, i64, boundRows.size()));
      LLVM::CondBrOp::create(builder, location, more, boundBody, exit);

      builder.setInsertionPointToStart(boundBody);
      Value status =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              getNativeRuntimeCallee(
                  context, NativeRuntimeEntry::NativeStateRegisterStatic),
              ValueRange{helperContext,
                         field(boundsName, boundType, bound, 0, i32),
                         field(boundsName, boundType, bound, 2, i64),
                         field(boundsName, boundType, bound, 3, i64)})
              .getResult();
      fail(status);
      Value end = LLVM::ZExtOp::create(
          builder, location, i64, field(boundsName, boundType, bound, 1, i32));
      Value following = LLVM::AddOp::create(
          builder, location, bound, llvmConstant(builder, location, i64, 1));
      LLVM::BrOp::create(builder, location,
                         ValueRange{firstRoot, following, end}, rootHeader);

      builder.setInsertionPointToStart(rootHeader);
      Value rootsLeft = LLVM::ICmpOp::create(
          builder, location, LLVM::ICmpPredicate::ult, root, rootEnd);
      LLVM::CondBrOp::create(builder, location, rootsLeft, rootBody,
                             ValueRange{}, boundHeader,
                             ValueRange{nextBound, rootEnd});

      builder.setInsertionPointToStart(rootBody);
      Value byte = field(rootsName, rootType, root, 0, i64);
      Value kind = field(rootsName, rootType, root, 1, i32);
      Value slot = schedule::NativeStateWindowAddressOp::create(
          builder, location, schedule::StatePlane::Value, byte, 0);
      fail(LLVM::CallOp::create(
               builder, location, TypeRange{i32},
               getNativeRuntimeCallee(
                   context, NativeRuntimeEntry::GcCandidateStaticRootRegister),
               ValueRange{helperContext, slot, kind})
               .getResult());
      if (hasDesignBytecode && !sharedNativeState) {
        Value bit = LLVM::ShlOp::create(
            builder, location, byte, llvmConstant(builder, location, i64, 3));
        fail(
            LLVM::CallOp::create(
                builder, location, TypeRange{i32},
                getNativeRuntimeCallee(
                    context, NativeRuntimeEntry::GcDesignCandidateRootRegister),
                ValueRange{helperContext, bit, kind})
                .getResult());
      }
      Value nextRoot = LLVM::AddOp::create(
          builder, location, root, llvmConstant(builder, location, i64, 1));
      LLVM::BrOp::create(builder, location,
                         ValueRange{nextRoot, nextBound, rootEnd}, rootHeader);

      builder.setInsertionPointToStart(exit);
      LLVM::ReturnOp::create(builder, location, ValueRange{});
    }
    LLVM::CallOp::create(builder, location, TypeRange{},
                         SymbolRefAttr::get(context, helper.getSymName()),
                         ValueRange{runtimeContext});
  }
  if (requiresNativeStateSync) {
    Value stateValue = detail::createStatePlaneAddress(
        builder, location, schedule::StatePlane::Value);
    Value stateUnknown = detail::createStatePlaneAddress(
        builder, location, schedule::StatePlane::Unknown);
    Value status = LLVM::CallOp::create(
                       builder, location, TypeRange{i32},
                       getNativeRuntimeCallee(
                           context, NativeRuntimeEntry::NativeStateSync),
                       ValueRange{runtimeContext, stateValue, stateUnknown,
                                  llvmConstant(builder, location, i64,
                                               stateLayout.bitCount)})
                       .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  if (stateLayout.directContinuous) {
    SmallVector<Value> arguments{runtimeContext};
    // The runtime binds each contribution plane's pointer global.
    for (schedule::StatePlane plane :
         {schedule::StatePlane::ContributionValue,
          schedule::StatePlane::ContributionUnknown,
          schedule::StatePlane::ContributionMask})
      arguments.push_back(
          LLVM::AddressOfOp::create(builder, location, pointer,
                                    schedule::getStatePlaneGlobalName(plane)));
    Value status =
        LLVM::CallOp::create(builder, location, TypeRange{i32},
                             getNativeRuntimeSymbol(
                                 NativeRuntimeEntry::NativeStateBindContinuous),
                             arguments)
            .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  if (!stateLayout.unknownSummaryRoots.empty()) {
    auto address = [&](StringRef name) -> Value {
      return LLVM::AddressOfOp::create(builder, location, pointer, name);
    };
    Value status =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            getNativeRuntimeSymbol(
                NativeRuntimeEntry::NativeStateBindUnknownSummary),
            ValueRange{
                runtimeContext,
                detail::createStatePlaneAddress(builder, location,
                                                schedule::StatePlane::Unknown),
                llvmConstant(builder, location, i64, stateLayout.bitCount),
                address(unknownSummaryName), address(unknownSummaryRootsName),
                llvmConstant(builder, location, i64,
                             stateLayout.unknownSummaryRoots.size()),
                address(unknownSummaryPatternsName),
                llvmConstant(builder, location, i64,
                             stateLayout.getUnknownSummaryPatternCount())})
            .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  if (bindStateSpecialization) {
    Value fast = LLVM::AddressOfOp::create(
        builder, location, pointer, "__talos_state_specialization_fast_v1");
    Value status = LLVM::CallOp::create(
                       builder, location, TypeRange{i32},
                       getNativeRuntimeSymbol(
                           NativeRuntimeEntry::NativeStateBindSpecialization),
                       ValueRange{runtimeContext, fast})
                       .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
  }
  if (hasCoverage) {
    struct ToggleBinding {
      uint64_t firstBit;
      uint64_t bitCount;
      uint64_t stateHandle;
    };
    SmallVector<ToggleBinding> toggleBindings;
    struct FsmBinding {
      uint64_t machine;
      uint64_t shift;
      uint64_t bitCount;
      uint64_t stateHandle;
    };
    SmallVector<FsmBinding> fsmBindings;
    auto collectToggleBindings = [&](Operation *operation, uint64_t id,
                                     const auto &handles) -> LogicalResult {
      if (auto values = cov::get<cov::FsmBindings>(operation)) {
        auto handle = handles.find(id);
        if (handle == handles.end())
          return operation->emitError(
              "FSM state vector has no native state handle");
        for (Attribute value : values) {
          auto binding = cast<cov::FsmBindingAttr>(value);
          uint64_t stateHandle =
              talos_rt_stable_handle_offset(handle->second, binding.getLow());
          if (stateHandle == UINT64_MAX)
            return operation->emitError(
                "FSM coverage binding cannot be represented by a stable state "
                "handle");
          fsmBindings.push_back({binding.getMachine(), binding.getShift(),
                                 binding.getWidth(), stateHandle});
        }
      }
      auto values = cov::get<cov::ToggleBindings>(operation);
      if (!values)
        return success();
      auto handle = handles.find(id);
      if (handle == handles.end())
        return operation->emitError(
            "covered declaration has no native state handle");
      for (Attribute value : values) {
        auto binding = dyn_cast<cov::ToggleBindingAttr>(value);
        if (!binding || binding.getLow() < 0 || binding.getWidth() == 0)
          return operation->emitError("has invalid toggle coverage binding");
        uint64_t firstBit = binding.getBase();
        uint64_t bitCount = binding.getWidth();
        if (firstBit > toggleBitCount || bitCount > toggleBitCount - firstBit)
          return operation->emitError(
              "toggle coverage binding exceeds the prepared inventory");
        uint64_t stateHandle =
            talos_rt_stable_handle_offset(handle->second, binding.getLow());
        if (stateHandle == UINT64_MAX)
          return operation->emitError(
              "toggle coverage binding cannot be represented by a stable "
              "state handle");
        toggleBindings.push_back({firstBit, bitCount, stateHandle});
      }
      return success();
    };
    WalkResult collected = module.walk([&](Operation *operation) -> WalkResult {
      LogicalResult result = success();
      if (auto storage = dyn_cast<sim::SimStorageDeclOp>(operation))
        result = collectToggleBindings(operation, storage.getId(),
                                       stateLayout.storage);
      else if (auto net = dyn_cast<sim::SimNetDeclOp>(operation))
        result =
            collectToggleBindings(operation, net.getId(), stateLayout.nets);
      return mlir::failed(result) ? WalkResult::interrupt()
                                  : WalkResult::advance();
    });
    if (collected.wasInterrupted())
      return failure();
    llvm::sort(toggleBindings,
               [](const ToggleBinding &lhs, const ToggleBinding &rhs) {
                 return lhs.firstBit < rhs.firstBit;
               });
    Value null = LLVM::ZeroOp::create(builder, location, pointer);
    Value initialValue = null;
    Value initialUnknown = null;
    if (toggleBitCount) {
      auto valueBytes = cov::get<cov::ToggleInitialValue>(module);
      auto unknownBytes = cov::get<cov::ToggleInitialUnknown>(module);
      const uint64_t expectedBytes = (toggleBitCount + 7) / 8;
      if (!valueBytes || !unknownBytes ||
          static_cast<uint64_t>(valueBytes.size()) != expectedBytes ||
          static_cast<uint64_t>(unknownBytes.size()) != expectedBytes)
        return module.emitError(
            "toggle coverage inventory has invalid initial shadow planes");
      auto asString = [](DenseI8ArrayAttr bytes) {
        ArrayRef<int8_t> data = bytes.asArrayRef();
        return StringRef(reinterpret_cast<const char *>(data.data()),
                         data.size());
      };
      LLVM::GlobalOp valueGlobal = makeByteArrayGlobal(
          module, location, "__talos_coverage_initial_value_v1",
          asString(valueBytes));
      LLVM::GlobalOp unknownGlobal = makeByteArrayGlobal(
          module, location, "__talos_coverage_initial_unknown_v1",
          asString(unknownBytes));
      initialValue = LLVM::AddressOfOp::create(builder, location, pointer,
                                               valueGlobal.getSymName());
      initialUnknown = LLVM::AddressOfOp::create(builder, location, pointer,
                                                 unknownGlobal.getSymName());
    }
    Value status =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            getNativeRuntimeCallee(context,
                                   NativeRuntimeEntry::CoverageFinalize),
            ValueRange{
                runtimeContext,
                llvmConstant(builder, location, i64, linePointCount),
                llvmConstant(builder, location, i64, toggleBitCount),
                initialValue, initialUnknown,
                llvmConstant(builder, location, i32, coveragePersistenceMask)})
            .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, status});
    for (const ToggleBinding &binding : toggleBindings) {
      Value bindStatus =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              getNativeRuntimeCallee(context,
                                     NativeRuntimeEntry::CoverageToggleBind),
              ValueRange{
                  runtimeContext,
                  llvmConstant(builder, location, i64, binding.firstBit),
                  llvmConstant(builder, location, i64, binding.bitCount),
                  llvmConstant(builder, location, i64, binding.stateHandle)})
              .getResult();
      LLVM::CallOp::create(
          builder, location, TypeRange{},
          getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
          ValueRange{runtimeContext, bindStatus});
    }
    for (const FsmBinding &binding : fsmBindings) {
      Value bindStatus =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              getNativeRuntimeCallee(context,
                                     NativeRuntimeEntry::CoverageFsmBind),
              ValueRange{
                  runtimeContext,
                  llvmConstant(builder, location, i64, binding.machine),
                  llvmConstant(builder, location, i64, binding.shift),
                  llvmConstant(builder, location, i64, binding.bitCount),
                  llvmConstant(builder, location, i64, binding.stateHandle)})
              .getResult();
      LLVM::CallOp::create(
          builder, location, TypeRange{},
          getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
          ValueRange{runtimeContext, bindStatus});
    }
    Value sealStatus = LLVM::CallOp::create(
                           builder, location, TypeRange{i32},
                           getNativeRuntimeCallee(
                               context, NativeRuntimeEntry::CoverageToggleSeal),
                           ValueRange{runtimeContext})
                           .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, sealStatus});
  }
  if (hasSAIF &&
      mlir::failed(materializeSAIFRegistration(module, builder, runtimeContext,
                                               stateLayout, precisionFs)))
    return failure();
  if (useAOT) {
    Value plan = LLVM::AddressOfOp::create(builder, location, pointer,
                                           "__talos_aot_schedule_plan_v1");
    Value installStatus =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            getNativeRuntimeCallee(context,
                                   NativeRuntimeEntry::SchedulerInstallAot),
            ValueRange{runtimeContext, plan})
            .getResult();
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerFail),
        ValueRange{runtimeContext, installStatus});
  }
  // The driver asks for the startup steps; they run before the root process
  // spawns (IEEE 1800-2023 36.10.2: VPI startup routines and cbEndOfCompile
  // precede simulation).
  bool startupVPI = native::has<native::StartupVpi>(module);
  if (startupVPI || native::has<native::StartupStateSync>(module)) {
    auto stateBits = runtime::get<runtime::StateBits>(module);
    auto start = schedule::NativeLifecycleStartOp::create(
        builder, location,
        builder.getI64IntegerAttr(stateBits ? stateBits.getUInt() : 0));
    start.setStateSync(native::has<native::StartupStateSync>(module));
    start.setResolveInitialDrivers(
        native::has<native::StartupResolveInitialDrivers>(module));
    start.setVpi(startupVPI);
  }
  LLVM::CallOp::create(builder, location, TypeRange{i64},
                       SymbolRefAttr::get(context, rootSpawnName),
                       runtimeContext);
  auto run = LLVM::CallOp::create(
      builder, location, TypeRange{i32},
      SymbolRefAttr::get(
          context,
          useAOT ? getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerRunAot)
                 : getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerRun)),
      runtimeContext);
  // Capture the design's own notion of elapsed time while the context that
  // holds it still exists. A host has no other channel: once main returns, the
  // context is gone and the module exposes nothing but its exports.
  auto finalTime = LLVM::CallOp::create(
      builder, location, TypeRange{i64},
      getNativeRuntimeCallee(context, NativeRuntimeEntry::SchedulerTime),
      runtimeContext);
  LLVM::StoreOp::create(
      builder, location, finalTime.getResult(),
      LLVM::AddressOfOp::create(builder, location, pointer, kFinalTimeName));
  // Report the simulation result before snapshot I/O can replace the
  // thread-local diagnostic.  If both fail, the simulation remains the exit
  // status and each failure is described by the operation that produced it.
  auto lastReport = LLVM::CallOp::create(
      builder, location, TypeRange{},
      getNativeRuntimeCallee(context,
                             NativeRuntimeEntry::SchedulerReportStatus),
      ValueRange{runtimeContext, run.getResult()});
  Value finalStatus = run.getResult();
  Value coverageStatus;
  if (shouldDumpCoverage) {
    coverageStatus =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            getNativeRuntimeCallee(context,
                                   NativeRuntimeEntry::CoverageSnapshot),
            ValueRange{runtimeContext, run.getResult(), finalTime.getResult()})
            .getResult();
    Value runSucceeded = LLVM::ICmpOp::create(
        builder, location, LLVM::ICmpPredicate::eq, run.getResult(),
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    finalStatus = LLVM::SelectOp::create(builder, location, runSucceeded,
                                         coverageStatus, run.getResult());
    lastReport = LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeCallee(context,
                               NativeRuntimeEntry::SchedulerReportStatus),
        ValueRange{runtimeContext, coverageStatus});
  }
  if (hasSAIF) {
    Value status = LLVM::CallOp::create(
                       builder, location, TypeRange{i32},
                       getNativeRuntimeSymbol(NativeRuntimeEntry::SaifFinish),
                       runtimeContext)
                       .getResult();
    Value succeeded = LLVM::ICmpOp::create(
        builder, location, LLVM::ICmpPredicate::eq, finalStatus,
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    finalStatus = LLVM::SelectOp::create(builder, location, succeeded, status,
                                         finalStatus);
    lastReport = LLVM::CallOp::create(
        builder, location, TypeRange{},
        getNativeRuntimeSymbol(NativeRuntimeEntry::SchedulerReportStatus),
        ValueRange{runtimeContext, status});
  }
  if (startupVPI) {
    // cbEndOfSimulation runs before the last status report (IEEE 1800-2023
    // 38.36.3). Its status is the result unless the reported one failed.
    {
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPoint(lastReport);
      finalStatus = schedule::NativeLifecycleFinishOp::create(
          builder, location, i32, runtimeContext,
          lastReport.getArgOperands()[1]);
      lastReport.getArgOperandsMutable()[1].set(finalStatus);
    }
    schedule::NativeLifecycleShutdownOp::create(builder, location,
                                                runtimeContext);
  }
  LLVM::CallOp::create(
      builder, location, TypeRange{},
      getNativeRuntimeCallee(context, NativeRuntimeEntry::ContextDestroy),
      runtimeContext);
  LLVM::ReturnOp::create(builder, location, finalStatus);

  // Storage for the captured time, plus the two accessors a host calls after
  // main has returned. The precision is a compile-time constant, but it has to
  // travel with the module: without it the raw tick count cannot be rendered
  // as a time.
  builder.setInsertionPointToEnd(module.getBody());
  LLVM::GlobalOp::create(builder, location, i64, /*isConstant=*/false,
                         LLVM::Linkage::Internal, kFinalTimeName,
                         builder.getI64IntegerAttr(0));
  auto defineAccessor = [&](StringRef name, function_ref<Value()> emitValue) {
    auto accessor = LLVM::LLVMFuncOp::create(
        builder, location, name, LLVM::LLVMFunctionType::get(i64, {}, false));
    OpBuilder::InsertionGuard guard(builder);
    builder.setInsertionPointToStart(accessor.addEntryBlock(builder));
    LLVM::ReturnOp::create(builder, location, emitValue());
  };
  defineAccessor(kFinalTimeAccessorName, [&]() -> Value {
    Value address =
        LLVM::AddressOfOp::create(builder, location, pointer, kFinalTimeName);
    return LLVM::LoadOp::create(builder, location, i64, address);
  });
  defineAccessor(kTimePrecisionAccessorName, [&]() -> Value {
    return LLVM::ConstantOp::create(builder, location, i64,
                                    builder.getI64IntegerAttr(precisionFs));
  });
  declareNativeRuntime(module, NativeRuntimeEntry::SchedulerTime);

  if (hasExecution)
    declareNativeRuntime(module, createDesign);
  else
    declareNativeRuntime(module, NativeRuntimeEntry::ContextCreate);
  declareNativeRuntimes(module,
                        {initializePlanes, NativeRuntimeEntry::ContextDestroy,
                         NativeRuntimeEntry::ContextConfigureArgv,
                         NativeRuntimeEntry::NativeStateRegisterStatic});
  if (requiresNativeStateSync)
    declareNativeRuntime(module, NativeRuntimeEntry::NativeStateSync);
  if (sharedNativeState)
    declareNativeRuntime(module, NativeRuntimeEntry::NativeStateBindShared);
  if (bindStateSpecialization)
    declareNativeRuntime(module,
                         NativeRuntimeEntry::NativeStateBindSpecialization);
  if (stateLayout.directContinuous)
    declareNativeRuntime(module, NativeRuntimeEntry::NativeStateBindContinuous);
  if (!stateLayout.unknownSummaryRoots.empty())
    declareNativeRuntime(module,
                         NativeRuntimeEntry::NativeStateBindUnknownSummary);
  declareNativeRuntimes(module,
                        {NativeRuntimeEntry::GcStaticRootRegister,
                         NativeRuntimeEntry::GcCandidateStaticRootRegister,
                         NativeRuntimeEntry::GcDesignRootRegister,
                         NativeRuntimeEntry::GcDesignCandidateRootRegister,
                         NativeRuntimeEntry::ClassRegister,
                         NativeRuntimeEntry::ElementTypeDefineDefault,
                         NativeRuntimeEntry::ContextRegisterImportSignature,
                         NativeRuntimeEntry::SchedulerFail,
                         NativeRuntimeEntry::SchedulerRun,
                         NativeRuntimeEntry::SchedulerReportStatus});
  if (hasCoverage) {
    declareNativeRuntime(module, NativeRuntimeEntry::CoverageFinalize);
    declareNativeRuntime(module, NativeRuntimeEntry::CoverageToggleBind);
    declareNativeRuntime(module, NativeRuntimeEntry::CoverageFsmBind);
    declareNativeRuntime(module, NativeRuntimeEntry::CoverageToggleSeal);
  }
  if (shouldDumpCoverage)
    declareNativeRuntime(module, NativeRuntimeEntry::CoverageSnapshot);
  if (hasSAIF) {
    declareNativeRuntime(module, NativeRuntimeEntry::SaifConfigure);
    declareNativeRuntime(module, NativeRuntimeEntry::SaifBind);
    declareNativeRuntime(module, NativeRuntimeEntry::SaifDriver);
    declareNativeRuntime(module, NativeRuntimeEntry::SaifSeal);
    declareNativeRuntime(module, NativeRuntimeEntry::SaifFinish);
  }
  declareNativeRuntime(module, NativeRuntimeEntry::SchedulerInstallAot);
  declareNativeRuntime(module, NativeRuntimeEntry::SchedulerRunAot);
  if (requiresEventSnapshotFeature)
    declareNativeRuntime(module, NativeRuntimeEntry::EventSnapshotLinkAnchor);
  if (needs(runtime::Features::SchedulerCohort))
    declareNativeRuntime(module, NativeRuntimeEntry::SchedulerTrackCohorts);
  if (requiresDynamicScanFeature)
    declareNativeRuntime(module, NativeRuntimeEntry::DynamicScanLinkAnchor);
  if (requiresContainerBitstreamFeature)
    declareNativeRuntime(module,
                         NativeRuntimeEntry::ContainerBitstreamLinkAnchor);
  if (requiresRecursiveBitstreamFeature)
    declareNativeRuntime(module,
                         NativeRuntimeEntry::RecursiveBitstreamLinkAnchor);
  if (requiresClassBitstreamFeature)
    declareNativeRuntime(module, NativeRuntimeEntry::ClassBitstreamLinkAnchor);
  if (requiresClassBitstreamFeature)
    declareNativeRuntime(module, NativeRuntimeEntry::ClassBitstreamFinalize);
  if (requiresClassBitstreamBytecodeFeature)
    declareNativeRuntime(module,
                         NativeRuntimeEntry::ClassBitstreamBytecodeLinkAnchor);
  if (requiresDPIExportBytecodeFeature)
    declareNativeRuntime(module,
                         NativeRuntimeEntry::DpiExportBytecodeLinkAnchor);
  if (requiresDPIImportBytecodeFeature)
    declareNativeRuntime(module,
                         NativeRuntimeEntry::DpiImportBytecodeLinkAnchor);
  return success();
}

} // namespace talos::detail

namespace talos {

LogicalResult
lowerNativeStartupLifecycle(ModuleOp module,
                            ArrayRef<std::string> startupModules) {
  bool required = native::has<native::StartupStateSync>(module) ||
                  native::has<native::StartupVpi>(module);
  native::remove<native::StartupStateSync>(module);
  native::remove<native::StartupResolveInitialDrivers>(module);
  native::remove<native::StartupVpi>(module);
  auto main = module.lookupSymbol<LLVM::LLVMFuncOp>("main");
  schedule::NativeLifecycleStartOp start;
  SmallVector<schedule::NativeLifecycleFinishOp> finishes;
  SmallVector<schedule::NativeLifecycleShutdownOp> shutdowns;
  if (main)
    main.walk([&](Operation *operation) {
      if (auto op = dyn_cast<schedule::NativeLifecycleStartOp>(operation))
        start = op;
      else if (auto op = dyn_cast<schedule::NativeLifecycleFinishOp>(operation))
        finishes.push_back(op);
      else if (auto op =
                   dyn_cast<schedule::NativeLifecycleShutdownOp>(operation))
        shutdowns.push_back(op);
    });
  if (!required && !start)
    return success();
  auto current = module.lookupSymbol<LLVM::GlobalOp>("__talos_current_context");
  auto stateValue = module.lookupSymbol<LLVM::GlobalOp>(
      schedule::getStatePlaneGlobalName(schedule::StatePlane::Value));
  auto stateUnknown = module.lookupSymbol<LLVM::GlobalOp>(
      schedule::getStatePlaneGlobalName(schedule::StatePlane::Unknown));
  // The lifecycle names the context and the planes only by lookup. When the
  // driver prunes symbols before this lowering, it keeps them because the
  // generated main itself uses them: it stores the context and initializes the
  // planes before the startup steps. Name the one that is missing.
  if (!main)
    return module.emitError(
        "the startup lifecycle requires a generated scheduler main");
  if (!current)
    return module.emitError("the startup lifecycle requires the current "
                            "context global @__talos_current_context");
  if (!stateValue)
    return module.emitError("the startup lifecycle requires the native state "
                            "value plane @")
           << schedule::getStatePlaneGlobalName(schedule::StatePlane::Value);
  bool vpi = start && start.getVpi();
  if (!start || (vpi && (finishes.size() != 1 || shutdowns.size() != 1)))
    return module.emitError("generated scheduler lifecycle is incomplete");
  auto valueArray = dyn_cast<LLVM::LLVMArrayType>(stateValue.getGlobalType());
  auto unknownArray =
      stateUnknown ? dyn_cast<LLVM::LLVMArrayType>(stateUnknown.getGlobalType())
                   : LLVM::LLVMArrayType();
  if (!valueArray ||
      (stateUnknown && (!unknownArray || valueArray.getNumElements() !=
                                             unknownArray.getNumElements())))
    return module.emitError("generated native state planes disagree");
  if (start.getStateBits() > valueArray.getNumElements() * uint64_t{8})
    return module.emitError(
        "execution descriptor disagrees with generated native state planes");
  if (!stateUnknown &&
      !runtime::bitEnumContainsAll(runtime::getExecutionFlags(module),
                                   runtime::ExecutionFlags::TwoState))
    return module.emitError("four-state execution requires an unknown plane");

  MLIRContext *context = module.getContext();
  Location location = start.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(context);
  OpBuilder builder(context);
  Type i32 = builder.getI32Type();
  Type i64 = builder.getI64Type();
  // Startup library names and the runtime entries are appended after every
  // other symbol, in this order.
  OpBuilder atEnd = OpBuilder::atBlockEnd(module.getBody());
  SmallVector<LLVM::GlobalOp> names;
  for (auto [index, name] : llvm::enumerate(startupModules)) {
    std::string bytes = name;
    bytes.push_back('\0');
    auto global = LLVM::GlobalOp::create(
        atEnd, location,
        LLVM::LLVMArrayType::get(builder.getI8Type(), bytes.size()),
        /*isConstant=*/true, LLVM::Linkage::Private,
        ("__talos_vpi_module_" + Twine(index)).str(),
        atEnd.getStringAttr(bytes));
    global.setUnnamedAddr(LLVM::UnnamedAddr::Global);
    names.push_back(global);
  }
  LLVM::GlobalOp nameArray;
  if (!names.empty()) {
    auto arrayType = LLVM::LLVMArrayType::get(pointer, names.size());
    nameArray =
        LLVM::GlobalOp::create(atEnd, location, arrayType,
                               /*isConstant=*/true, LLVM::Linkage::Private,
                               "__talos_vpi_startup_modules", Attribute());
    OpBuilder initializer(context);
    initializer.setInsertionPointToStart(
        initializer.createBlock(&nameArray.getInitializerRegion()));
    Value array = LLVM::UndefOp::create(initializer, location, arrayType);
    for (auto [index, global] : llvm::enumerate(names))
      array = LLVM::InsertValueOp::create(
          initializer, location, array,
          LLVM::AddressOfOp::create(initializer, location, global),
          ArrayRef<int64_t>{static_cast<int64_t>(index)});
    LLVM::ReturnOp::create(initializer, location, array);
  }
  auto declare = [&](NativeRuntimeEntry entry) -> LLVM::LLVMFuncOp {
    if (auto existing = module.lookupSymbol<LLVM::LLVMFuncOp>(
            getNativeRuntimeSymbol(entry)))
      return existing;
    return createNativeRuntimeDeclaration(atEnd, location, entry);
  };
  LLVM::LLVMFuncOp fail = declare(NativeRuntimeEntry::SchedulerFail);

  builder.setInsertionPoint(start);
  Value runtimeContext = LLVM::LoadOp::create(
      builder, location, pointer,
      LLVM::AddressOfOp::create(builder, location, current), 8);
  auto check = [&](Value status) {
    LLVM::CallOp::create(builder, location, fail,
                         ValueRange{runtimeContext, status});
  };
  if (start.getStateSync()) {
    LLVM::LLVMFuncOp sync = declare(NativeRuntimeEntry::NativeStateSync);
    Value unknown =
        stateUnknown
            ? Value(LLVM::AddressOfOp::create(builder, location, stateUnknown))
            : Value(LLVM::ZeroOp::create(builder, location, pointer));
    check(
        LLVM::CallOp::create(
            builder, location, sync,
            ValueRange{runtimeContext,
                       LLVM::AddressOfOp::create(builder, location, stateValue),
                       unknown,
                       detail::llvmConstant(builder, location, i64,
                                            start.getStateBits())})
            .getResult());
  }
  if (start.getResolveInitialDrivers()) {
    LLVM::LLVMFuncOp resolve =
        declare(NativeRuntimeEntry::SchedulerResolveInitialDrivers);
    check(LLVM::CallOp::create(builder, location, resolve, runtimeContext)
              .getResult());
  }
  if (vpi) {
    // IEEE 1800-2023 36.9.1, 36.10.2: the startup routines register their
    // system tasks and callbacks; cbEndOfCompile and cbStartOfSimulation then
    // run before the first process (38.36.3).
    LLVM::LLVMFuncOp startup = declare(NativeRuntimeEntry::VpiStartup);
    Value moduleNames =
        nameArray
            ? LLVM::GEPOp::create(
                  builder, location, pointer, nameArray.getGlobalType(),
                  LLVM::AddressOfOp::create(builder, location, nameArray),
                  ArrayRef<LLVM::GEPArg>{0, 0}, LLVM::GEPNoWrapFlags::inbounds)
                  .getResult()
            : LLVM::ZeroOp::create(builder, location, pointer).getResult();
    check(LLVM::CallOp::create(
              builder, location, startup,
              ValueRange{
                  runtimeContext, moduleNames,
                  detail::llvmConstant(builder, location, i64, names.size())})
              .getResult());
    LLVM::LLVMFuncOp endCompile = declare(NativeRuntimeEntry::VpiEndCompile);
    check(LLVM::CallOp::create(builder, location, endCompile, runtimeContext)
              .getResult());
    LLVM::LLVMFuncOp startSimulation =
        declare(NativeRuntimeEntry::VpiStartSimulation);
    check(
        LLVM::CallOp::create(builder, location, startSimulation, runtimeContext)
            .getResult());
    LLVM::LLVMFuncOp endSimulation =
        declare(NativeRuntimeEntry::VpiEndSimulation);
    LLVM::LLVMFuncOp shutdown = declare(NativeRuntimeEntry::VpiShutdown);
    schedule::NativeLifecycleFinishOp finish = finishes.front();
    builder.setInsertionPoint(finish);
    Value status = finish.getStatus();
    Value ended = LLVM::CallOp::create(builder, location, endSimulation,
                                       finish.getContext())
                      .getResult();
    Value failed =
        LLVM::ICmpOp::create(builder, location, LLVM::ICmpPredicate::ne, status,
                             detail::llvmConstant(builder, location, i32, 0));
    finish.replaceAllUsesWith(
        LLVM::SelectOp::create(builder, location, failed, status, ended)
            .getResult());
    finish.erase();
    schedule::NativeLifecycleShutdownOp release = shutdowns.front();
    builder.setInsertionPoint(release);
    LLVM::CallOp::create(builder, location, shutdown, release.getContext());
    release.erase();
  }
  start.erase();
  return success();
}

} // namespace talos
