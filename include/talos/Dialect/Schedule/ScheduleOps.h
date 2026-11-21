#ifndef TALOS_DIALECT_SCHEDULE_SCHEDULEOPS_H
#define TALOS_DIALECT_SCHEDULE_SCHEDULEOPS_H
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "talos/Dialect/Runtime/RuntimeTypes.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Simulation/SimulationAttrs.h"
#include "talos/Dialect/Simulation/SimulationResources.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include <optional>
namespace talos::schedule {
/// The global that holds a canonical native state plane.
llvm::StringRef getStatePlaneGlobalName(StatePlane plane);
/// Whether `plane` is a canonical plane of design state, whose global holds
/// its bytes; a contribution plane's global holds a pointer to them.
inline bool isCanonicalStatePlane(StatePlane plane) {
  return plane == StatePlane::Value || plane == StatePlane::Unknown;
}
/// The state plane a global holds, if it is one.
std::optional<StatePlane> getStatePlaneOfGlobal(llvm::StringRef name);
/// Whether `range` is a well-formed state access `window`: physical bytes
/// [begin, end) with 0 <= begin <= end.
bool isValidStateWindow(llvm::ArrayRef<int64_t> range);
/// Whether `range` is a well-formed `written_bits`: [begin, width] bits with
/// begin >= 0 and width > 0.
bool isValidStateWrittenBits(llvm::ArrayRef<int64_t> range);
/// The global that holds an NBA readiness index.
llvm::StringRef getNBAIndexGlobalName(NBAIndex index);
/// The NBA readiness index a global holds, if it is one.
std::optional<NBAIndex> getNBAIndexOfGlobal(llvm::StringRef name);
/// The global that holds a generated eval ready set.
llvm::StringRef getReadySetGlobalName(ReadySet set);
/// The generated eval ready set a global holds, if it is one.
std::optional<ReadySet> getReadySetOfGlobal(llvm::StringRef name);
/// The global that holds a generated eval mask.
llvm::StringRef getEvalMaskGlobalName(EvalMask mask);
/// The generated eval mask a global holds, if it is one.
std::optional<EvalMask> getEvalMaskOfGlobal(llvm::StringRef name);
/// The bytes a generated NBA accumulator field spans in the four-state
/// record (talos_rt_generated_nba_accumulator_256): four words for a bit
/// field, one 32-bit word for `valid` and `exec_region`.
uint64_t getNBAAccumulatorFieldBytes(NBAAccumulatorField field);
} // namespace talos::schedule
#define GET_OP_CLASSES
#include "talos/Dialect/Schedule/ScheduleOps.h.inc"
namespace talos::schedule {
uint32_t getNativeWaitEntryCount(mlir::Operation *operation);
}
#endif
