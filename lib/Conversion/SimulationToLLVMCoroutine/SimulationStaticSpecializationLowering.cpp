//===- SimulationStaticSpecializationLowering.cpp - Native guards -------===//

#include "SimulationToLLVMCoroutinePrivate.h"

#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace talos::detail {
namespace {

constexpr int32_t likelyBranchWeight = (1 << 20) - 1;
constexpr int32_t unlikelyBranchWeight = 1;

Value loadStaticSpecializationFast(ConversionPatternRewriter &rewriter,
                                   Location location, bool nba = false) {
  Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
  IntegerType i32 = rewriter.getI32Type();
  Value fastAddress =
      LLVM::AddressOfOp::create(rewriter, location, pointer,
                                nba ? "__talos_static_specialization_fast_v1"
                                    : "__talos_state_specialization_fast_v1");
  Value fast = LLVM::LoadOp::create(rewriter, location, i32, fastAddress, 4);
  return arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::ne, fast,
      llvmConstant(rewriter, location, i32, uint32_t{0}));
}

} // namespace

void markLikelyTrue(cf::CondBranchOp branch) {
  branch.setBranchWeights(
      ArrayRef<int32_t>{likelyBranchWeight, unlikelyBranchWeight});
}

Value staticSpecializationGuard(ConversionPatternRewriter &rewriter,
                                Location location, uint32_t staticID,
                                uint32_t flags) {
  Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
  IntegerType i32 = rewriter.getI32Type();
  Block *head = rewriter.getInsertionBlock();
  Block *continuation = rewriter.splitBlock(head, rewriter.getInsertionPoint());
  BlockArgument result =
      continuation->addArgument(rewriter.getI1Type(), location);
  Region *region = head->getParent();
  Block *slowBlock = rewriter.createBlock(region, continuation->getIterator());

  rewriter.setInsertionPointToEnd(head);
  Value useFast = loadStaticSpecializationFast(rewriter, location);
  Value fastAllowed =
      llvmConstant(rewriter, location, rewriter.getI1Type(), uint32_t{1});
  markLikelyTrue(cf::CondBranchOp::create(rewriter, location, useFast,
                                          continuation, ValueRange{fastAllowed},
                                          slowBlock, ValueRange{}));

  rewriter.setInsertionPointToEnd(slowBlock);
  Value contextAddress = LLVM::AddressOfOp::create(rewriter, location, pointer,
                                                   "__talos_current_context");
  Value context =
      LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
  Value allowed =
      LLVM::CallOp::create(
          rewriter, location, TypeRange{i32},
          getNativeRuntimeCallee(rewriter.getContext(),
                                 NativeRuntimeEntry::StaticSpecializationGuard),
          ValueRange{context, llvmConstant(rewriter, location, i32, UINT32_MAX),
                     llvmConstant(rewriter, location, i32, staticID),
                     llvmConstant(rewriter, location, i32, flags)})
          .getResult();
  Value useDirect = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::ne, allowed,
      llvmConstant(rewriter, location, i32, uint32_t{0}));
  cf::BranchOp::create(rewriter, location, continuation, ValueRange{useDirect});

  rewriter.setInsertionPointToStart(continuation);
  return result;
}

Value staticNBASpecializationGuard(ConversionPatternRewriter &rewriter,
                                   Location location, uint32_t rootIndex,
                                   bool guardedVisibility) {
  Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
  IntegerType i32 = rewriter.getI32Type();
  Block *head = rewriter.getInsertionBlock();
  Block *continuation = rewriter.splitBlock(head, rewriter.getInsertionPoint());
  BlockArgument result =
      continuation->addArgument(rewriter.getI1Type(), location);
  Region *region = head->getParent();
  Block *slowBlock = rewriter.createBlock(region, continuation->getIterator());

  rewriter.setInsertionPointToEnd(head);
  Value useFast =
      loadStaticSpecializationFast(rewriter, location, /*nba=*/true);
  Value fastAllowed =
      llvmConstant(rewriter, location, rewriter.getI1Type(), uint32_t{1});
  markLikelyTrue(cf::CondBranchOp::create(rewriter, location, useFast,
                                          continuation, ValueRange{fastAllowed},
                                          slowBlock, ValueRange{}));

  rewriter.setInsertionPointToEnd(slowBlock);
  Value contextAddress = LLVM::AddressOfOp::create(rewriter, location, pointer,
                                                   "__talos_current_context");
  Value context =
      LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
  StringRef guardName =
      guardedVisibility
          ? getNativeRuntimeSymbol(
                NativeRuntimeEntry::StaticNbaSpecializationGuardWrite)
          : getNativeRuntimeSymbol(
                NativeRuntimeEntry::StaticNbaSpecializationGuard);
  Value allowed =
      LLVM::CallOp::create(
          rewriter, location, TypeRange{i32},
          SymbolRefAttr::get(rewriter.getContext(), guardName),
          ValueRange{context, llvmConstant(rewriter, location, i32, rootIndex)})
          .getResult();
  Value useDirect = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::ne, allowed,
      llvmConstant(rewriter, location, i32, uint32_t{0}));
  cf::BranchOp::create(rewriter, location, continuation, ValueRange{useDirect});

  rewriter.setInsertionPointToStart(continuation);
  return result;
}

} // namespace talos::detail
