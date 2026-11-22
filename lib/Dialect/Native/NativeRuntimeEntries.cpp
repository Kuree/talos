//===- NativeRuntimeEntries.cpp - Native runtime entry catalog ------------===//

#include "talos/Dialect/Native/NativeRuntimeEntries.h"
#include "talos/Dialect/Native/NativeDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/STLExtras.h"

#include <vector>

namespace talos {
using namespace native_runtime;
using llvm::ArrayRef;
using llvm::StringRef;

std::optional<NativeRuntimeEntry>
getNativeRuntimeEntry(llvm::StringRef callee) {
  using Row = std::pair<StringRef, NativeRuntimeEntry>;
  // The rows sorted by symbol, built once.
  static const std::vector<Row> rows = [] {
    std::vector<Row> rows = {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  {#symbol, NativeRuntimeEntry::Enum},
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
    };
    llvm::sort(rows, llvm::less_first());
    return rows;
  }();
  auto row = llvm::lower_bound(rows, callee, [](const Row &row, StringRef key) {
    return row.first < key;
  });
  if (row == rows.end() || row->first != callee)
    return std::nullopt;
  return row->second;
}

uint32_t getNativeRuntimeEffects(NativeRuntimeEntry entry) {
  switch (entry) {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  case NativeRuntimeEntry::Enum:                                               \
    return effects;
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
  }
  return None;
}

bool hasNativeRuntimeEffect(llvm::StringRef callee, Effect effect) {
  std::optional<NativeRuntimeEntry> entry = getNativeRuntimeEntry(callee);
  return entry && (getNativeRuntimeEffects(*entry) & effect) == effect;
}

ArrayRef<native_runtime::Type>
getNativeRuntimeSignature(NativeRuntimeEntry entry) {
#define SIG(...) __VA_ARGS__
  switch (entry) {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  case NativeRuntimeEntry::Enum: {                                             \
    static constexpr native_runtime::Type types[] = {signature};               \
    return types;                                                              \
  }
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
  }
#undef SIG
  return {};
}

mlir::FlatSymbolRefAttr getNativeRuntimeCallee(mlir::MLIRContext *context,
                                               NativeRuntimeEntry entry) {
  return mlir::FlatSymbolRefAttr::get(context, getNativeRuntimeSymbol(entry));
}

mlir::LLVM::LLVMFunctionType
getNativeRuntimeFunctionType(mlir::MLIRContext *context,
                             NativeRuntimeEntry entry) {
  auto toLLVM = [&](native_runtime::Type type) -> mlir::Type {
    switch (type) {
    case V:
      return mlir::LLVM::LLVMVoidType::get(context);
    case I1:
      return mlir::IntegerType::get(context, 1);
    case I8:
      return mlir::IntegerType::get(context, 8);
    case I16:
      return mlir::IntegerType::get(context, 16);
    case I32:
      return mlir::IntegerType::get(context, 32);
    case I64:
      return mlir::IntegerType::get(context, 64);
    case F32:
      return mlir::Float32Type::get(context);
    case F64:
      return mlir::Float64Type::get(context);
    case Ptr:
      return mlir::LLVM::LLVMPointerType::get(context);
    }
    llvm_unreachable("unknown native runtime type");
  };
  ArrayRef<native_runtime::Type> signature = getNativeRuntimeSignature(entry);
  llvm::SmallVector<mlir::Type> parameters;
  for (native_runtime::Type parameter : signature.drop_front())
    parameters.push_back(toLLVM(parameter));
  return mlir::LLVM::LLVMFunctionType::get(toLLVM(signature.front()),
                                           parameters,
                                           /*isVarArg=*/false);
}

mlir::LLVM::LLVMFuncOp
createNativeRuntimeDeclaration(mlir::OpBuilder &builder,
                               mlir::Location location,
                               NativeRuntimeEntry entry) {
  mlir::MLIRContext *context = builder.getContext();
  auto function = mlir::LLVM::LLVMFuncOp::create(
      builder, location, getNativeRuntimeSymbol(entry),
      getNativeRuntimeFunctionType(context, entry));
  native::set<native::RuntimeEntry>(
      function, native::RuntimeEntryAttr::get(context, entry));
  // Generated code reaches queue growth only from a capacity test, so the
  // optimizer lays that arm out of line. (The failure latch is not cold: it
  // is called unconditionally with a status and tests it itself.)
  if (getNativeRuntimeEffects(entry) & Cold)
    function.setPassthroughAttr(
        builder.getArrayAttr({builder.getStringAttr("cold")}));
  return function;
}

mlir::LLVM::LLVMFuncOp declareNativeRuntime(mlir::ModuleOp module,
                                            NativeRuntimeEntry entry) {
  StringRef symbol = getNativeRuntimeSymbol(entry);
  if (auto existing = module.lookupSymbol<mlir::LLVM::LLVMFuncOp>(symbol)) {
    // A call built from the returned declaration then fails verification.
    if (existing.getFunctionType() !=
        getNativeRuntimeFunctionType(module.getContext(), entry))
      existing.emitOpError() << "runtime symbol @" << symbol
                             << " is predeclared with an incompatible type";
    return existing;
  }
  mlir::OpBuilder builder(module.getContext());
  builder.setInsertionPointToStart(module.getBody());
  return createNativeRuntimeDeclaration(builder, module.getLoc(), entry);
}

void declareNativeRuntimes(mlir::ModuleOp module,
                           ArrayRef<NativeRuntimeEntry> entries) {
  for (NativeRuntimeEntry entry : entries)
    declareNativeRuntime(module, entry);
}

llvm::LogicalResult verifyNativeRuntimeDeclarations(mlir::ModuleOp module) {
  bool valid = true;
  for (auto function : module.getOps<mlir::LLVM::LLVMFuncOp>()) {
    std::optional<NativeRuntimeEntry> entry =
        getNativeRuntimeEntry(function.getSymName());
    if (!entry || function.getFunctionType() ==
                      getNativeRuntimeFunctionType(module.getContext(), *entry))
      continue;
    function.emitOpError() << "runtime symbol @" << function.getSymName()
                           << " is predeclared with an incompatible type";
    valid = false;
  }
  return llvm::success(valid);
}

} // namespace talos
