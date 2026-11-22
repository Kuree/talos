//===- NativePartitionTest.cpp - Physical definition cost boundaries ------===//

#include "NativeExecutionCounts.h"
#include "NativeModulePruning.h"
#include "NativePartitionCost.h"
#include "NativeSplitClusters.h"
#include "talos/LLVM/FunctionRoles.h"

#include "mlir/Parser/Parser.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/GenericValue.h"
#include "llvm/ExecutionEngine/Interpreter.h"
#include "llvm/IR/GlobalAlias.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "gtest/gtest.h"

using talos::driver::detail::estimateNativeGlobalWeight;
using namespace llvm;

namespace {

TEST(NativeModulePruning, SymbolDCEKeepsCallbacksAndExports) {
  mlir::MLIRContext context;
  context.loadDialect<mlir::LLVM::LLVMDialect>();
  auto module = mlir::parseSourceString<mlir::ModuleOp>(R"mlir(
    module attributes {test.inventory = [@dead_a, @dead_b]} {
      llvm.func @register_callbacks(!llvm.ptr)
      llvm.func @main() {
        %table = llvm.mlir.addressof @callback_table : !llvm.ptr
        llvm.call @register_callbacks(%table) : (!llvm.ptr) -> ()
        llvm.return
      }
      llvm.mlir.global internal constant @callback_table() : !llvm.ptr {
        %callback = llvm.mlir.addressof @callback : !llvm.ptr
        llvm.return %callback : !llvm.ptr
      }
      llvm.func @callback() { llvm.return }
      llvm.func @foreign_entry() { llvm.return }
      llvm.func @dead_a() {
        llvm.call @dead_b() : () -> ()
        llvm.return
      }
      llvm.func @dead_b() {
        llvm.call @dead_a() : () -> ()
        llvm.return
      }
      llvm.mlir.global internal @unused_data(0 : i64) : i64
    }
  )mlir",
                                                        &context);
  ASSERT_TRUE(module);
  llvm::StringSet<> exports;
  exports.insert("foreign_entry");
  auto removed =
      talos::driver::detail::pruneNativeExecutableSymbols(*module, exports);
  ASSERT_TRUE(mlir::succeeded(removed));
  EXPECT_EQ(removed->size(), 3u);
  EXPECT_TRUE(removed->contains("dead_a"));
  EXPECT_TRUE(removed->contains("dead_b"));
  EXPECT_TRUE(removed->contains("unused_data"));
  for (StringRef name : {"main", "foreign_entry", "callback", "callback_table"})
    EXPECT_NE(module->lookupSymbol(name), nullptr) << name.str();
}

TEST(NativeModulePruning, PreservesExportsAndCallbacksButDropsDeadCycles) {
  LLVMContext context;
  Module module("model", context);
  IRBuilder<> builder(context);
  auto makeFunction = [&](StringRef name) {
    auto *function =
        Function::Create(FunctionType::get(builder.getVoidTy(), false),
                         GlobalValue::ExternalLinkage, name, module);
    builder.SetInsertPoint(BasicBlock::Create(context, "entry", function));
    builder.CreateRetVoid();
    return function;
  };
  auto *main = makeFunction("main");
  auto *callback = makeFunction("callback");
  auto *exported = makeFunction("foreign_entry");
  auto *deadA = makeFunction("dead_a");
  auto *deadB = makeFunction("dead_b");
  builder.SetInsertPoint(deadA->getEntryBlock().getTerminator());
  builder.CreateCall(deadB);
  builder.SetInsertPoint(deadB->getEntryBlock().getTerminator());
  builder.CreateCall(deadA);
  auto *table = new GlobalVariable(module, callback->getType(), true,
                                   GlobalValue::InternalLinkage, callback,
                                   "callback_table");
  auto registration = module.getOrInsertFunction(
      "register_callbacks", builder.getVoidTy(), builder.getPtrTy());
  builder.SetInsertPoint(main->getEntryBlock().getTerminator());
  builder.CreateCall(registration, {table});
  llvm::StringSet<> exports;
  exports.insert("foreign_entry");
  auto removed =
      talos::driver::detail::pruneNativeExecutableModel(module, exports);
  EXPECT_TRUE(removed.contains("dead_a"));
  EXPECT_TRUE(removed.contains("dead_b"));
  EXPECT_EQ(removed.size(), 2u);
  EXPECT_NE(module.getFunction("callback"), nullptr);
  EXPECT_NE(module.getNamedGlobal("callback_table"), nullptr);
  EXPECT_FALSE(main->hasLocalLinkage());
  EXPECT_FALSE(exported->hasLocalLinkage());
  EXPECT_TRUE(callback->hasLocalLinkage());
  EXPECT_FALSE(verifyModule(module, &errs()));
}

