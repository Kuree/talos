//===- SimulationPromotionRangeIndex.cpp - Scoped proof invalidation -----===//

#include "NativeStateAccess.h"
#include "SimulationAOTPlanning.h"
#include "SimulationPackedLowering.h"
#include "talos/Conversion/SimulationToLLVMCoroutine.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "talos/Runtime/PromotionRangeIndex.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_MATERIALIZENATIVEPROMOTIONRANGEINDEXPASS
#include "talos/Conversion/Passes.h.inc"
} // namespace talos

namespace talos::detail {

LogicalResult materializeNativePromotionRangeIndex(ModuleOp module,
                                                   uint64_t bucketMinEntries) {
  auto hook = module.lookupSymbol<LLVM::LLVMFuncOp>(
      "__talos_eval_promotion_invalidate_range_v1");
  if (!hook) {
    for (auto global : module.getOps<LLVM::GlobalOp>())
      if (schedule::has<schedule::Field::EvalKnownRangeDependencies>(global))
        return global.emitError("range proof cache has no scoped invalidator");
    return success();
  }
  if (!hook.empty())
    return hook.emitError("range invalidator was materialized twice");
  auto stateBits = runtime::get<runtime::StateBits>(module);
  if (!stateBits)
    return hook.emitError("range invalidator has no canonical state layout");
  if (failed(verifyNativeGroupProofDomains(module)))
    return failure();

  struct Certificate {
    LLVM::GlobalOp global;
    uint64_t latch = 0;
    uint64_t pendingBit = 0;
    DenseI64ArrayAttr ranges;
    bool nba = false;
    bool route = false;
    bool group = false;
    bool local = false;
  };
  SmallVector<Certificate> certificates;
  constexpr auto kernelAttr =
      ::talos::schedule::Field::EvalKernelProofDependencies;
  constexpr auto routeAttr =
      ::talos::schedule::Field::EvalRouteProofDependencies;
  constexpr auto nbaAttr = ::talos::schedule::Field::EvalNbaProofDependencies;
  constexpr auto groupAttr =
      ::talos::schedule::Field::EvalGroupProofDependencies;
  auto pending = module.lookupSymbol<LLVM::GlobalOp>(
      "__talos_eval_promotion_pending_mask_v1");
  auto routePending = module.lookupSymbol<LLVM::GlobalOp>(
      "__talos_eval_route_promotion_pending_v1");
  for (auto global : module.getOps<LLVM::GlobalOp>()) {
    if (auto ranges =
            schedule::get<schedule::Field::EvalKnownRangeDependencies>(
                global)) {
      auto initial = dyn_cast_or_null<IntegerAttr>(global.getValueOrNull());
      if (!global.getGlobalType().isInteger(8) || global.getConstant() ||
          global.getLinkage() != LLVM::Linkage::Internal ||
          global.getAddrSpace() || global.getExternallyInitialized() ||
          !initial || !initial.getValue().isZero() || ranges.empty())
        return global.emitError(
            "range proof cache requires private zero-initialized i8 storage");
      certificates.push_back({global, 0, 0, ranges, false, false, false, true});
      schedule::remove<schedule::Field::EvalKnownRangeDependencies>(global);
    }
    if (auto groups = schedule::get<groupAttr>(global)) {
      if (global.getSymName() != groupPromotionLatchName)
        return global.emitError("group proof index has invalid latch storage");
      for (Attribute attr : groups) {
        auto group = cast<schedule::GroupProofDependencyAttr>(attr);
        certificates.push_back({global, group.getDomain().getUInt(), 0,
                                group.getRanges(), false, false, true});
      }
      schedule::remove<groupAttr>(global);
    }
    if (auto kernels = ::talos::schedule::get<kernelAttr>(global)) {
      auto latchType = dyn_cast<LLVM::LLVMArrayType>(global.getGlobalType());
      auto pendingType =
          pending ? dyn_cast<LLVM::LLVMArrayType>(pending.getGlobalType())
                  : LLVM::LLVMArrayType{};
      if (global.getSymName() != "__talos_eval_kernel_promotion_latched_v1" ||
          !latchType || !latchType.getElementType().isInteger(8) ||
          !pendingType || !pendingType.getElementType().isInteger(64))
        return global.emitError("kernel proof index has invalid latch storage");
      for (Attribute attr : kernels) {
        auto kernel = dyn_cast<schedule::KernelProofDependencyAttr>(attr);
        auto latch = kernel ? kernel.getLatch() : IntegerAttr{};
        auto bit = kernel ? kernel.getPendingBit() : IntegerAttr{};
        auto ranges = kernel ? kernel.getRanges() : DenseI64ArrayAttr{};
        if (!latch || !bit || !ranges ||
            latch.getUInt() >= latchType.getNumElements() ||
            bit.getUInt() / 64 >= pendingType.getNumElements())
          return global.emitError(
              "kernel proof index has invalid certificate identity");
        certificates.push_back(
            {global, latch.getUInt(), bit.getUInt(), ranges});
      }
      ::talos::schedule::remove<kernelAttr>(global);
    }
    if (auto roots = ::talos::schedule::get<nbaAttr>(global)) {
      auto wordType = dyn_cast<LLVM::LLVMArrayType>(global.getGlobalType());
      if (global.getSymName() != "__talos_eval_fast_nba_roots_v1" ||
          !wordType || !wordType.getElementType().isInteger(64))
        return global.emitError(
            "NBA proof index has invalid knownness storage");
      for (Attribute attr : roots) {
        auto root = dyn_cast<schedule::NBAProofDependencyAttr>(attr);
        auto bit = root ? root.getBit() : IntegerAttr{};
        auto ranges = root ? root.getRanges() : DenseI64ArrayAttr{};
        if (!bit || !ranges || bit.getUInt() / 64 >= wordType.getNumElements())
          return global.emitError(
              "NBA proof index has invalid certificate identity");
        certificates.push_back({global, bit.getUInt(), 0, ranges, true});
      }
      ::talos::schedule::remove<nbaAttr>(global);
    }
    if (auto route = ::talos::schedule::get<routeAttr>(global)) {
      auto ranges = route.getRanges();
      auto pendingBit = route.getPendingBit();
      auto pendingType =
          routePending
              ? dyn_cast<LLVM::LLVMArrayType>(routePending.getGlobalType())
              : LLVM::LLVMArrayType{};
      if (!global.getSymName().starts_with(
              "__talos_eval_selected_variant_v1_") ||
          !ranges || !pendingBit || !pendingType ||
          !pendingType.getElementType().isInteger(64) ||
          pendingBit.getUInt() / 64 >= pendingType.getNumElements() ||
          !global.getGlobalType().isInteger(8))
        return global.emitError(
            "route proof index has invalid selector storage");
      certificates.push_back(
          {global, 0, pendingBit.getUInt(), ranges, false, true});
      ::talos::schedule::remove<routeAttr>(global);
    }
  }
  // Stable dense certificate IDs are independent of scheduler owner bits.
  llvm::sort(certificates, [](auto a, auto b) {
    return std::tuple{a.global.getSymName(), a.latch} <
           std::tuple{b.global.getSymName(), b.latch};
  });
  std::vector<talos_rt_native_promotion_dependency> entries;
  for (auto [id, certificate] : llvm::enumerate(certificates)) {
    auto values = certificate.ranges.asArrayRef();
    if (values.size() % 2)
      return certificate.global.emitError("proof index has an odd range list");
    for (size_t index = 0; index != values.size(); index += 2) {
      if (values[index] < 0 || values[index + 1] <= 0)
        return certificate.global.emitError("proof index has an invalid range");
      uint64_t begin = values[index], width = values[index + 1];
      if (begin > stateBits.getUInt() || width > stateBits.getUInt() - begin)
        return certificate.global.emitError(
            "proof index exceeds canonical state");
      entries.push_back({begin, begin + width, 0, id});
    }
  }
  if (!runtime::buildPromotionRangeIndex(entries, stateBits.getUInt(),
                                         certificates.size()))
    return hook.emitError("could not verify canonical proof dependency index");

  // Wide (whole-memory) dependencies of kernel proofs become promotion slices:
  // the runtime counts each slice's X/Z bits and touches its dependents only
  // when the slice changes between holding X/Z and holding none (IEEE
  // 1800-2023 6.3.1). A kernel or group proof is re-validated only by its
  // readiness scan, which reads every one of its ranges (the same merged
  // promotion ranges, or the group domain's ranges), so no dependent can be
  // valid while its slice holds X/Z. Route and NBA proofs keep
  // per-publication actions. Slices need the global
  // invalidator, which recounts them when the plane changed unpublished.
  std::vector<talos_rt_native_promotion_dependency> coverageEntries = entries;
  struct Slice {
    uint64_t begin, end;
    SmallVector<uint64_t> dependents;
  };
  SmallVector<Slice> slices;
  auto globalInvalidate = module.lookupSymbol<LLVM::LLVMFuncOp>(
      "__talos_eval_promotion_invalidate_v1");
  for (Certificate certificate : certificates)
    if (certificate.local) {
      if (!globalInvalidate || globalInvalidate.empty())
        return certificate.global.emitError(
            "range proof cache has no full invalidator");
      // Context reset/unbounded mutation must revoke local cached remainders,
      // just as it revokes the whole-owner and group certificates.
      OpBuilder resetBuilder(globalInvalidate.getContext());
      SmallVector<LLVM::ReturnOp> returns;
      globalInvalidate.walk([&](LLVM::ReturnOp op) { returns.push_back(op); });
      for (LLVM::ReturnOp op : returns) {
        resetBuilder.setInsertionPoint(op);
        LLVM::StoreOp::create(
            resetBuilder, op.getLoc(),
            llvmConstant(resetBuilder, op.getLoc(), resetBuilder.getI8Type(),
                         0),
            LLVM::AddressOfOp::create(
                resetBuilder, op.getLoc(),
                LLVM::LLVMPointerType::get(module.getContext()),
                certificate.global.getSymName()),
            1);
      }
    }
  {
    constexpr uint64_t kSliceBits = 4096;
    auto sliceable = [&](const talos_rt_native_promotion_dependency &entry) {
      Certificate &certificate = certificates[entry.certificate];
      return entry.end - entry.begin > kSliceBits && !certificate.nba &&
             !certificate.route &&
             (certificate.group ||
              certificate.global.getSymName() ==
                  "__talos_eval_kernel_promotion_latched_v1");
    };
    size_t wide = llvm::count_if(entries, sliceable);
    // Slices keep at least one narrow entry: an empty range index takes the
    // early path below that builds empty hooks.
    if (globalInvalidate && !globalInvalidate.empty() && wide != 0 &&
        wide != entries.size()) {
      std::vector<uint64_t> points;
      for (const auto &entry : entries)
        if (sliceable(entry)) {
          points.push_back(entry.begin);
          points.push_back(entry.end);
        }
      llvm::sort(points);
      points.erase(std::unique(points.begin(), points.end()), points.end());
      for (size_t index = 0; index + 1 < points.size(); ++index) {
        uint64_t low = points[index], high = points[index + 1];
        SmallVector<uint64_t> dependents;
        for (const auto &entry : entries)
          if (sliceable(entry) && entry.begin <= low && entry.end >= high)
            dependents.push_back(entry.certificate);
        if (dependents.empty())
          continue;
        llvm::sort(dependents);
        dependents.erase(std::unique(dependents.begin(), dependents.end()),
                         dependents.end());
        if (!slices.empty() && slices.back().end == low &&
            slices.back().dependents == dependents)
          slices.back().end = high;
        else
          slices.push_back({low, high, std::move(dependents)});
      }
      llvm::erase_if(entries, sliceable);
      if (!runtime::buildPromotionRangeIndex(entries, stateBits.getUInt(),
                                             certificates.size()))
        return hook.emitError(
            "could not verify canonical proof dependency index");
    }
  }

  MLIRContext *context = module.getContext();
  OpBuilder builder(context);
  Location location = hook.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i64 = builder.getI64Type();
  Type voidType = LLVM::LLVMVoidType::get(context);
  Block *entry = hook.addEntryBlock(builder);
  hook->setAttr("passthrough",
                builder.getArrayAttr({builder.getStringAttr("cold"),
                                      builder.getStringAttr("noinline")}));
  auto recheck = getOrDeclareGeneratedFunction(
      module, "__talos_eval_promotion_recheck_range_v1", voidType, {i64, i64});
  if (!recheck.empty())
    return recheck.emitError("range recheck was materialized twice");
  recheck->setAttr("passthrough", hook->getAttr("passthrough"));
  Block *recheckEntry = recheck.addEntryBlock(builder);
  if (entries.empty()) {
    builder.setInsertionPointToStart(entry);
    LLVM::ReturnOp::create(builder, location, ValueRange{});
    builder.setInsertionPointToStart(recheckEntry);
    LLVM::ReturnOp::create(builder, location, ValueRange{});
    return success();
  }

  // Narrow X/Z changes (IEEE 1800-2023 6.3.1, 6.11.2, 38.34) should find their
  // proofs without a logarithmic tree walk. A bucket record per word suits a
  // narrow dependency but not a whole-memory one, so only those stay in the
  // interval tree. Both tables apply the same idempotent proof actions, and
  // every query consults both. Keep small trees compact, and cap the buckets
  // at twice the interval table they replace.
  constexpr uint64_t maxBucketedBits = 4096;
  std::vector<talos_rt_native_promotion_dependency> narrow, tree;
  for (const auto &dependency : entries)
    (dependency.end - dependency.begin <= maxBucketedBits ? narrow : tree)
        .push_back(dependency);
  runtime::PromotionBucketIndex buckets;
  bool bucketed =
      narrow.size() >= bucketMinEntries && narrow.size() <= UINT64_MAX / 64 &&
      runtime::buildPromotionBucketIndex(narrow, narrow.size() * 64, buckets);
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos proof index: certificates=" << certificates.size()
                 << " dependencies=" << entries.size()
                 << " wide=" << tree.size() << " bucketed=" << bucketed
                 << " records=" << buckets.records.size() << " buckets="
                 << (buckets.starts.size() ? buckets.starts.size() - 1 : 0)
                 << '\n';
  if (!bucketed)
    tree = entries;
  else if (!runtime::buildPromotionRangeIndex(tree, stateBits.getUInt(),
                                              certificates.size()))
    return hook.emitError("could not verify canonical proof dependency index");

  // The runtime record is four consecutive uint64_t fields. A nested i64
  // array has the same layout on every supported target. Use a dense constant
  // instead of repeatedly inserting into an N-record LLVM constant array:
  // translation would rebuild and unique that entire array for every record.
  // An empty tree keeps a placeholder record to carry the coverage below.
  SmallVector<uint64_t> dependencyWords;
  dependencyWords.reserve(std::max<size_t>(tree.size(), 1) * 4);
  for (const auto &dependency : tree)
    llvm::append_range(dependencyWords,
                       ArrayRef<uint64_t>{dependency.begin, dependency.end,
                                          dependency.subtree_end,
                                          dependency.certificate});
  if (tree.empty())
    dependencyWords.append(4, 0);
  int64_t dependencyRows = dependencyWords.size() / 4;
  auto dependencyArray = LLVM::LLVMArrayType::get(
      LLVM::LLVMArrayType::get(i64, 4), dependencyRows);
  auto denseType = RankedTensorType::get({dependencyRows, 4}, i64);
  builder.setInsertionPointToStart(module.getBody());
  auto dependencies = LLVM::GlobalOp::create(
      builder, location, dependencyArray, true, LLVM::Linkage::Internal,
      "__talos_eval_proof_dependencies_v1",
      DenseIntElementsAttr::get(denseType, ArrayRef<uint64_t>(dependencyWords)),
      8);
  // The publication pass consumes this union of the same verified index.
  // It is coverage, not another ownership or alias inventory. Constant stores
  // outside it cannot change any certificate and need no runtime guard.
  SmallVector<int64_t> coverage;
  for (const auto &dependency : coverageEntries) {
    if (!coverage.empty() &&
        dependency.begin <= static_cast<uint64_t>(coverage.back())) {
      coverage.back() =
          std::max(coverage.back(), static_cast<int64_t>(dependency.end));
    } else {
      coverage.push_back(dependency.begin);
      coverage.push_back(dependency.end);
    }
  }
  ::talos::schedule::set<::talos::schedule::Field::EvalProofCoverage>(
      dependencies, builder.getDenseI64ArrayAttr(coverage));
  // Every dependency as (begin, end, certificate), for the windows that
  // constant-offset publications resolve at compile time.
  SmallVector<int64_t> flatEntries;
  flatEntries.reserve(entries.size() * 3);
  for (const auto &dependency : entries)
    llvm::append_range(flatEntries,
                       ArrayRef<int64_t>{int64_t(dependency.begin),
                                         int64_t(dependency.end),
                                         int64_t(dependency.certificate)});
  ::talos::schedule::set<::talos::schedule::Field::EvalProofEntries>(
      dependencies, builder.getDenseI64ArrayAttr(flatEntries));
  if (!slices.empty()) {
    SmallVector<int64_t> flatSlices;
    for (const Slice &slice : slices)
      llvm::append_range(flatSlices, ArrayRef<int64_t>{int64_t(slice.begin),
                                                       int64_t(slice.end)});
    ::talos::schedule::set<::talos::schedule::Field::EvalProofSlices>(
        dependencies, builder.getDenseI64ArrayAttr(flatSlices));
  }

  // Pointer fields use the target LLVM layout; only packed bit positions and
  // uint64_t pending words have fixed byte offsets across native and wasm32.
  Type certificateType = LLVM::LLVMStructType::getLiteral(
      context, {pointer, pointer, i64, pointer, pointer});
  auto certificateArray =
      LLVM::LLVMArrayType::get(certificateType, certificates.size());
  auto actions = makeConstantGlobal(
      module, location, certificateArray, "__talos_eval_proof_certificates_v1",
      LLVM::Linkage::Internal, 8, [&](OpBuilder &b) {
        Value array = LLVM::ZeroOp::create(b, location, certificateArray);
        for (auto [index, certificate] : llvm::enumerate(certificates)) {
          Value record = LLVM::ZeroOp::create(b, location, certificateType);
          Value address = LLVM::AddressOfOp::create(
              b, location, pointer, certificate.global.getSymName());
          auto insert = [&](Value value, int64_t field) {
            record = LLVM::InsertValueOp::create(b, location, record, value,
                                                 ArrayRef<int64_t>{field});
          };
          if (certificate.group || certificate.local) {
            // Independent proof domains have no runnable owner/pending word.
            // The runtime's existing latch-only action clears this byte on
            // lost knownness and does nothing on gained knownness. A later
            // query rereads its negative hint before rescanning exact ranges.
            insert(byteGEP(b, location, address, certificate.latch), 0);
          } else if (certificate.route) {
            insert(address, 0);
            insert(byteGEP(b, location,
                           LLVM::AddressOfOp::create(b, location, pointer,
                                                     routePending.getSymName()),
                           (certificate.pendingBit / 64) * sizeof(uint64_t)),
                   1);
            insert(llvmConstant(b, location, i64,
                                uint64_t{1} << (certificate.pendingBit % 64)),
                   2);
          } else if (certificate.nba) {
            insert(byteGEP(b, location, address,
                           (certificate.latch / 64) * sizeof(uint64_t)),
                   1);
            insert(llvmConstant(b, location, i64,
                                uint64_t{1} << (certificate.latch % 64)),
                   2);
          } else {
            insert(byteGEP(b, location, address, certificate.latch), 0);
            insert(byteGEP(b, location,
                           LLVM::AddressOfOp::create(b, location, pointer,
                                                     pending.getSymName()),
                           (certificate.pendingBit / 64) * sizeof(uint64_t)),
                   1);
            insert(llvmConstant(b, location, i64,
                                uint64_t{1} << (certificate.pendingBit % 64)),
                   2);
          }
          array = LLVM::InsertValueOp::create(
              b, location, array, record,
              ArrayRef<int64_t>{static_cast<int64_t>(index)});
        }
        return array;
      });

  // Aggregate entry shortcuts must be recomputed after a dependent proof is
  // disturbed. Per-kernel latches and per-route selectors remain independent;
  // the lookup helper changes only those in its exact overlap result.
  auto reset = getOrDeclareGeneratedFunction(
      module, "__talos_eval_proof_aggregate_invalidate_v1", voidType, {});
  builder.setInsertionPointToStart(reset.addEntryBlock(builder));
  for (StringRef name : {"__talos_eval_promotion_latched_v1"})
    if (auto global = module.lookupSymbol<LLVM::GlobalOp>(name))
      LLVM::StoreOp::create(
          builder, location,
          LLVM::ZeroOp::create(builder, location, global.getGlobalType()),
          LLVM::AddressOfOp::create(builder, location, pointer, name));
  if (auto dirty = module.lookupSymbol<LLVM::GlobalOp>(
          "__talos_eval_route_promotion_dirty_v1"))
    LLVM::StoreOp::create(
        builder, location,
        llvmConstant(builder, location, builder.getI8Type(), 1),
        LLVM::AddressOfOp::create(builder, location, pointer,
                                  dirty.getSymName()));
  LLVM::ReturnOp::create(builder, location, ValueRange{});

  auto request = getOrDeclareGeneratedFunction(
      module, "__talos_eval_proof_aggregate_recheck_v1", voidType, {});
  builder.setInsertionPointToStart(request.addEntryBlock(builder));
  // A gain in knownness cannot invalidate a positive proof. Only cached
  // failed scans need to become eligible for another boundary check.
  for (StringRef name : {"__talos_eval_route_promotion_dirty_v1"})
    if (auto global = module.lookupSymbol<LLVM::GlobalOp>(name))
      LLVM::StoreOp::create(
          builder, location,
          llvmConstant(builder, location, builder.getI8Type(), 1),
          LLVM::AddressOfOp::create(builder, location, pointer, name));
  LLVM::ReturnOp::create(builder, location, ValueRange{});
  auto treeLookup = [&](Block *block, LLVM::LLVMFuncOp aggregate,
                        StringRef name) {
    if (tree.empty())
      return;
    auto lookup = getOrDeclareGeneratedFunction(
        module, name, voidType, {pointer, i64, pointer, pointer, i64, i64});
    LLVM::CallOp::create(
        builder, location, lookup,
        ValueRange{LLVM::AddressOfOp::create(builder, location, pointer,
                                             dependencies.getSymName()),
                   llvmConstant(builder, location, i64, tree.size()),
                   LLVM::AddressOfOp::create(builder, location, pointer,
                                             actions.getSymName()),
                   LLVM::AddressOfOp::create(builder, location, pointer,
                                             aggregate.getSymName()),
                   block->getArgument(0), block->getArgument(1)});
  };
  builder.setInsertionPointToStart(recheckEntry);
  treeLookup(
      recheckEntry, request,
      getNativeRuntimeSymbol(NativeRuntimeEntry::NativePromotionRecheckRanges));
  LLVM::ReturnOp::create(builder, location, ValueRange{});
  builder.setInsertionPointToStart(entry);
  treeLookup(entry, reset,
             getNativeRuntimeSymbol(
                 NativeRuntimeEntry::NativePromotionInvalidateRanges));
  LLVM::ReturnOp::create(builder, location, ValueRange{});

  if (bucketed) {
    builder.setInsertionPointToStart(module.getBody());
    auto i32 = builder.getI32Type();
    auto starts = LLVM::GlobalOp::create(
        builder, location, LLVM::LLVMArrayType::get(i32, buckets.starts.size()),
        true, LLVM::Linkage::Internal, "__talos_eval_proof_bucket_starts_v1",
        DenseIntElementsAttr::get(
            RankedTensorType::get({int64_t(buckets.starts.size())}, i32),
            ArrayRef<uint32_t>(buckets.starts)),
        4);
    auto records = LLVM::GlobalOp::create(
        builder, location,
        LLVM::LLVMArrayType::get(i64, buckets.records.size()), true,
        LLVM::Linkage::Internal, "__talos_eval_proof_bucket_records_v1",
        DenseIntElementsAttr::get(
            RankedTensorType::get({int64_t(buckets.records.size())}, i64),
            ArrayRef<uint64_t>(buckets.records)),
        8);
    auto specialize = [&](Block *head, LLVM::LLVMFuncOp aggregate,
                          StringRef helperName) {
      builder.setInsertionPointToStart(head);
      auto helper = getOrDeclareGeneratedFunction(
          module, helperName, voidType,
          {pointer, pointer, i64, pointer, pointer, i64, i64});
      LLVM::CallOp::create(
          builder, location, helper,
          ValueRange{
              LLVM::AddressOfOp::create(builder, location, pointer,
                                        starts.getSymName()),
              LLVM::AddressOfOp::create(builder, location, pointer,
                                        records.getSymName()),
              llvmConstant(builder, location, i64, buckets.starts.size() - 1),
              LLVM::AddressOfOp::create(builder, location, pointer,
                                        actions.getSymName()),
              LLVM::AddressOfOp::create(builder, location, pointer,
                                        aggregate.getSymName()),
              head->getArgument(0), head->getArgument(1)});
    };
    specialize(entry, reset,
               getNativeRuntimeSymbol(
                   NativeRuntimeEntry::NativePromotionInvalidateBuckets));
    specialize(recheckEntry, request,
               getNativeRuntimeSymbol(
                   NativeRuntimeEntry::NativePromotionRecheckBuckets));
  }

  if (!slices.empty()) {
    builder.setInsertionPointToStart(module.getBody());
    auto constantArray = [&](StringRef name, ArrayRef<uint64_t> words,
                             bool constant) {
      auto type = LLVM::LLVMArrayType::get(i64, words.size());
      return LLVM::GlobalOp::create(
          builder, location, type, constant, LLVM::Linkage::Internal, name,
          DenseIntElementsAttr::get(
              RankedTensorType::get({int64_t(words.size())}, i64), words),
          8);
    };
    SmallVector<uint64_t> ranges, starts{0}, dependents;
    for (const Slice &slice : slices) {
      llvm::append_range(ranges, ArrayRef<uint64_t>{slice.begin, slice.end});
      llvm::append_range(dependents, slice.dependents);
      starts.push_back(dependents.size());
    }
    auto rangesGlobal =
        constantArray("__talos_eval_promotion_slice_ranges_v1", ranges, true);
    // Recounted from the plane by the global invalidator, which plan
    // installation runs before any publication.
    auto countsGlobal = constantArray(
        "__talos_eval_promotion_slice_counts_v1",
        SmallVector<uint64_t>(slices.size(), 0), false);
    auto startsGlobal =
        constantArray("__talos_eval_promotion_slice_starts_v1", starts, true);
    auto dependentsGlobal = constantArray(
        "__talos_eval_promotion_slice_dependents_v1", dependents, true);
    Type slicesType = LLVM::LLVMStructType::getLiteral(
        context, {pointer, pointer, pointer, pointer, i64, pointer});
    makeConstantGlobal(
        module, location, slicesType, "__talos_eval_promotion_slices_v1",
        LLVM::Linkage::Internal, 8, [&](OpBuilder &b) {
          Value record = LLVM::ZeroOp::create(b, location, slicesType);
          auto put = [&](Value value, int64_t field) {
            record = LLVM::InsertValueOp::create(b, location, record, value,
                                                 ArrayRef<int64_t>{field});
          };
          auto addressOf = [&](StringRef name) -> Value {
            return LLVM::AddressOfOp::create(b, location, pointer, name);
          };
          put(addressOf(rangesGlobal.getSymName()), 0);
          put(addressOf(countsGlobal.getSymName()), 1);
          put(addressOf(startsGlobal.getSymName()), 2);
          put(addressOf(dependentsGlobal.getSymName()), 3);
          put(llvmConstant(b, location, i64, slices.size()), 4);
          put(detail::createStatePlaneAddress(b, location,
                                              schedule::StatePlane::Unknown),
              5);
          return record;
        });
    auto adjust = declareNativeRuntime(
        module, NativeRuntimeEntry::NativePromotionSlicesAdjust);
    auto recount = declareNativeRuntime(
        module, NativeRuntimeEntry::NativePromotionSlicesRecount);
    auto beforeReturns = [&](LLVM::LLVMFuncOp function, auto emit) {
      SmallVector<LLVM::ReturnOp> returns;
      function.walk([&](LLVM::ReturnOp op) { returns.push_back(op); });
      for (LLVM::ReturnOp op : returns) {
        builder.setInsertionPoint(op);
        emit(function);
      }
    };
    auto adjustIn = [&](LLVM::LLVMFuncOp aggregate, bool becameUnknown) {
      return [&, aggregate, becameUnknown](LLVM::LLVMFuncOp function) mutable {
        Block &entryBlock = function.getBody().front();
        LLVM::CallOp::create(
            builder, location, adjust,
            ValueRange{LLVM::AddressOfOp::create(
                           builder, location, pointer,
                           "__talos_eval_promotion_slices_v1"),
                       LLVM::AddressOfOp::create(builder, location, pointer,
                                                 actions.getSymName()),
                       LLVM::AddressOfOp::create(builder, location, pointer,
                                                 aggregate.getSymName()),
                       entryBlock.getArgument(0), entryBlock.getArgument(1),
                       llvmConstant(builder, location, builder.getI32Type(),
                                    becameUnknown)});
      };
    };
    beforeReturns(hook, adjustIn(reset, true));
    beforeReturns(recheck, adjustIn(request, false));
    beforeReturns(globalInvalidate, [&](LLVM::LLVMFuncOp) {
      LLVM::CallOp::create(builder, location, recount,
                           ValueRange{LLVM::AddressOfOp::create(
                               builder, location, pointer,
                               "__talos_eval_promotion_slices_v1")});
    });
    if (native::has<native::DebugTiming>(module))
      llvm::errs() << "talos proof slices: slices=" << slices.size()
                   << " dependents=" << dependents.size() << '\n';
  }
  return success();
}

namespace {
struct NativeProofPublicationInputs {
  explicit NativeProofPublicationInputs(Operation *operation) {
    auto module = cast<ModuleOp>(operation);
    auto hook = module.lookupSymbol<LLVM::LLVMFuncOp>(
        "__talos_eval_promotion_invalidate_range_v1");
    auto dependencies = module.lookupSymbol<LLVM::GlobalOp>(
        "__talos_eval_proof_dependencies_v1");
    active = hook && dependencies;
    if (!active)
      return;
    coverage = schedule::get<schedule::Field::EvalProofCoverage>(dependencies);
    if (!coverage || coverage.size() % 2) {
      dependencies.emitError("missing verified proof coverage");
      valid = false;
    }
    bits = runtime::get<runtime::StateBits>(module);
  }
  DenseI64ArrayAttr coverage;
  IntegerAttr bits;
  bool active = false;
  bool valid = true;
};

/// The constant byte offset of an unknown-plane address, kept small enough
/// to scale to bits.
std::optional<uint64_t> constantPlaneBytes(Value address) {
  std::optional<uint64_t> bytes = getConstantByteOffset(address);
  if (!bytes || *bytes > (UINT64_MAX >> 4))
    return std::nullopt;
  return bytes;
}

struct NativeFunctionProofPublications {
  NativeFunctionProofPublications(Operation *operation,
                                  AnalysisManager &manager) {
    auto function = cast<LLVM::LLVMFuncOp>(operation);
    auto cached = manager.getCachedParentAnalysis<NativeProofPublicationInputs>(
        function->getParentOfType<ModuleOp>());
    if (!cached || !cached->get().valid) {
      function.emitError("proof publication requires cached dependency inputs");
      valid = false;
      return;
    }
    const auto &inputs = cached->get();
    function.walk([&](Operation *operation) {
      if (isa<LLVM::StoreOp, schedule::NativeStateStoreOp>(operation))
        allStores.push_back(operation);
    });
    if (!inputs.active)
      return;
    auto disjointRange = [&](uint64_t begin, uint64_t width) {
      if (width > UINT64_MAX - begin)
        return false;
      auto ranges = inputs.coverage.asArrayRef();
      // Ranges are sorted and disjoint; find the first end past the store
      // start.
      size_t low = 0, high = ranges.size() / 2;
      while (low != high) {
        size_t middle = low + (high - low) / 2;
        if (static_cast<uint64_t>(ranges[middle * 2 + 1]) <= begin)
          low = middle + 1;
        else
          high = middle;
      }
      return low == ranges.size() / 2 ||
             static_cast<uint64_t>(ranges[low * 2]) >= begin + width;
    };
    auto bits = inputs.bits;
    auto disjointStore = [&](const NativeMemoryAccess &store) {
      if (DenseI64ArrayAttr range = store.writtenBits) {
        // The generated dynamic store's clipped mask proves containment.
        // Missing or malformed evidence is conservative, never a guessed lane.
        if (bits && range.size() == 2 && range[0] >= 0 && range[1] > 0 &&
            static_cast<uint64_t>(range[0]) <= bits.getUInt() &&
            static_cast<uint64_t>(range[1]) <= bits.getUInt() - range[0])
          return disjointRange(range[0], range[1]);
      }
      auto type = dyn_cast<IntegerType>(store.type);
      if (!type || !store.offset || *store.offset > UINT64_MAX / 8)
        return false;
      uint64_t begin = *store.offset * 8;
      uint64_t width = ((uint64_t{type.getWidth()} + 7) / 8) * 8;
      return disjointRange(begin, width);
    };
    // The unknown plane is written by typed stores, and by copies and fills
    // of its window addresses; native finalization rejects any other access.
    auto inUnknownPlane = [](Value address) {
      std::optional<StateWindow> window = getStateWindow(address);
      return window && window->plane == schedule::StatePlane::Unknown;
    };
    for (Operation *operation : allStores) {
      auto typed = dyn_cast<schedule::NativeStateStoreOp>(operation);
      if (!typed || typed.getPlane() != schedule::StatePlane::Unknown)
        continue;
      auto store = *getNativeMemoryAccess(operation);
      if (disjointStore(store))
        continue;
      if (!isa<IntegerType>(store.type)) {
        operation->emitError(
            "canonical proof publication requires packed integer storage");
        valid = false;
      }
      stores.push_back(operation);
    }
    // Bulk writes (wide direct copies and fills) change canonical X/Z bits
    // too. Their destination range is the constant byte offset plus the
    // length when both are constant; otherwise it is not disjoint.
    function.walk([&](Operation *operation) {
      Value destination, length;
      if (auto copy = dyn_cast<LLVM::MemcpyOp>(operation)) {
        destination = copy.getDst();
        length = copy.getLen();
      } else if (auto move = dyn_cast<LLVM::MemmoveOp>(operation)) {
        destination = move.getDst();
        length = move.getLen();
      } else if (auto set = dyn_cast<LLVM::MemsetOp>(operation)) {
        destination = set.getDst();
        length = set.getLen();
      } else {
        return;
      }
      if (!inUnknownPlane(destination))
        return;
      APInt bytes;
      std::optional<uint64_t> offset = constantPlaneBytes(destination);
      if (offset && matchPattern(length, m_ConstantInt(&bytes)) &&
          bytes.getActiveBits() <= 60 &&
          (bytes.isZero() || disjointRange(*offset * 8, bytes.getZExtValue() * 8)))
        return;
      bulkWrites.push_back(operation);
    });
  }
  /// Stores of either form; `stores` publish their X/Z changes.
  SmallVector<Operation *> allStores;
  SmallVector<Operation *> stores;
  SmallVector<Operation *> bulkWrites;
  bool valid = true;
};

class PublishNativeFunctionProofsPass final
    : public PassWrapper<PublishNativeFunctionProofsPass,
                         OperationPass<LLVM::LLVMFuncOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(PublishNativeFunctionProofsPass)
  StringRef getArgument() const final {
    return "publish-native-function-proofs";
  }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<LLVM::LLVMDialect, schedule::ScheduleDialect,
                    native::NativeDialect>();
  }
  void runOnOperation() override {
    if (getOperation().isExternal()) {
      markAllAnalysesPreserved();
      return;
    }
    const auto &work = getAnalysis<NativeFunctionProofPublications>();
    if (!work.valid)
      return signalPassFailure();
    bool changed = !work.stores.empty() || !work.bulkWrites.empty();
    // Proof publication is the last reader of declared write ranges.
    for (Operation *store : work.allStores) {
      if (auto typed = dyn_cast<schedule::NativeStateStoreOp>(store)) {
        changed |= static_cast<bool>(typed.getWrittenBitsAttr());
        typed.removeWrittenBitsAttr();
        continue;
      }
      changed |= schedule::has<schedule::Field::EvalUnknownWriteRange>(store);
      schedule::remove<schedule::Field::EvalUnknownWriteRange>(store);
    }
    if (!changed) {
      markAllAnalysesPreserved();
      return;
    }
    MLIRContext *context = &getContext();
    // Run after value-domain cloning: proven two-state stores have disappeared.
    // Diff the actual canonical bytes, including masked and dynamically
    // selected NBA stores. Preserved neighbors produce no delta; a known NBA
    // payload must still clear an unknown destination before publication (IEEE
    // 1800 10.4.2). Neither staging a future update nor a known-to-known store
    // invalidates a certificate. No actor or observer executes between the
    // store and this proof publication, which precedes all dependent
    // computation/fanout.
    OpBuilder builder(context);
    Type i64 = builder.getI64Type();
    auto constant = [&](Location location, uint64_t value) -> Value {
      return llvmConstant(builder, location, i64, value);
    };
    // The bit offset of a window of the unknown plane, for dynamic
    // publications.
    auto planeBitOffset = [&](Location location, Value dynamicOffset,
                              uint64_t staticOffset) -> Value {
      Value bytes = dynamicOffset;
      if (!bytes)
        bytes = constant(location, staticOffset);
      else if (staticOffset)
        bytes = LLVM::AddOp::create(builder, location, bytes,
                                    constant(location, staticOffset));
      return LLVM::ShlOp::create(builder, location, bytes,
                                 constant(location, 3));
    };
    // Publishes one chunk of at most 64 changed bits at the insertion point,
    // in a cold block entered only when some bit changed, and continues after
    // it. A constant canonical offset publishes through a window whose
    // dependent proofs are resolved at compile time.
    auto publish = [&](Location location, std::optional<uint64_t> constantBits,
                       Value bitOffset, Value chunk,
                       llvm::function_ref<Value()> nextChunk) {
      // Keep the empty-mask check in this body. An alwaysinline wrapper can
      // land in a different native partition, leaving an ordinary call on
      // every unchanged store despite its attribute.
      Value hasChange =
          LLVM::ICmpOp::create(builder, location, LLVM::ICmpPredicate::ne,
                               chunk, constant(location, 0));
      Block *head = builder.getInsertionBlock();
      Block *continuation = head->splitBlock(builder.getInsertionPoint());
      Block *changed = new Block;
      head->getParent()->getBlocks().insert(continuation->getIterator(),
                                            changed);
      builder.setInsertionPointToEnd(head);
      LLVM::CondBrOp::create(builder, location, hasChange, changed,
                             continuation);
      builder.setInsertionPointToStart(changed);
      Value next = nextChunk();
      if (constantBits)
        LLVM::CallOp::create(
            builder, location, TypeRange{},
            SymbolRefAttr::get(context, "__talos_eval_promotion_publish_at_v1"),
            ValueRange{constant(location, *constantBits), chunk, next})
            .setCConv(LLVM::cconv::CConv::PreserveMost);
      else
        LLVM::CallOp::create(
            builder, location, TypeRange{},
            SymbolRefAttr::get(context,
                               "__talos_eval_promotion_publish_unknown_v1"),
            ValueRange{bitOffset, chunk, next})
            .setCConv(LLVM::cconv::CConv::PreserveMost);
      LLVM::BrOp::create(builder, location, ValueRange{}, continuation);
      builder.setInsertionPointToStart(continuation);
    };
    auto toChunk = [&](Location location, Value value) -> Value {
      unsigned width = cast<IntegerType>(value.getType()).getWidth();
      if (width > 64)
        return LLVM::TruncOp::create(builder, location, i64, value);
      if (width < 64)
        return LLVM::ZExtOp::create(builder, location, i64, value);
      return value;
    };
    for (Operation *operation : work.stores) {
      Location location = operation->getLoc();
      auto typed = cast<schedule::NativeStateStoreOp>(operation);
      auto store = *getNativeMemoryAccess(operation);
      auto type = cast<IntegerType>(store.type);
      builder.setInsertionPoint(operation);
      auto read = schedule::NativeStateLoadOp::create(
          builder, location, type, typed.getPlane(), typed.getDynamicOffset(),
          typed.getStaticOffset(), 1);
      read.setWindowAttr(typed.getWindowAttr());
      Value old = read;
      // Bit offsets must stay representable after scaling by eight.
      std::optional<uint64_t> constantBytes;
      if (store.offset && *store.offset <= (UINT64_MAX >> 4))
        constantBytes = store.offset;
      Value bitOffset = planeBitOffset(location, typed.getDynamicOffset(),
                                       typed.getStaticOffset());
      Value delta = LLVM::XOrOp::create(builder, location, old, store.stored);
      builder.setInsertionPointAfter(operation);
      for (uint64_t bit = 0; bit < type.getWidth(); bit += 64) {
        Value chunk = delta;
        if (bit)
          chunk =
              LLVM::LShrOp::create(builder, location, chunk,
                                   llvmConstant(builder, location, type, bit));
        chunk = toChunk(location, chunk);
        Value offset = bit ? LLVM::AddOp::create(builder, location, bitOffset,
                                                 constant(location, bit))
                                 .getResult()
                           : bitOffset;
        publish(location,
                constantBytes ? std::optional<uint64_t>(*constantBytes * 8 + bit)
                              : std::nullopt,
                offset, chunk, [&] {
                  Value next = store.stored;
                  if (bit)
                    next = LLVM::LShrOp::create(
                        builder, location, next,
                        llvmConstant(builder, location, type, bit));
                  return toChunk(location, next);
                });
      }
    }
    // A bulk write (a direct wide copy or fill) changes canonical X/Z bits
    // like a store does. Its new destination bytes are the source bytes, or
    // the fill byte, as they are before the write: LLVM memcpy operands do not
    // overlap and memmove copies as if through a temporary. So each chunk's
    // exact delta is computed, and published, just before the write; nothing
    // runs between them (IEEE 1800-2023 6.3.1).
    for (Operation *write : work.bulkWrites) {
      Location location = write->getLoc();
      Value destination, source, fill, length;
      if (auto copy = dyn_cast<LLVM::MemcpyOp>(write)) {
        destination = copy.getDst();
        source = copy.getSrc();
        length = copy.getLen();
      } else if (auto move = dyn_cast<LLVM::MemmoveOp>(write)) {
        destination = move.getDst();
        source = move.getSrc();
        length = move.getLen();
      } else {
        auto set = cast<LLVM::MemsetOp>(write);
        destination = set.getDst();
        fill = set.getVal();
        length = set.getLen();
      }
      schedule::remove<schedule::Field::EvalUnknownWriteRange>(write);
      builder.setInsertionPoint(write);
      std::optional<uint64_t> constantBytes = constantPlaneBytes(destination);
      StateWindow window = *getStateWindow(destination);
      Value bitBase =
          planeBitOffset(location, window.dynamicOffset, window.staticOffset);
      // Exact chunks up to this many bytes; a longer write (such as a whole
      // plane fill) or an unbounded one reports its whole range as possibly
      // X/Z after the write instead, which is always sound.
      constexpr uint64_t kExactBytes = 4096;
      APInt bytes;
      if (!matchPattern(length, m_ConstantInt(&bytes)) ||
          bytes.getActiveBits() > 60 || bytes.getZExtValue() > kExactBytes) {
        // The range hook is declared by prepareNativeProofPublicationInputs.
        builder.setInsertionPointAfter(write);
        Value width = LLVM::ShlOp::create(builder, location,
                                          toChunk(location, length),
                                          constant(location, 3));
        LLVM::CallOp::create(
            builder, location, TypeRange{},
            SymbolRefAttr::get(context,
                               "__talos_eval_promotion_invalidate_range_v1"),
            ValueRange{bitBase, width});
        continue;
      }
      uint64_t total = bytes.getZExtValue();
      // The new and old bytes [at, at + count) of the destination.
      auto chunkAt = [&](Value at, unsigned count) {
        auto type = builder.getIntegerType(count * 8);
        // Either side may be a state plane's window.
        Value old =
            createLoadAt(builder, location, type, destination, at, 0, 1);
        if (auto footprint =
                schedule::get<schedule::Field::EvalStateAccessBytes>(write))
          setNativeAccessWindow(old.getDefiningOp(), footprint);
        Value next;
        if (source) {
          next = createLoadAt(builder, location, type, source, at, 0, 1);
        } else if (count == 1) {
          next = fill;
        } else {
          next = LLVM::ZExtOp::create(builder, location, type, fill);
          APInt ones = APInt::getSplat(count * 8, APInt(8, 1));
          next = LLVM::MulOp::create(
              builder, location, next,
              LLVM::ConstantOp::create(builder, location, type,
                                       builder.getIntegerAttr(type, ones)));
        }
        Value delta = LLVM::XOrOp::create(builder, location, old, next);
        return std::pair{toChunk(location, delta), toChunk(location, next)};
      };
      auto publishAt = [&](uint64_t at, Value index, unsigned count) {
        auto [delta, next] = chunkAt(index, count);
        Value offset = LLVM::AddOp::create(
            builder, location, bitBase,
            LLVM::ShlOp::create(builder, location, index, constant(location, 3)));
        publish(location,
                constantBytes && at != UINT64_MAX
                    ? std::optional<uint64_t>((*constantBytes + at) * 8)
                    : std::nullopt,
                offset, delta, [&] { return next; });
      };
      constexpr uint64_t kUnrolledBytes = 64;
      uint64_t words = total / 8;
      uint64_t first = 0;
      if (total > kUnrolledBytes) {
        // Whole words in a loop through dynamic publications; then the tail.
        Block *head = builder.getInsertionBlock();
        Block *rest = head->splitBlock(builder.getInsertionPoint());
        Block *loop = new Block, *body = new Block;
        loop->addArgument(i64, location);
        head->getParent()->getBlocks().insert(rest->getIterator(), loop);
        head->getParent()->getBlocks().insert(rest->getIterator(), body);
        builder.setInsertionPointToEnd(head);
        LLVM::BrOp::create(builder, location, ValueRange{constant(location, 0)},
                           loop);
        builder.setInsertionPointToStart(loop);
        Value word = loop->getArgument(0);
        Value more =
            LLVM::ICmpOp::create(builder, location, LLVM::ICmpPredicate::ult,
                                 word, constant(location, words));
        LLVM::CondBrOp::create(builder, location, more, body, rest);
        builder.setInsertionPointToStart(body);
        Value at = LLVM::ShlOp::create(builder, location, word,
                                       constant(location, 3));
        publishAt(UINT64_MAX, at, 8);
        LLVM::BrOp::create(
            builder, location,
            ValueRange{LLVM::AddOp::create(builder, location, word,
                                           constant(location, 1))},
            loop);
        builder.setInsertionPointToStart(rest);
        first = words * 8;
      }
      for (uint64_t at = first; at < total; at += 8)
        publishAt(at, constant(location, at),
                  static_cast<unsigned>(std::min<uint64_t>(8, total - at)));
    }
  }
};
} // namespace

