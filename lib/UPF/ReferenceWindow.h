#ifndef TALOS_UPF_REFERENCEWINDOW_H
#define TALOS_UPF_REFERENCEWINDOW_H

#include "ControlValue.h"
#include <memory>

namespace talos::upf_detail {
struct ReferenceWindow {
  Descriptor root;
  mlir::Value start, lower, upper, valid;
};

// Freeze IEEE 1800-2023 11.5.1/7.4.5 reference bounds before handles lose
// their projection history. Windows are ordinary SSA across CFG/call/wait
// boundaries; whole root identities are proved from every actual capture.
class ReferenceWindows {
public:
  explicit ReferenceWindows(sim::SimDesignOp design);
  ~ReferenceWindows();
  mlir::FailureOr<Descriptor> getRoot(mlir::Value reference);
  bool isWhole(mlir::Value reference);
  mlir::LogicalResult prepare(llvm::ArrayRef<mlir::Value> references);
  mlir::FailureOr<ReferenceWindow> get(mlir::Value reference);

private:
  struct Impl;
  std::unique_ptr<Impl> impl;
};
} // namespace talos::upf_detail
#endif
