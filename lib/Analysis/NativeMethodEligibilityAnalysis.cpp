//===- NativeMethodEligibilityAnalysis.cpp - Native method closures -------===//

#include "talos/Analysis/NativeMethodEligibilityAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"

using namespace mlir;

namespace talos::analysis {

NativeMethodEligibilityAnalysis::NativeMethodEligibilityAnalysis(
    sim::SimDesignOp design, bool includeTasks) {
  SmallVector<sim::SimClassMethodDeclOp> methods;
  for (auto method : design.getOps<sim::SimClassMethodDeclOp>())
    if (method.getImplementation() && (includeTasks || !method.getIsTask()))
      methods.push_back(method);
  if (methods.empty())
    return;

  SmallVector<sim::SimFuncOp> functions;
  llvm::StringMap<unsigned> indices;
  for (auto function : design.getOps<sim::SimFuncOp>()) {
    indices.try_emplace(function.getSymName(), functions.size());
    functions.push_back(function);
  }
  using Family = std::pair<uint64_t, unsigned>;
  DenseMap<Family, SmallVector<unsigned>> targets;
  DenseMap<Family, unsigned> familyNodes;
  SmallVector<SmallVector<unsigned>> callers(functions.size());
  DenseSet<unsigned> visited, unsupported;
  SmallVector<unsigned> pending, failures;
  auto reject = [&](unsigned node) {
    if (unsupported.insert(node).second)
      failures.push_back(node);
  };
  auto edge = [&](unsigned caller, unsigned callee) {
    callers[callee].push_back(caller);
    ++edgeCount;
  };
  auto familyNode = [&](Family family) {
    auto [entry, inserted] = familyNodes.try_emplace(family, callers.size());
    if (inserted)
      callers.emplace_back();
    return entry->second;
  };
  for (auto method : methods) {
    auto found = indices.find(*method.getImplementation());
    if (method.getIsVirtual()) {
      Family family{method.getSignatureId().value_or(0), method.getIsTask()};
      families.insert(family);
      if (found == indices.end())
        reject(familyNode(family));
      else
        targets[family].push_back(found->second);
    }
    if (found != indices.end())
      pending.push_back(found->second);
  }
  DenseSet<unsigned> expandedFamilies;
  auto virtualCall = [&](unsigned caller, uint64_t signature, bool isTask) {
    Family family{signature, isTask};
    unsigned node = familyNode(family);
    families.insert(family);
    edge(caller, node);
    // One shared family node avoids caller-count times override-count edges.
    // A bad override reaches every caller through the same reverse graph.
    if (!expandedFamilies.insert(node).second)
      return;
    auto found = targets.find(family);
    if (found == targets.end() || found->second.empty()) {
      reject(node);
      return;
    }
    for (unsigned target : found->second) {
      edge(node, target);
      pending.push_back(target);
    }
  };
  while (!pending.empty()) {
    unsigned index = pending.pop_back_val();
    if (!visited.insert(index).second)
      continue;
    auto function = functions[index];
    if (function.isExternal())
      reject(index);
    function.walk([&](Operation *operation) {
      if (operation == function)
        return;
      // Enabling a task is not itself proof that execution will suspend.
      // Follow its targets; a timing/control effect in any recursive closure
      // propagates back through these edges (IEEE 1800-2023 13.3/13.4).
      bool taskCall =
          isa<sim::SimTaskCallOp, sim::SimClassVirtualTaskCallOp>(operation);
      if (((!taskCall || function.getEntryKind() != sim::EntryKind::Task) &&
           sim::isSuspensionOp(operation)) ||
          isa<sim::SimControlNonlocalExitOp, sim::SimDPICallOp,
              sim::SimFinishOp, sim::SimStopOp, sim::SimFatalOp,
              sim::SimErrorOp, sim::SimProgramExitOp>(operation))
        reject(index);
      StringRef callee;
      if (auto call = dyn_cast<sim::SimCallOp>(operation))
        callee = call.getCallee();
      else if (auto call = dyn_cast<sim::SimClassDirectCallOp>(operation))
        callee = call.getCallee();
      else if (auto call = dyn_cast<sim::SimTaskCallOp>(operation))
        callee = call.getCallee();
      if (!callee.empty()) {
        auto found = indices.find(callee);
        if (found == indices.end())
          reject(index);
        else {
          edge(index, found->second);
          pending.push_back(found->second);
        }
      }
      if (auto call = dyn_cast<sim::SimClassVirtualCallOp>(operation))
        virtualCall(index, call.getSignatureId(), false);
      else if (auto call = dyn_cast<sim::SimClassVirtualTaskCallOp>(operation))
        virtualCall(index, call.getSignatureId(), true);
    });
  }
  while (!failures.empty()) {
    unsigned callee = failures.pop_back_val();
    for (unsigned caller : callers[callee])
      reject(caller);
  }
  functionCount = visited.size();
  for (unsigned index : visited)
    if (!unsupported.contains(index))
      eligible.try_emplace(functions[index].getSymName(), functions[index]);
  // Families not called by a method still describe bytecode call sites in
  // ordinary processes. Summarize their targets without a second body scan.
  for (Family family : families) {
    auto found = targets.find(family);
    bool bad = found == targets.end() || found->second.empty();
    if (!bad)
      for (unsigned target : found->second)
        bad |= unsupported.contains(target);
    auto node = familyNodes.find(family);
    bad |= node != familyNodes.end() && unsupported.contains(node->second);
    if (bad)
      ineligibleFamilies.insert(family);
  }
}

bool NativeMethodEligibilityAnalysis::canInvoke(sim::SimFuncOp function) const {
  if (!function)
    return false;
  auto found = eligible.find(function.getSymName());
  return found != eligible.end() && found->second == function.getOperation();
}

bool NativeMethodEligibilityAnalysis::canInvoke(
    StringRef implementation) const {
  return eligible.contains(implementation);
}

bool NativeMethodEligibilityAnalysis::canInvokeVirtual(uint64_t signature,
                                                       bool isTask) const {
  std::pair<uint64_t, unsigned> family{signature, isTask};
  return families.contains(family) && !ineligibleFamilies.contains(family);
}

} // namespace talos::analysis