TEST(NativeExecutionCounts, RequiresMainWithoutMutatingLibraryModule) {
  LLVMContext context;
  Module module("library", context);
  EXPECT_FALSE(talos::driver::detail::addNativeExecutionCounts(module));
  EXPECT_TRUE(module.empty());
  EXPECT_TRUE(module.global_empty());
}

TEST(NativeExecutionCounts, NoExecutorHasNoInstrumentationCost) {
  LLVMContext context;
  Module module("empty", context);
  IRBuilder<> builder(context);
  auto *main = Function::Create(FunctionType::get(builder.getInt32Ty(), false),
                                GlobalValue::ExternalLinkage, "main", module);
  builder.SetInsertPoint(BasicBlock::Create(context, "entry", main));
  builder.CreateRet(builder.getInt32(0));
  EXPECT_TRUE(talos::driver::detail::addNativeExecutionCounts(module));
  EXPECT_EQ(module.size(), 1u);
  EXPECT_EQ(main->getInstructionCount(), 1u);
  EXPECT_TRUE(module.global_empty());
}

// Splitting counts by simulation time asks the runtime for the time through
// the scheduler_time entry, declared with its catalog prototype, i64(ptr).
TEST(NativeExecutionCounts, PhaseQueriesTheCatalogTimeEntry) {
  LLVMContext context;
  Module module("phase", context);
  IRBuilder<> builder(context);
  auto *main = Function::Create(FunctionType::get(builder.getInt32Ty(), false),
                                GlobalValue::ExternalLinkage, "main", module);
  builder.SetInsertPoint(BasicBlock::Create(context, "entry", main));
  builder.CreateRet(builder.getInt32(0));
  auto *ramp = Function::Create(FunctionType::get(builder.getVoidTy(), false),
                                GlobalValue::ExternalLinkage,
                                "p.__talos_coro_ramp", module);
  builder.SetInsertPoint(BasicBlock::Create(context, "entry", ramp));
  builder.CreateRetVoid();
  new GlobalVariable(
      module, builder.getPtrTy(), false, GlobalValue::InternalLinkage,
      ConstantPointerNull::get(builder.getPtrTy()), "__talos_current_context");
  ASSERT_TRUE(talos::driver::detail::addNativeExecutionCounts(module));
  Function *time = module.getFunction("talos_rt_v1_scheduler_time");
  ASSERT_NE(time, nullptr);
  EXPECT_TRUE(time->isDeclaration());
  EXPECT_EQ(time->getFunctionType(),
            talos::driver::detail::getNativeRuntimeIRFunctionType(
                context, talos::NativeRuntimeEntry::SchedulerTime));
  EXPECT_EQ(
      time->getFunctionType(),
      FunctionType::get(builder.getInt64Ty(), {builder.getPtrTy()}, false));
  EXPECT_FALSE(verifyModule(module, &errs()));
}