LogicalResult materializeNativePromotionWrites(ModuleOp module) {
  auto hook = module.lookupSymbol<LLVM::LLVMFuncOp>(
      "__talos_eval_promotion_invalidate_range_v1");
  auto dependencies =
      module.lookupSymbol<LLVM::GlobalOp>("__talos_eval_proof_dependencies_v1");
  if (!hook || !dependencies)
    return success();
  auto coverage =
      ::talos::schedule::get<::talos::schedule::Field::EvalProofCoverage>(
          dependencies);
  if (!coverage || coverage.size() % 2)
    return dependencies.emitError("missing verified proof coverage");
  ::talos::schedule::remove<::talos::schedule::Field::EvalProofCoverage>(
      dependencies);
  MLIRContext *context = module.getContext();
  OpBuilder builder(context);
  Location location = hook.getLoc();
  Type i64 = builder.getI64Type();
  Type voidType = LLVM::LLVMVoidType::get(context);
  auto maskHook = getOrDeclareGeneratedFunction(
      module, "__talos_eval_promotion_invalidate_mask_v1", voidType,
      {i64, i64});
  maskHook->setAttr("passthrough",
                    builder.getArrayAttr({builder.getStringAttr("cold"),
                                          builder.getStringAttr("noinline")}));
  Block *entry = maskHook.addEntryBlock(builder);
  Block *loop = new Block, *visit = new Block, *done = new Block;
  loop->addArgument(i64, location);
  maskHook.getBody().push_back(loop);
  maskHook.getBody().push_back(visit);
  maskHook.getBody().push_back(done);
  builder.setInsertionPointToStart(entry);
  LLVM::BrOp::create(builder, location, ValueRange{entry->getArgument(1)},
                     loop);
  builder.setInsertionPointToStart(loop);
  Value mask = loop->getArgument(0);
  Value nonempty =
      LLVM::ICmpOp::create(builder, location, LLVM::ICmpPredicate::ne, mask,
                           llvmConstant(builder, location, i64, 0));
  LLVM::CondBrOp::create(builder, location, nonempty, visit, done);
  builder.setInsertionPointToStart(visit);
  Value first =
      LLVM::CountTrailingZerosOp::create(builder, location, i64, mask, true);
  Value shifted = LLVM::LShrOp::create(builder, location, mask, first);
  Value complement =
      LLVM::XOrOp::create(builder, location, shifted,
                          llvmConstant(builder, location, i64, UINT64_MAX));
  // Zero is defined as 64 here: a complete changed word is one range. Clearing
  // the lowest run by modular addition avoids an undefined shift by 64.
  Value width = LLVM::CountTrailingZerosOp::create(builder, location, i64,
                                                   complement, false);
  Value offset =
      LLVM::AddOp::create(builder, location, entry->getArgument(0), first);
  LLVM::CallOp::create(builder, location, hook, ValueRange{offset, width});
  Value lowest = LLVM::ShlOp::create(
      builder, location, llvmConstant(builder, location, i64, 1), first);
  Value next =
      LLVM::AndOp::create(builder, location, mask,
                          LLVM::AddOp::create(builder, location, mask, lowest));
  LLVM::BrOp::create(builder, location, ValueRange{next}, loop);
  builder.setInsertionPointToStart(done);
  LLVM::ReturnOp::create(builder, location, ValueRange{});

  builder.setInsertionPointAfter(maskHook);
  auto recheckMask =
      cast<LLVM::LLVMFuncOp>(builder.clone(*maskHook.getOperation()));
  recheckMask.setSymName("__talos_eval_promotion_recheck_mask_v1");
  recheckMask.walk([&](LLVM::CallOp call) {
    if (call.getCallee() == hook.getSymName())
      call.setCallee("__talos_eval_promotion_recheck_range_v1");
  });
  auto publish = getOrDeclareGeneratedFunction(
      module, "__talos_eval_promotion_publish_unknown_v1", voidType,
      {i64, i64, i64});
  // All state inputs are explicit old/new unknown-mask deltas. The callees
  // invalidate/recheck proof metadata without acquiring state or running an
  // observer. Physical state may stay local while this ordered action runs.
  schedule::set(publish, schedule::Field::EvalStateMetadataOnly,
                builder.getUnitAttr());
  publish->setAttr("passthrough", maskHook->getAttr("passthrough"));
  // Publishing is the only call in most generated bodies, and it is cold. A
  // callee that preserves the scratch registers lets a caller keep its values
  // in them across the call, so shrink-wrapping confines the caller's frame to
  // the cold block. This is a generated-code ABI choice; every call site above
  // uses the same convention.
  publish.setCConv(LLVM::cconv::CConv::PreserveMost);
  // Constant-offset publications name their window; they are resolved to a
  // static certificate list once every function has published
  // (materializeNativePromotionWindows).
  auto publishAt = getOrDeclareGeneratedFunction(
      module, "__talos_eval_promotion_publish_at_v1", voidType,
      {i64, i64, i64});
  schedule::set(publishAt, schedule::Field::EvalStateMetadataOnly,
                builder.getUnitAttr());
  publishAt.setCConv(LLVM::cconv::CConv::PreserveMost);
  Block *publication = publish.addEntryBlock(builder);
  builder.setInsertionPointToStart(publication);
  Value changedMask = publication->getArgument(1);
  Value newUnknown = publication->getArgument(2);
  Value lost = LLVM::AndOp::create(builder, location, changedMask, newUnknown);
  Value gained = LLVM::XOrOp::create(builder, location, changedMask, lost);
  LLVM::CallOp::create(builder, location, maskHook,
                       ValueRange{publication->getArgument(0), lost});
  LLVM::CallOp::create(builder, location, recheckMask,
                       ValueRange{publication->getArgument(0), gained});
  LLVM::ReturnOp::create(builder, location, ValueRange{});

  return success();
}

