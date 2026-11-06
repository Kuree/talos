//===- BytecodeBootstrapTestPass.cpp - Exercise native methods from VM ---===//

#include "AnalysisTestPasses.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;

namespace {
class BytecodeBootstrapTestPass
    : public PassWrapper<BytecodeBootstrapTestPass, OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(BytecodeBootstrapTestPass)
  BytecodeBootstrapTestPass() = default;
  BytecodeBootstrapTestPass(const BytecodeBootstrapTestPass &other)
      : PassWrapper(other) {}
  StringRef getArgument() const final {
    return "test-talos-bytecode-bootstrap";
  }
  StringRef getDescription() const final {
    return "bootstrap a linked native model through its retained bytecode root";
  }
  Option<bool> recordTasks{*this, "record-tasks", llvm::cl::init(false)};

  void runOnOperation() final {
    auto module = getOperation();
    auto root = module.lookupSymbol<LLVM::GlobalOp>(
        "__talos_root.__talos_process_descriptor");
    if (!root) {
      module.emitError("test model has no root process descriptor");
      return signalPassFailure();
    }
    // A bytecode root executes the ordinary spawn intrinsics, giving its
    // children bytecode-owned call stacks. Keep native method entries intact.
    // Changing only a child's descriptor would leave it in a native process
    // instance, which cannot own the interpreter's pending task activations.
    root.walk([&](LLVM::InsertValueOp insert) {
      if (insert->getResult(0).getType() != root.getGlobalType())
        return;
      auto position = insert.getPosition();
      if (position.size() != 1)
        return;
      unsigned field = position.front();
      if (field != 2 && field != 3 && field != 6 && field != 7 && field != 8)
        return;
      OpBuilder builder(insert);
      Value value;
      if (field == 2 || field == 3)
        value = LLVM::ConstantOp::create(
            builder, insert.getLoc(), builder.getI32Type(),
            builder.getI32IntegerAttr(field == 3 ? 2 : 0));
      else
        value = LLVM::ZeroOp::create(builder, insert.getLoc(),
                                     insert.getValue().getType());
      insert.getValueMutable().assign(value);
    });
    if (!recordTasks)
      return;
    OpBuilder builder(module.getContext());
    builder.setInsertionPointToStart(module.getBody());
    auto hook = LLVM::LLVMFuncOp::create(
        builder, module.getLoc(), "talos_test_native_task_entry",
        LLVM::LLVMFunctionType::get(
            LLVM::LLVMVoidType::get(module.getContext()), {}, false));
    unsigned recorded = 0;
    for (auto function : module.getOps<LLVM::LLVMFuncOp>()) {
      if (function.isExternal() ||
          !function.getSymName().ends_with(".__talos_native_sync_thunk"))
        continue;
      builder.setInsertionPointToStart(&function.getBody().front());
      LLVM::CallOp::create(builder, function.getLoc(), TypeRange{},
                           SymbolRefAttr::get(hook), ValueRange{});
      ++recorded;
    }
    if (!recorded) {
      module.emitError("test model has no synchronous native task entries");
      signalPassFailure();
    }
  }
};
} // namespace

namespace talos {
void registerBytecodeBootstrapTestPass() {
  PassRegistration<BytecodeBootstrapTestPass>();
}
} // namespace talos