TEST(NativeExecutionCounts, ReportsBothExitsAndKeepsDistinctDomainEntries) {
  LLVMContext context;
  Module module("entries", context);
  IRBuilder<> builder(context);
  auto *type = FunctionType::get(builder.getVoidTy(), false);
  for (StringRef name :
       {"__talos_eval_ranked_group_0", "__talos_eval_ranked_group_0.dataflow",
        "__talos_eval_dispatch_v1", "unrelated"}) {
    auto *function =
        Function::Create(type, GlobalValue::ExternalLinkage, name, module);
    function->addFnAttr(Attribute::Speculatable);
    builder.SetInsertPoint(BasicBlock::Create(context, "entry", function));
    builder.CreateRetVoid();
  }
  auto *main = Function::Create(
      FunctionType::get(builder.getInt32Ty(), {builder.getInt1Ty()}, false),
      GlobalValue::ExternalLinkage, "main", module);
  auto *entry = BasicBlock::Create(context, "entry", main);
  auto *success = BasicBlock::Create(context, "success", main);
  auto *failure = BasicBlock::Create(context, "failure", main);
  builder.SetInsertPoint(entry);
  builder.CreateCondBr(main->getArg(0), success, failure);
  builder.SetInsertPoint(success);
  auto *invoke =
      builder.CreateCall(module.getFunction("__talos_eval_ranked_group_0"));
  invoke->addFnAttr(Attribute::Speculatable);
  builder.CreateRet(builder.getInt32(0));
  builder.SetInsertPoint(failure);
  builder.CreateRet(builder.getInt32(1));
  ASSERT_TRUE(talos::driver::detail::addNativeExecutionCounts(module));
  EXPECT_FALSE(verifyModule(module, &errs()));
  auto *counts = module.getNamedGlobal("__talos_execution_counts");
  ASSERT_NE(counts, nullptr);
  EXPECT_EQ(cast<ArrayType>(counts->getValueType())->getNumElements(), 3u);
  EXPECT_TRUE(counts->getInitializer()->isNullValue());
  EXPECT_EQ(module.getFunction("unrelated")->getInstructionCount(), 1u);
  EXPECT_FALSE(module.getFunction("__talos_eval_ranked_group_0")
                   ->hasFnAttribute(Attribute::Speculatable));
  EXPECT_FALSE(invoke->hasFnAttr(Attribute::Speculatable));
  for (BasicBlock *block : {success, failure}) {
    auto *call = dyn_cast<CallInst>(block->getTerminator()->getPrevNode());
    ASSERT_NE(call, nullptr);
    EXPECT_EQ(call->getCalledFunction()->getName(),
              "__talos_execution_counts_report");
  }
}

