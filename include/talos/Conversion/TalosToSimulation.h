//===- TalosToSimulation.h - Semantic to executable sim ----*- C++ -*-===//

#ifndef TALOS_CONVERSION_TALOSTOSIMULATION_H
#define TALOS_CONVERSION_TALOSTOSIMULATION_H

#include "talos/Conversion/Passes.h"

#include "mlir/IR/Location.h"
#include "mlir/IR/Types.h"
#include "mlir/Support/LogicalResult.h"

#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <memory>

namespace mlir {
class OpPassManager;
class Pass;
} // namespace mlir

namespace talos {

/// Canonical C ABI categories supported by the DPI import boundary.
/// Keep these values in sync with dpi::ABIKind; they are serialized into
/// bytecode signature metadata and are therefore part of the internal ABI.
enum class DPIABIKind : uint32_t {
  Bit = 0,
  Logic = 1,
  Byte = 2,
  ShortInt = 3,
  Int = 4,
  LongInt = 5,
  BitVector = 6,
  LogicVector = 7,
  String = 8,
  Chandle = 9,
  ShortReal = 10,
  Real = 11,
  OpenArray = 12,
  UnpackedAggregate = 13,
};

struct DPIABIType {
  DPIABIKind kind;
  uint32_t width;
  bool fourState;
  bool isSigned;

  bool isVector() const {
    return kind == DPIABIKind::BitVector || kind == DPIABIKind::LogicVector;
  }

  bool isIndirect() const {
    return isVector() || kind == DPIABIKind::OpenArray ||
           kind == DPIABIKind::UnpackedAggregate;
  }
};

/// Classify a source-semantic type for the DPI-C ABI. Diagnostics are
/// emitted at `location` for unsupported categories.
mlir::FailureOr<DPIABIType> classifyDPIABIType(mlir::Type type,
                                               mlir::Location location);

/// Exact scalar/vector typedef spelling used by generated DPI headers.
llvm::StringRef getDPICTypeSpelling(const DPIABIType &type);

/// Populate a module pass manager with the serial/parallel/serial lowering.
void buildTalosToSimulationPipeline(mlir::OpPassManager &manager);

/// Populate the lowering pipeline with explicit simulation configuration.
void buildTalosToSimulationPipeline(mlir::OpPassManager &manager,
                                    uint32_t workers, llvm::StringRef vpiMode);

/// Populate the lowering pipeline with explicit simulation and optimization
/// configuration. `optLevel` is in the inclusive range 0 through 3.
void buildTalosToSimulationPipeline(mlir::OpPassManager &manager,
                                    uint32_t workers, llvm::StringRef vpiMode,
                                    uint32_t optLevel);

/// Populate the lowering pipeline with explicit static-state specialization.
/// `staticSpecialization` is auto, off, or on. Auto enables the pass at O2/O3.
/// `clockedKernels` is off, immediate, or deferred (see
/// talos-sim-fuse-clocked-kernels); kernels form at O1 and above.
/// `forwardCopies` is on, off, or census (see
/// talos-sim-forward-copy-processes); it runs at O1 and above with VPI off.
/// `enableUPF` includes power-intent elaboration. The driver disables it when
/// no UPF was requested; standalone IR pipelines retain it by default.
void buildTalosToSimulationPipeline(
    mlir::OpPassManager &manager, uint32_t workers, llvm::StringRef vpiMode,
    uint32_t optLevel, llvm::StringRef staticSpecialization,
    bool earlySymbolDCE = true, llvm::StringRef clockedKernels = "deferred",
    llvm::StringRef forwardCopies = "on", bool enableUPF = true);

/// Register the aggregate serial/parallel/serial lowering pipeline.
void registerTalosToSimulationPipeline();

} // namespace talos

#endif // TALOS_CONVERSION_TALOSTOSIMULATION_H
