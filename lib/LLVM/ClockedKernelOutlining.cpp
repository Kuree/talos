//===- ClockedKernelOutlining.cpp - Bound native clocked update bodies ----===//

#include "talos/LLVM/ClockedKernelOutlining.h"
#include "talos/Dialect/Schedule/ClockedKernelName.h"

#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Module.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Transforms/Utils/CodeExtractor.h"
#include "llvm/Transforms/Utils/Local.h"

#include <algorithm>

using namespace llvm;

namespace talos {
namespace {

struct UpdateGroup {
  SmallVector<BasicBlock *> blocks;
  SmallVector<Instruction *> addresses;
  unsigned size = 0;
};

// CodeExtractor preserves instruction metadata, but an assumption in the
// caller does not describe the helper's arguments. Carry over only assumptions
// whose two original operands are passed directly to the helper.
static void preserveStorageAssumptions(Function &helper) {
  auto *call = dyn_cast<CallBase>(*helper.user_begin());
  if (!call)
    return;
  for (Instruction &instruction : call->getFunction()->getEntryBlock()) {
    auto *assume = dyn_cast<AssumeInst>(&instruction);
    if (!assume)
      continue;
    auto storage = assume->getOperandBundle("separate_storage");
    if (!storage || storage->Inputs.size() != 2)
      continue;
    SmallVector<Value *, 2> arguments;
    for (Value *input : storage->Inputs)
      for (unsigned index = 0; index != call->arg_size(); ++index)
        if (call->getArgOperand(index) == input) {
          arguments.push_back(helper.getArg(index));
          break;
        }
    if (arguments.size() != 2)
      continue;
    IRBuilder<> builder(&*helper.getEntryBlock().getFirstInsertionPt());
    SmallVector<OperandBundleDef, 1> bundles;
    bundles.emplace_back("separate_storage", arguments);
    builder.CreateAssumption(builder.getTrue(), bundles);
  }
}

// Simplify the new entry and the newly exposed argument relationships without
// repeating the module pipeline over the large caller. Use separate analysis
// managers: extraction has invalidated the caller's cached analyses.
static void simplifyHelpers(ArrayRef<Function *> helpers) {
  if (helpers.empty())
    return;
  PassBuilder builder;
  LoopAnalysisManager loops;
  FunctionAnalysisManager functions;
  CGSCCAnalysisManager cgscc;
  ModuleAnalysisManager modules;
  builder.registerModuleAnalyses(modules);
  builder.registerCGSCCAnalyses(cgscc);
  builder.registerFunctionAnalyses(functions);
  builder.registerLoopAnalyses(loops);
  builder.crossRegisterProxies(loops, functions, cgscc, modules);
  auto passes = builder.buildFunctionSimplificationPipeline(
      OptimizationLevel::O3, ThinOrFullLTOPhase::None);
  for (Function *helper : helpers)
    passes.run(*helper, functions);
}

// CodeExtractor communicates SSA outputs through stack slots. A computed return
// value also creates such an output, even when its ReturnInst is in the region.
// Only constant address expressions may be replicated: in particular a state
// load is never resampled across updates.
static bool hasSmallInterface(UpdateGroup &group) {
  for (BasicBlock *block : group.blocks)
    if (auto *ret = dyn_cast<ReturnInst>(block->getTerminator());
        ret && ret->getReturnValue() && !isa<Constant>(ret->getReturnValue()))
      return false;
  CodeExtractor extractor(group.blocks);
  if (!extractor.isEligible())
    return false;
  SetVector<Value *> inputs, outputs, allocas;
  extractor.findInputsOutputs(inputs, outputs, allocas);
  if (!outputs.empty())
    return false;

  SmallPtrSet<Value *, 32> roots, addresses;
  SmallVector<Value *> work(inputs.begin(), inputs.end());
  while (!work.empty()) {
    Value *value = work.pop_back_val();
    if (auto *gep = dyn_cast<GetElementPtrInst>(value);
        gep && gep->hasAllConstantIndices()) {
      if (addresses.insert(gep).second) {
        group.addresses.push_back(gep);
        work.push_back(gep->getPointerOperand());
      }
    } else if (!isa<Constant>(value)) {
      roots.insert(value);
    }
  }
  if (roots.size() > 6)
    return false;
  for (Value *root : roots) {
    Type *type = root->getType();
    if (!type->isPointerTy() &&
        !(type->isIntegerTy() && type->getIntegerBitWidth() <= 64))
      return false;
  }
  // A PHI's incoming value must remain available on its predecessor edge.
  for (PHINode &phi : group.blocks.front()->phis())
    for (Value *value : phi.incoming_values())
      if (addresses.contains(value))
        return false;
  return true;
}

static bool outlineUpdates(Function &function, unsigned targetSize,
                           SmallVectorImpl<Function *> &helpers) {
  DominatorTree dominators(function);
  DenseMap<DomTreeNode *, unsigned> sizes;
  for (DomTreeNode *node : post_order(dominators.getRootNode())) {
    sizes[node] += node->getBlock()->size();
    if (DomTreeNode *parent = node->getIDom())
      sizes[parent] += sizes[node];
  }

  // Follow the largest child of each dominator. The other subtrees, together
  // with this node, form the next ordered update group. Unlike a postdominator
  // spine this still finds boundaries when every update can return an error.
  // Groups have one entry; CodeExtractor preserves all their exit edges.
  SmallVector<UpdateGroup> groups;
  UpdateGroup group;
  unsigned nextCheck = targetSize;
  for (DomTreeNode *node = dominators.getRootNode(); node;) {
    DomTreeNode *continuation = nullptr;
    for (DomTreeNode *child : *node)
      if (!continuation || sizes[child] > sizes[continuation])
        continuation = child;
    // The entry owns the state bases and activation-local storage. Leave it
    // and its other subtrees in the caller.
    if (node != dominators.getRootNode()) {
      group.blocks.push_back(node->getBlock());
      group.size += node->getBlock()->size();
      for (DomTreeNode *child : *node) {
        if (child == continuation)
          continue;
        for (DomTreeNode *member : depth_first(child)) {
          group.blocks.push_back(member->getBlock());
          group.size += member->getBlock()->size();
        }
      }
      if (group.size >= nextCheck) {
        group.addresses.clear();
        if (group.size <= 4 * targetSize && hasSmallInterface(group)) {
          groups.push_back(std::move(group));
          group = UpdateGroup{};
          nextCheck = targetSize;
        } else if (group.size >= 4 * targetSize) {
          group = UpdateGroup{};
          nextCheck = targetSize;
        } else {
          // Bound repeated interface scans even for a long chain of tiny
          // blocks that cannot yet be cut without spilling an SSA result.
          nextCheck = group.size + std::max(1u, targetSize / 4);
        }
      }
    }
    node = continuation;
  }
  if (groups.empty())
    return false;

  SmallVector<WeakTrackingVH> deadAddresses;
  for (UpdateGroup &selected : groups) {
    SmallPtrSet<BasicBlock *, 32> members(selected.blocks.begin(),
                                          selected.blocks.end());
    DenseMap<Value *, Value *> copies;
    auto insertion = selected.blocks.front()->getFirstInsertionPt();
    auto copyAddress = [&](auto &&self, Instruction *address) -> Value * {
      if (Value *copy = copies.lookup(address))
        return copy;
      Instruction *copy = address->clone();
      for (Use &operand : copy->operands())
        if (auto *gep = dyn_cast<GetElementPtrInst>(operand.get());
            gep && gep->hasAllConstantIndices() &&
            !members.contains(gep->getParent()))
          operand.set(self(self, gep));
      copy->insertBefore(insertion);
      copies[address] = copy;
      deadAddresses.push_back(address);
      return copy;
    };
    for (Instruction *address : selected.addresses) {
      Value *copy = copyAddress(copyAddress, address);
      address->replaceUsesWithIf(copy, [&](Use &use) {
        auto *user = dyn_cast<Instruction>(use.getUser());
        return user && members.contains(user->getParent());
      });
    }
  }

  // All address rematerialization precedes this cache. Reuse it across
  // extractions; constructing it afresh per helper would scan the whole kernel.
  CodeExtractorAnalysisCache cache(function);
  for (UpdateGroup &selected : groups) {
    CodeExtractor extractor(selected.blocks, nullptr, false, nullptr, nullptr,
                            nullptr, false, false, nullptr,
                            "__talos_update_group");
    Function *helper = extractor.extractCodeRegion(cache);
    if (!helper)
      continue;
    helper->removeFnAttr(Attribute::AlwaysInline);
    helper->addFnAttr(Attribute::NoInline);
    helper->addFnAttr(kClockedUpdateGroupAttr);
    helper->setCallingConv(CallingConv::Fast);
    for (User *user : helper->users())
      if (auto *call = dyn_cast<CallBase>(user))
        call->setCallingConv(CallingConv::Fast);
    preserveStorageAssumptions(*helper);
    helpers.push_back(helper);
  }
  RecursivelyDeleteTriviallyDeadInstructionsPermissive(deadAddresses);
  // Address rematerialization itself changes IR even if extraction declines.
  return true;
}

} // namespace

PreservedAnalyses ClockedKernelOutliningPass::run(Module &module,
                                                  ModuleAnalysisManager &) {
  SmallVector<Function *> kernels;
  for (Function &function : module)
    if (!function.isDeclaration() &&
        function.getName().contains(schedule::clockedKernelPrefix) &&
        function.getName().contains(".__talos_eval_body_") &&
        !function.getName().contains(".__talos_update_group") &&
        !function.hasFnAttribute(Attribute::OptimizeNone) &&
        !function.hasFnAttribute("nooutline") &&
        function.getInstructionCount() >= 4 * targetSize)
      kernels.push_back(&function);
  bool changed = false;
  SmallVector<Function *> helpers;
  for (Function *kernel : kernels)
    changed |= outlineUpdates(*kernel, targetSize, helpers);
  simplifyHelpers(helpers);
  return changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
}

} // namespace talos