TEST(NativeExecutionCounts, CountsTakenLoopIterationsAcrossInvocations) {
  LLVMContext context;
  auto module = std::make_unique<Module>("executed-counts", context);
  module->setDataLayout("e-p:64:64-i64:64-n8:16:32:64-S128");
  IRBuilder<> builder(context);
  auto *leaf = Function::Create(FunctionType::get(builder.getVoidTy(), false),
                                GlobalValue::ExternalLinkage,
                                "__talos_eval_ranked_group_0", *module);
  builder.SetInsertPoint(BasicBlock::Create(context, "entry", leaf));
  builder.CreateRetVoid();
  auto *dispatch = Function::Create(
      FunctionType::get(builder.getVoidTy(), {builder.getInt64Ty()}, false),
      GlobalValue::ExternalLinkage, "__talos_eval_dispatch_v1", *module);
  auto *entry = BasicBlock::Create(context, "entry", dispatch);
  auto *loop = BasicBlock::Create(context, "loop", dispatch);
  auto *body = BasicBlock::Create(context, "body", dispatch);
  auto *done = BasicBlock::Create(context, "done", dispatch);
  builder.SetInsertPoint(entry);
  builder.CreateBr(loop);
  builder.SetInsertPoint(loop);
  auto *remaining = builder.CreatePHI(builder.getInt64Ty(), 2);
  remaining->addIncoming(dispatch->getArg(0), entry);
  builder.CreateCondBr(builder.CreateICmpEQ(remaining, builder.getInt64(0)),
                       done, body);
  builder.SetInsertPoint(body);
  builder.CreateCall(leaf);
  remaining->addIncoming(builder.CreateSub(remaining, builder.getInt64(1)),
                         body);
  builder.CreateBr(loop);
  builder.SetInsertPoint(done);
  builder.CreateRetVoid();
  auto *main = Function::Create(FunctionType::get(builder.getInt32Ty(), false),
                                GlobalValue::ExternalLinkage, "main", *module);
  builder.SetInsertPoint(BasicBlock::Create(context, "entry", main));
  builder.CreateRet(builder.getInt32(0));
  ASSERT_TRUE(talos::driver::detail::addNativeExecutionCounts(*module));
  auto *counts = module->getNamedGlobal("__talos_execution_counts");
  auto *read = Function::Create(
      FunctionType::get(builder.getInt64Ty(), {builder.getInt64Ty()}, false),
      GlobalValue::ExternalLinkage, "read_count", *module);
  builder.SetInsertPoint(BasicBlock::Create(context, "entry", read));
  builder.CreateRet(builder.CreateLoad(
      builder.getInt64Ty(),
      builder.CreateInBoundsGEP(counts->getValueType(), counts,
                                {builder.getInt32(0), read->getArg(0)})));
  ASSERT_FALSE(verifyModule(*module, &errs()));
  std::string error;
  std::unique_ptr<ExecutionEngine> engine(
      EngineBuilder(std::move(module))
          .setEngineKind(EngineKind::Interpreter)
          .setErrorStr(&error)
          .create());
  ASSERT_NE(engine, nullptr) << error;
  GenericValue argument;
  for (unsigned iterations : {0, 3, 5}) {
    argument.IntVal = APInt(64, iterations);
    engine->runFunction(dispatch, {argument});
  }
  argument.IntVal = APInt(64, 0);
  EXPECT_EQ(engine->runFunction(read, {argument}).IntVal.getZExtValue(), 3u);
  argument.IntVal = APInt(64, 1);
  EXPECT_EQ(engine->runFunction(read, {argument}).IntVal.getZExtValue(), 8u);
}

TEST(NativePartitionCost, ReferencedInitializerIsChargedOnlyToItsDefinition) {
  LLVMContext context;
  Module module("references", context);
  auto *type = ArrayType::get(Type::getInt32Ty(context), 1024);
  auto *payload =
      new GlobalVariable(module, type, true, GlobalValue::InternalLinkage,
                         ConstantAggregateZero::get(type), "payload");
  auto *reference =
      new GlobalVariable(module, payload->getType(), true,
                         GlobalValue::InternalLinkage, payload, "reference");
  uint64_t referenceWeight = estimateNativeGlobalWeight(*reference);
  uint64_t payloadWeight = estimateNativeGlobalWeight(*payload);
  SmallVector<uint32_t> values(1024, 7);
  payload->setInitializer(ConstantDataArray::get(context, values));
  EXPECT_GT(estimateNativeGlobalWeight(*payload), payloadWeight);
  EXPECT_EQ(estimateNativeGlobalWeight(*reference), referenceWeight);
}

TEST(NativePartitionCost, CyclicReferenceGraphDoesNotChangeLocalWeights) {
  LLVMContext context;
  Module module("cycle", context);
  auto *pointer = PointerType::getUnqual(context);
  SmallVector<GlobalVariable *> globals;
  for (unsigned index = 0; index != 257; ++index)
    globals.push_back(new GlobalVariable(
        module, pointer, true, GlobalValue::InternalLinkage,
        ConstantPointerNull::get(pointer), "node" + Twine(index)));
  uint64_t localWeight = estimateNativeGlobalWeight(*globals.front());
  // Multiplication by 17 permutes this prime-sized graph. Every node has one
  // initializer address regardless of whether the target is itself, another
  // node, or part of a long cycle.
  for (unsigned index = 0; index != globals.size(); ++index)
    globals[index]->setInitializer(globals[(index * 17 + 1) % globals.size()]);
  for (GlobalVariable *global : globals)
    EXPECT_EQ(estimateNativeGlobalWeight(*global), localWeight);
}

