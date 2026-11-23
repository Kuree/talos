//===- SimulationRuntimeABILowering.cpp - Native runtime declarations -===//

#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/SAIF/SAIFDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace talos::detail {

void declareNativeRuntimeABI(ModuleOp module) {
  using Entry = NativeRuntimeEntry;
  MLIRContext *context = module.getContext();
  if (saif::has<saif::Output>(module))
    declareNativeRuntime(module, Entry::SaifDriver);
  declareNativeRuntimes(
      module,
      {Entry::StrengthResolve, Entry::StrengthResolveKind,
       Entry::SchedulerSignal, Entry::SchedulerSignalTransition,
       Entry::SchedulerWideTransitionOwned,
       Entry::SchedulerWideTransitionProjected,
       Entry::SchedulerStaticTransition, Entry::SchedulerStaticTransitionOwned,
       Entry::SchedulerStaticTransitionProjected,
       Entry::SchedulerHandoffPending, Entry::SchedulerRealTransition,
       Entry::StaticSpecializationGuard, Entry::StaticSpecializationGuardRoots,
       Entry::ObservedWriterGuard, Entry::ObservedWriterGuardCached,
       Entry::StaticNbaSpecializationGuard});
  bool guardedVisibility = false;
  module.walk([&](Operation *op) {
    guardedVisibility |=
        schedule::has<schedule::Field::NbaGuardedPrivateInfluence>(op);
  });
  if (guardedVisibility)
    declareNativeRuntime(module, Entry::StaticNbaSpecializationGuardWrite);
  declareNativeRuntimes(module, {Entry::SchedulerEvent,
                                 Entry::SchedulerEventCreate,
                                 Entry::SchedulerEventAfter,
                                 Entry::SchedulerEventReplaceAfter,
                                 Entry::SchedulerEventTriggered,
                                 Entry::ClockingOutputTrack,
                                 Entry::ClockingOutputCurrent,
                                 Entry::SchedulerWaitOrderFailed,
                                 Entry::ClockOccurrenceConsume,
                                 Entry::NochangeUpdate,
                                 Entry::NativeHandleOffset,
                                 Entry::NetCountDrivers,
                                 Entry::PassSwitchControl,
                                 Entry::PassSwitchControlDelayed,
                                 Entry::MosDriveDelayed,
                                 Entry::PowerCancelNba,
                                 Entry::PowerNba,
                                 Entry::PowerNbaAfter,
                                 Entry::PowerNbaView,
                                 Entry::SchedulerNba,
                                 Entry::SchedulerGenericNbaWords,
                                 Entry::SchedulerNbaScalar,
                                 Entry::SchedulerGenericNbaPending,
                                 Entry::SchedulerNbaIfChanged,
                                 Entry::SchedulerPackedSliceNba,
                                 Entry::SchedulerDriverNba,
                                 Entry::SchedulerInertialDriver,
                                 Entry::SchedulerInertialPathDriver,
                                 Entry::SchedulerInertialPathDriverPulse,
                                 Entry::SchedulerInertialPathStorage,
                                 Entry::SchedulerInertialPathStoragePulse,
                                 Entry::SchedulerInertialDriverStrengthPair,
                                 Entry::SchedulerInertialPathStrengthPair,
                                 Entry::SchedulerInertialPathStrengthPairPulse,
                                 Entry::SchedulerResolveDrivers,
                                 Entry::SchedulerClockingNba,
                                 Entry::SchedulerClockingDriverNba,
                                 Entry::SchedulerStaticNba,
                                 Entry::StaticNbaClaim,
                                 Entry::SchedulerStaticNbaPacked,
                                 Entry::StaticNbaStageWide,
                                 Entry::SchedulerStringNba,
                                 Entry::SchedulerManagedNba,
                                 Entry::SchedulerManagedNbaMasked,
                                 Entry::SchedulerFail,
                                 Entry::NativeStateAlloc,
                                 Entry::NativeStateAllocWithRoots,
                                 Entry::NativeStateAllocWithTypedRoots,
                                 Entry::NativeStateRetain,
                                 Entry::NativeStateRelease,
                                 Entry::NativeStateLoadPlane,
                                 Entry::NativeStateStorePlane,
                                 Entry::NativeFrameStore,
                                 Entry::NativeFrameStoreWide,
                                 Entry::NativeStateStoreContinuousPlane,
                                 Entry::NativeOverride,
                                 Entry::NativeDynamicOverride,
                                 Entry::NativeReleaseOverride,
                                 Entry::ArgumentRefLoad,
                                 Entry::ArgumentRefStore,
                                 Entry::GcCurrentLane,
                                 Entry::GcRootPush,
                                 Entry::GcRootPop,
                                 Entry::GcRootRangePush,
                                 Entry::GcRootRangePop,
                                 Entry::GcManagedRootRangePush,
                                 Entry::GcManagedRootRangePop,
                                 Entry::GcCandidateRoot,
                                 Entry::GcSafepoint,
                                 Entry::ObjectAllocate,
                                 Entry::ReferencePathIndexCreate,
                                 Entry::ReferencePathCovergroupOptionCreate,
                                 Entry::ReferencePathStringCharacterCreate,
                                 Entry::ReferencePathAggregateElementCreate,
                                 Entry::ContainerSize,
                                 Entry::VpiFrameBind,
                                 Entry::BoxBindType,
                                 Entry::BoxIsType,
                                 Entry::ContainerReadChecked,
                                 Entry::ContainerCreateLike,
                                 Entry::ContainerCreateTyped,
                                 Entry::ContainerCreateTypedPattern,
                                 Entry::MailboxCreateTyped,
                                 Entry::ContainerClone,
                                 Entry::ContainerSwap,
                                 Entry::ContainerImportFixed,
                                 Entry::ContainerExportFixed,
                                 Entry::ContainerDelete,
                                 Entry::QueueDeleteIndex,
                                 Entry::QueueReadDeleteChecked,
                                 Entry::QueueInsert,
                                 Entry::MailboxTryPut,
                                 Entry::MailboxNum,
                                 Entry::MailboxTryPeek,
                                 Entry::MailboxTryGet,
                                 Entry::SemaphoreCreate,
                                 Entry::SemaphorePut,
                                 Entry::SemaphoreTryGet,
                                 Entry::RandomBounded,
                                 Entry::RandomDistribution,
                                 Entry::StochasticQueue,
                                 Entry::RandomCycleNext,
                                 Entry::RandomNext,
                                 Entry::RandomInitializationEnter,
                                 Entry::RandomInitializationLeave,
                                 Entry::RandomLegacy,
                                 Entry::RandomGetState,
                                 Entry::RandomSetState,
                                 Entry::RandomSeed,
                                 Entry::SampledRead});
  auto snapshot = declareNativeRuntime(module, Entry::SampledPlane);
  auto none = LLVM::ModRefInfo::NoModRef;
  snapshot.setMemoryEffectsAttr(LLVM::MemoryEffectsAttr::get(
      context, none, LLVM::ModRefInfo::Ref, none, none, none, none));
  snapshot.setNoUnwind(true);
  snapshot.setWillReturn(true);
  declareNativeRuntimes(
      module, {Entry::SampledWord, Entry::SampledHistory,
               Entry::ClockedSampleUpdate, Entry::ClockedSampleRead,
               Entry::RandomSolveModesState, Entry::RandomSolveWideModesState,
               Entry::RandomFunctionStage, Entry::RandomCycleSample});
  for (Type floating : {Type(Float32Type::get(module.getContext())),
                        Type(Float64Type::get(module.getContext()))}) {
    bool single = floating.isF32();
    declareNativeRuntime(module, single ? Entry::RandomReal32ToRank
                                        : Entry::RandomReal64ToRank);
    declareNativeRuntime(module, single ? Entry::RandomReal32FromRank
                                        : Entry::RandomReal64FromRank);
  }
  declareNativeRuntimes(
      module,
      {Entry::CovergroupSetEnabled, Entry::CovergroupSetName,
       Entry::CovergroupSetIntegerOption, Entry::CovergroupGetIntegerOption,
       Entry::CovergroupSetStringOption, Entry::CovergroupGetStringOption,
       Entry::CovergroupSetTypeIntegerOption,
       Entry::CovergroupSetTypeStringOption, Entry::CovergroupSampleEnabled,
       Entry::CovergroupClockEventRegister});
  bool eventSnapshots = false;
  module.walk([&](Operation *op) {
    eventSnapshots |=
        isa<sim::SimEventSnapshotRegisterOp, sim::SimEventSnapshotMaskOp,
            sim::SimEventSnapshotFlushOp>(op);
  });
  if (eventSnapshots) {
    declareNativeRuntime(module, Entry::EventSnapshotRegister);
    declareNativeRuntime(module, Entry::EventSnapshotMask);
    declareNativeRuntime(module, Entry::EventSnapshotFlush);
  }
  declareNativeRuntimes(module, {Entry::CovergroupBlockEventRegister,
                                 Entry::CovergroupBlockEventFire,
                                 Entry::CovergroupPrepare,
                                 Entry::CovergroupCandidates,
                                 Entry::CovergroupBindWith,
                                 Entry::CovergroupReleasePreparation,
                                 Entry::CovergroupCreate,
                                 Entry::CovergroupFormalRead,
                                 Entry::CovergroupSample,
                                 Entry::CovergroupInstanceQuery,
                                 Entry::CovergroupTypeQuery,
                                 Entry::CoveragePointHit,
                                 Entry::CoverageControlDefinition,
                                 Entry::CoverageControlInstance,
                                 Entry::CoverageQueryDefinition,
                                 Entry::CoverageQueryInstance,
                                 Entry::CoverageDatabaseSave,
                                 Entry::CoverageDatabaseMerge,
                                 Entry::FunctionalCoverageGet,
                                 Entry::FunctionalCoverageSetDbName,
                                 Entry::FunctionalCoverageLoadDb,
                                 Entry::CoverageFinalize,
                                 Entry::CoverageSnapshot,
                                 Entry::ContainerRead,
                                 Entry::QueuePush,
                                 Entry::ContainerWrite,
                                 Entry::AssocCreateTyped,
                                 Entry::AssocCreateElementKeyed,
                                 Entry::AssocReadChecked,
                                 Entry::AssocWriteChecked,
                                 Entry::AssocExists,
                                 Entry::AssocDelete,
                                 Entry::AssocSetDefaultChecked});
  for (NativeRuntimeEntry entry : {Entry::AssocFirst, Entry::AssocLast,
                                   Entry::AssocNext, Entry::AssocPrev})
    declareNativeRuntime(module, entry);
  declareNativeRuntimes(module, {Entry::ReferencePathAssocCreate,
                                 Entry::ObjectShallowCopy,
                                 Entry::ObjectRead,
                                 Entry::ObjectWrite,
                                 Entry::ObjectBitsInsert,
                                 Entry::ObjectReadPlanes,
                                 Entry::ObjectWritePlanes,
                                 Entry::ObjectFieldLoad,
                                 Entry::ObjectFieldStore,
                                 Entry::ObjectOverride,
                                 Entry::ObjectReleaseOverride,
                                 Entry::ObjectIsInstance,
                                 Entry::ObjectId,
                                 Entry::ManagedWatch,
                                 Entry::ObjectCast,
                                 Entry::MethodInvoke,
                                 Entry::InterfaceMethodInvoke,
                                 Entry::MethodTaskActivate,
                                 Entry::InterfaceMethodTaskActivate,
                                 Entry::WeakCreate,
                                 Entry::WeakGet,
                                 Entry::WeakClear,
                                 Entry::StringCreate,
                                 Entry::StringFromPacked,
                                 Entry::StringToPacked,
                                 Entry::StringConcatMany,
                                 Entry::StringRepeat,
                                 Entry::StringLength,
                                 Entry::StringGetc,
                                 Entry::StringPutc,
                                 Entry::StringSubstr,
                                 Entry::StringCompare,
                                 Entry::StringCompareInsensitive,
                                 Entry::StringCaseConvert,
                                 Entry::StringParseInteger,
                                 Entry::StringParseLogic,
                                 Entry::StringParseReal,
                                 Entry::StringParseRealConstant,
                                 Entry::StringFormatInteger,
                                 Entry::StringFormatReal,
                                 Entry::FileOpenStringMcd,
                                 Entry::FileOpenString,
                                 Entry::DumpOpenString,
                                 Entry::DumpPorts,
                                 Entry::DumpPortsControl,
                                 Entry::FileGetlineString,
                                 Entry::FileScanField,
                                 Entry::FileScanRaw,
                                 Entry::FileErrorString,
                                 Entry::StringScanField,
                                 Entry::StringScanRaw,
                                 Entry::PlusargTest,
                                 Entry::PlusargValue,
                                 Entry::PlusargScan,
                                 Entry::PlusargParseLogic,
                                 Entry::PlusargParseReal,
                                 Entry::System,
                                 Entry::ImportCall,
                                 Entry::ImportCallNoncontext,
                                 Entry::ImportCallGuarded,
                                 Entry::ImportCallNoncontextGuarded,
                                 Entry::DpiOpenArrayPack,
                                 Entry::DpiOpenArrayUnpack,
                                 Entry::DpiOpenArrayAggregatePack,
                                 Entry::DpiOpenArrayAggregateUnpack,
                                 Entry::DpiOpenArrayPrepareRecursive,
                                 Entry::DpiOpenArrayFinishRecursive,
                                 Entry::DpiOpenArrayReleaseRecursive,
                                 Entry::DpiAggregatePack,
                                 Entry::DpiAggregateUnpack,
                                 Entry::DpiAggregateRootsPush,
                                 Entry::DpiAggregateRootsPop,
                                 Entry::DpiAggregateExportPack,
                                 Entry::DpiCurrentContext});
}

} // namespace talos::detail
