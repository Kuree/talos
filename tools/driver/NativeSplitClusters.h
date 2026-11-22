//===- NativeSplitClusters.h - Native split clusters -----------*- C++ -*-===//

#ifndef TALOS_TOOLS_DRIVER_NATIVESPLITCLUSTERS_H
#define TALOS_TOOLS_DRIVER_NATIVESPLITCLUSTERS_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/IR/Module.h"

namespace talos::driver::detail {

/// The function that alone calls `callee`: every use of `callee` is the callee
/// operand of a direct call in that one other function. Null when the address
/// escapes (a stored pointer, a constant, a call argument) or several functions
/// call it. A recursive call of `callee` itself is no other caller.
inline const llvm::Function *soleNativeCaller(const llvm::Function &callee) {
  const llvm::Function *caller = nullptr;
  for (const llvm::Use &use : callee.uses()) {
    const auto *call = llvm::dyn_cast<llvm::CallBase>(use.getUser());
    if (!call || !call->isCallee(&use))
      return nullptr;
    const llvm::Function *user = call->getFunction();
    if (user == &callee)
      continue;
    if (caller && caller != user)
      return nullptr;
    caller = user;
  }
  return caller;
}

/// Each defined function's split cluster, by the cluster's root: the function
/// together with the callees that exist only for it, transitively. A function
/// joins its sole caller's cluster (soleNativeCaller) when neither is
/// `exported`, both have the same `owner`, and neither is an `outlier`, a body
/// compiled on its own: an outlier is a cluster by itself. A physical split
/// that keeps a cluster in one unit never separates a function from such a
/// callee, e.g. a wrapper from the body only it calls, so their inlining does
/// not depend on how units are packed. The root of a cycle of sole callers is
/// its member with the least name.
inline llvm::DenseMap<const llvm::Function *, const llvm::Function *>
nativeSplitClusterRoots(
    const llvm::Module &module,
    llvm::function_ref<llvm::StringRef(const llvm::GlobalValue *)> owner,
    const llvm::StringSet<> &exported,
    llvm::function_ref<bool(const llvm::Function &)> outlier) {
  llvm::DenseMap<const llvm::Function *, const llvm::Function *> parents;
  for (const llvm::Function &function : module) {
    if (function.isDeclaration() || exported.contains(function.getName()) ||
        outlier(function))
      continue;
    const llvm::Function *caller = soleNativeCaller(function);
    if (caller && !exported.contains(caller->getName()) &&
        owner(caller) == owner(&function) && !outlier(*caller))
      parents[&function] = caller;
  }
  llvm::DenseMap<const llvm::Function *, const llvm::Function *> roots;
  for (const llvm::Function &function : module) {
    if (function.isDeclaration() || roots.count(&function))
      continue;
    // Follow sole callers to a function with none, or around a cycle.
    llvm::SmallVector<const llvm::Function *> path;
    llvm::SmallPtrSet<const llvm::Function *, 8> onPath;
    const llvm::Function *current = &function;
    const llvm::Function *root = nullptr;
    while (true) {
      if (auto known = roots.find(current); known != roots.end()) {
        root = known->second;
        break;
      }
      if (!onPath.insert(current).second) {
        // A cycle: its members are the path from `current` on.
        auto begin = llvm::find(path, current);
        root = *begin;
        for (auto member = begin; member != path.end(); ++member)
          if ((*member)->getName() < root->getName())
            root = *member;
        break;
      }
      path.push_back(current);
      const llvm::Function *parent = parents.lookup(current);
      if (!parent) {
        root = current;
        break;
      }
      current = parent;
    }
    for (const llvm::Function *member : path)
      roots[member] = root;
  }
  return roots;
}

} // namespace talos::driver::detail

#endif