TEST(NativePartitionCost, AliasReferenceDoesNotTraverseAliasee) {
  LLVMContext context;
  Module module("alias", context);
  auto *type = ArrayType::get(Type::getInt32Ty(context), 4096);
  auto *payload =
      new GlobalVariable(module, type, true, GlobalValue::InternalLinkage,
                         ConstantAggregateZero::get(type), "payload");
  auto *alias =
      GlobalAlias::create(GlobalValue::InternalLinkage, "alias", payload);
  auto *reference =
      new GlobalVariable(module, alias->getType(), true,
                         GlobalValue::InternalLinkage, alias, "reference");
  uint64_t weight = estimateNativeGlobalWeight(*reference);
  SmallVector<uint32_t> values(4096, 9);
  payload->setInitializer(ConstantDataArray::get(context, values));
  EXPECT_EQ(estimateNativeGlobalWeight(*reference), weight);
}

TEST(NativePartitionCost, InlineAggregateConstantsStillContribute) {
  LLVMContext context;
  Module module("inline", context);
  auto *array = ArrayType::get(Type::getInt32Ty(context), 1024);
  auto *type = StructType::get(context, {array, Type::getInt64Ty(context)});
  auto *global =
      new GlobalVariable(module, type, true, GlobalValue::InternalLinkage,
                         ConstantAggregateZero::get(type), "data");
  uint64_t zeroWeight = estimateNativeGlobalWeight(*global);
  SmallVector<uint32_t> values(1024, 3);
  global->setInitializer(ConstantStruct::get(
      type, {ConstantDataArray::get(context, values),
             ConstantInt::get(Type::getInt64Ty(context), 1)}));
  EXPECT_GT(estimateNativeGlobalWeight(*global), zeroWeight);
}