LogicalResult materializeNativePromotionWindows(ModuleOp module) {
  auto publishAt = module.lookupSymbol<LLVM::LLVMFuncOp>(
      "__talos_eval_promotion_publish_at_v1");
  auto dependencies =
      module.lookupSymbol<LLVM::GlobalOp>("__talos_eval_proof_dependencies_v1");
  DenseI64ArrayAttr flat;
  if (dependencies) {
    flat = ::talos::schedule::get<::talos::schedule::Field::EvalProofEntries>(
        dependencies);
    ::talos::schedule::remove<::talos::schedule::Field::EvalProofEntries>(
        dependencies);
  }
  // Read below while resolving windows, removed at the end.
  auto removeSlices = llvm::make_scope_exit([&] {
    if (dependencies)
      ::talos::schedule::remove<::talos::schedule::Field::EvalProofSlices>(
          dependencies);
  });
  if (!publishAt)
    return success();
  SmallVector<LLVM::CallOp> calls;
  module.walk([&](LLVM::CallOp call) {
    if (call.getCallee() == publishAt.getSymName())
      calls.push_back(call);
  });
  if (calls.empty()) {
    publishAt.erase();
    return success();
  }
  if (!dependencies || !flat || flat.size() % 3)
    return publishAt.emitError("window publication without proof entries");
  ArrayRef<int64_t> sliceRanges;
  DenseI64ArrayAttr slicesAttr =
      ::talos::schedule::get<::talos::schedule::Field::EvalProofSlices>(
          dependencies);
  if (slicesAttr)
    sliceRanges = slicesAttr.asArrayRef();

  // Dependencies up to this width are found by their begin; wider ones
  // (whole memories) are few and checked one by one.
  constexpr uint64_t kNarrowBits = 4096;
  struct Entry {
    uint64_t begin, end, certificate;
  };
  std::vector<Entry> narrow, wide;
  for (size_t index = 0; index < flat.size(); index += 3) {
    Entry entry{uint64_t(flat[index]), uint64_t(flat[index + 1]),
                uint64_t(flat[index + 2])};
    (entry.end - entry.begin <= kNarrowBits ? narrow : wide).push_back(entry);
  }
  llvm::sort(narrow, [](const Entry &left, const Entry &right) {
    return left.begin < right.begin;
  });
  // The window [low, low + 64)'s certificates and the bits each covers.
  auto resolve = [&](uint64_t low) {
    llvm::MapVector<uint64_t, uint64_t> masks;
    auto add = [&](const Entry &entry) {
      uint64_t high = low + 64;
      if (entry.end <= low || entry.begin >= high)
        return;
      uint64_t first = std::max(entry.begin, low) - low;
      uint64_t last = std::min(entry.end, high) - low;
      uint64_t bits = last - first == 64 ? UINT64_MAX
                                         : ((uint64_t{1} << (last - first)) - 1)
                                               << first;
      masks[entry.certificate] |= bits;
    };
    uint64_t from = low > kNarrowBits ? low - kNarrowBits : 0;
    auto it = llvm::lower_bound(narrow, from, [](const Entry &entry,
                                                 uint64_t value) {
      return entry.begin < value;
    });
    for (; it != narrow.end() && it->begin < low + 64; ++it)
      add(*it);
    for (const Entry &entry : wide)
      add(entry);
    SmallVector<uint64_t> records;
    for (auto [certificate, mask] : masks)
      llvm::append_range(records, ArrayRef<uint64_t>{mask, certificate});
    // Overlapping promotion slices, named with bit 63 set.
    for (size_t slice = 0; slice < sliceRanges.size() / 2; ++slice) {
      uint64_t begin = uint64_t(sliceRanges[2 * slice]);
      uint64_t end = uint64_t(sliceRanges[2 * slice + 1]);
      uint64_t first = std::max(begin, low), last = std::min(end, low + 64);
      if (first >= last)
        continue;
      uint64_t span = last - first;
      uint64_t bits = (span == 64 ? UINT64_MAX : (uint64_t{1} << span) - 1)
                      << (first - low);
      llvm::append_range(records,
                         ArrayRef<uint64_t>{bits, slice | (uint64_t{1} << 63)});
    }
    return records;
  };

  MLIRContext *context = module.getContext();
  OpBuilder builder(context);
  Location location = publishAt.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i64 = builder.getI64Type();
  Type voidType = LLVM::LLVMVoidType::get(context);
  auto runtimeWindow = declareNativeRuntime(
      module, NativeRuntimeEntry::NativePromotionPublishWindow);
  auto window = getOrDeclareGeneratedFunction(
      module, "__talos_eval_promotion_publish_window_v1", voidType,
      {pointer, i64, i64, i64});
  // Cold, like the range publication it replaces, and preserving the
  // caller's scratch registers so the store's frame stays in its cold block.
  window->setAttr("passthrough",
                  builder.getArrayAttr({builder.getStringAttr("cold"),
                                        builder.getStringAttr("noinline")}));
  window.setCConv(LLVM::cconv::CConv::PreserveMost);
  schedule::set(window, schedule::Field::EvalStateMetadataOnly,
                builder.getUnitAttr());
  {
    Block *entry = window.addEntryBlock(builder);
    builder.setInsertionPointToStart(entry);
    auto address = [&](StringRef name) -> Value {
      return LLVM::AddressOfOp::create(builder, location, pointer, name);
    };
    LLVM::CallOp::create(
        builder, location, runtimeWindow,
        ValueRange{entry->getArgument(0), entry->getArgument(1),
                   address("__talos_eval_proof_certificates_v1"),
                   address("__talos_eval_proof_aggregate_invalidate_v1"),
                   address("__talos_eval_proof_aggregate_recheck_v1"),
                   entry->getArgument(2), entry->getArgument(3),
                   slicesAttr ? address("__talos_eval_promotion_slices_v1")
                              : LLVM::ZeroOp::create(builder, location, pointer)
                                    .getResult()});
    LLVM::ReturnOp::create(builder, location, ValueRange{});
  }

  llvm::DenseMap<uint64_t, std::pair<LLVM::GlobalOp, uint64_t>> windows;
  for (LLVM::CallOp call : calls) {
    APInt constant;
    if (!matchPattern(call.getArgOperands()[0], m_ConstantInt(&constant)) ||
        constant.getActiveBits() > 64)
      return call.emitError("window publication needs a constant offset");
    uint64_t low = constant.getZExtValue();
    auto found = windows.find(low);
    if (found == windows.end()) {
      SmallVector<uint64_t> records = resolve(low);
      LLVM::GlobalOp global;
      if (!records.empty()) {
        builder.setInsertionPointToStart(module.getBody());
        auto type = LLVM::LLVMArrayType::get(i64, records.size());
        global = LLVM::GlobalOp::create(
            builder, location, type, true, LLVM::Linkage::Internal,
            ("__talos_eval_promotion_window_" + llvm::Twine(low) + "_v1")
                .str(),
            DenseIntElementsAttr::get(
                RankedTensorType::get({int64_t(records.size())}, i64),
                ArrayRef<uint64_t>(records)),
            8);
      }
      found = windows.try_emplace(low, global, records.size() / 2).first;
    }
    auto [global, count] = found->second;
    builder.setInsertionPoint(call);
    // No proof reads this window: its X/Z changes break no certificate.
    if (global) {
      Value records = LLVM::AddressOfOp::create(builder, call.getLoc(),
                                                pointer, global.getSymName());
      LLVM::CallOp::create(
          builder, call.getLoc(), window,
          ValueRange{records, llvmConstant(builder, call.getLoc(), i64, count),
                     call.getArgOperands()[1], call.getArgOperands()[2]})
          .setCConv(LLVM::cconv::CConv::PreserveMost);
    }
    call.erase();
  }
  publishAt.erase();
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos proof windows: calls=" << calls.size()
                 << " windows=" << windows.size() << '\n';
  return success();
}