// A physical split unit keeps a function with the callees that exist only for
// it, transitively.
TEST(NativeSplitClusters, PrivateCalleesJoinTheirSoleCaller) {
  LLVMContext context;
  Module module("clusters", context);
  IRBuilder<> builder(context);
  auto *type = FunctionType::get(builder.getVoidTy(), false);
  StringMap<Function *> functions;
  for (StringRef name :
       {"execute", "body", "leaf", "shared", "other", "escaped", "entry",
        "entry_callee", "passed", "foreign", "big", "big_leaf", "ring_tail",
        "ring_b", "ring_a", "recursive"}) {
    auto *function =
        Function::Create(type, GlobalValue::ExternalLinkage, name, module);
    builder.SetInsertPoint(BasicBlock::Create(context, "entry", function));
    builder.CreateRetVoid();
    functions[name] = function;
  }
  // Declarations have no cluster, and a call to one changes nothing.
  auto *external =
      Function::Create(type, GlobalValue::ExternalLinkage, "external", module);
  auto *consume = Function::Create(
      FunctionType::get(builder.getVoidTy(), {builder.getPtrTy()}, false),
      GlobalValue::ExternalLinkage, "consume", module);
  auto call = [&](StringRef caller, StringRef callee) {
    builder.SetInsertPoint(functions[caller]->getEntryBlock().getTerminator());
    builder.CreateCall(functions[callee]);
  };
  call("execute", "body"); // execute -> body -> leaf: one cluster.
  call("body", "leaf");
  call("body", "shared"); // Two callers: its own unit.
  call("other", "shared");
  call("execute", "escaped"); // Also stored below: its own unit.
  new GlobalVariable(module, builder.getPtrTy(), true,
                     GlobalValue::InternalLinkage, functions["escaped"],
                     "table");
  call("execute", "entry");   // Exported: its own unit.
  call("execute", "foreign"); // Another owner: its own unit.
  call("execute", "big");     // An outlier is a cluster by itself.
  call("big", "big_leaf");
  call("ring_a", "ring_b"); // Sole callers of each other: one cluster.
  call("ring_b", "ring_a");
  call("body", "recursive"); // Its own recursion is no other caller.
  call("recursive", "recursive");
  call("entry", "entry_callee"); // An exported caller: its own unit.
  call("execute", "passed");     // Also passed as an argument: its own unit.
  builder.SetInsertPoint(functions["execute"]->getEntryBlock().getTerminator());
  builder.CreateCall(consume, {functions["passed"]});
  builder.CreateCall(external);
  // A tail called only from a cycle joins it, also when the walk starts at
  // the tail and enters the cycle at its larger name.
  call("ring_b", "ring_tail");

  StringSet<> exported;
  exported.insert("entry");
  auto roots = talos::driver::detail::nativeSplitClusterRoots(
      module,
      [](const GlobalValue *value) {
        return value->getName() == "foreign" ? StringRef("unit:2")
                                             : StringRef("unit:1");
      },
      exported,
      [](const Function &function) { return function.getName() == "big"; });
  auto rootOf = [&](StringRef name) {
    return roots.lookup(functions[name])->getName().str();
  };
  EXPECT_EQ(rootOf("execute"), "execute");
  EXPECT_EQ(rootOf("body"), "execute");
  EXPECT_EQ(rootOf("leaf"), "execute");
  EXPECT_EQ(rootOf("recursive"), "execute");
  EXPECT_EQ(rootOf("shared"), "shared");
  EXPECT_EQ(rootOf("other"), "other");
  EXPECT_EQ(rootOf("escaped"), "escaped");
  EXPECT_EQ(rootOf("entry"), "entry");
  EXPECT_EQ(rootOf("foreign"), "foreign");
  EXPECT_EQ(rootOf("big"), "big");
  EXPECT_EQ(rootOf("big_leaf"), "big_leaf");
  EXPECT_EQ(rootOf("ring_a"), "ring_a");
  EXPECT_EQ(rootOf("ring_b"), "ring_a");
  EXPECT_EQ(rootOf("ring_tail"), "ring_a");
  EXPECT_EQ(rootOf("entry_callee"), "entry_callee");
  EXPECT_EQ(rootOf("passed"), "passed");
  EXPECT_FALSE(roots.count(external));
  EXPECT_FALSE(roots.count(consume));
  EXPECT_EQ(roots.size(), functions.size());
}

// The role attributes are dropped from bitcode handed to the linker (they
// would change the ThinLTO module hash), and nothing else is.
TEST(FunctionRoles, DropFunctionRoleAttributesRemovesOnlyRoles) {
  LLVMContext context;
  Module module("roles", context);
  auto *type = FunctionType::get(Type::getVoidTy(context), false);
  auto *kernel =
      Function::Create(type, GlobalValue::ExternalLinkage, "kernel", module);
  kernel->addFnAttr(talos::kClockedKernelFnAttr);
  kernel->addFnAttr(talos::kEvalBodyFnAttr);
  kernel->addFnAttr(Attribute::NoInline);
  kernel->addFnAttr("keep", "yes");
  auto *plain =
      Function::Create(type, GlobalValue::ExternalLinkage, "plain", module);
  plain->addFnAttr(talos::kEvalBodyFnAttr);
  talos::dropFunctionRoleAttributes(module);
  for (Function *function : {kernel, plain}) {
    EXPECT_FALSE(function->hasFnAttribute(talos::kClockedKernelFnAttr));
    EXPECT_FALSE(function->hasFnAttribute(talos::kEvalBodyFnAttr));
  }
  EXPECT_TRUE(kernel->hasFnAttribute(Attribute::NoInline));
  EXPECT_EQ(kernel->getFnAttribute("keep").getValueAsString(), "yes");
}

} // namespace