LogicalResult prepareNativeProofPublicationInputs(ModuleOp module,
                                                  AnalysisManager manager) {
  const auto &inputs = manager.getAnalysis<NativeProofPublicationInputs>();
  if (!inputs.valid)
    return failure();
  // Function passes may report an unbounded bulk write through the range
  // hook; they must not add module symbols themselves.
  if (inputs.active) {
    OpBuilder builder(module.getContext());
    Type i64 = builder.getI64Type();
    getOrDeclareGeneratedFunction(
        module, "__talos_eval_promotion_invalidate_range_v1",
        LLVM::LLVMVoidType::get(module.getContext()), {i64, i64});
  }
  return materializeNativePromotionWrites(module);
}

std::unique_ptr<Pass> createPublishNativeFunctionProofsPass() {
  return std::make_unique<PublishNativeFunctionProofsPass>();
}

} // namespace talos::detail

namespace talos {
namespace {
class MaterializeNativePromotionRangeIndexPass final
    : public impl::MaterializeNativePromotionRangeIndexPassBase<
          MaterializeNativePromotionRangeIndexPass> {
public:
  using Base::Base;

  void runOnOperation() override {
    if (failed(detail::materializeNativePromotionRangeIndex(getOperation(),
                                                            bucketMinEntries)))
      signalPassFailure();
  }
};
} // namespace
} // namespace talos
