//===- NativeEvalRankAnalysis.h - Native eval ranking -*- C++ -*-===//
#ifndef TALOS_ANALYSIS_NATIVEEVALRANKANALYSIS_H
#define TALOS_ANALYSIS_NATIVEEVALRANKANALYSIS_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/Support/Error.h"
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace talos::runtime {
struct ActivationOrder;
}
namespace talos::analysis {
enum class NativeRankStrategy { Heuristic, Z3 };
bool hasZ3NativeRankAnalysis();

using NativeRankEdge = std::pair<uint32_t, uint32_t>;
struct NativeRankUnit {
  std::string executor;
  uint32_t island = 0;
  bool movable = false, repeatable = false, twoState = false,
       convergence = false;
  bool operator==(const NativeRankUnit &rhs) const;
};

/// Certificates from the actual baseline lowering, keyed by stable executor
/// names, independent of the permutation of physical ready bits.
struct NativeEvalLayout {
  std::map<std::string, std::string> helpers;
  std::set<std::vector<std::string>> chains;
  std::set<std::string> unconditional;
  bool runtimeCalendar = false;
  bool preserves(const NativeEvalLayout &required) const;
};
struct NativeRankGraph {
  uint32_t size = 0;
  /// The heuristic only needs topology. Z3 needs one capability record per
  /// node.
  std::vector<NativeRankUnit> units;
  std::vector<NativeRankEdge> edges; // canonical, unique
  bool operator==(const NativeRankGraph &rhs) const;
};
using NativeRankCost = std::pair<unsigned, unsigned>; // destinations, edges
struct NativeRankResult {
  NativeRankCost original, selected;
  bool proven = false;
};

/// Both strategies use the same SCC condensation, node identities and live
/// dependencies. A bounded solver can return a verified incumbent.
class NativeEvalRankAnalysis {
public:
  virtual ~NativeEvalRankAnalysis() = default;
  static const NativeEvalRankAnalysis &get(NativeRankStrategy strategy);
  llvm::Expected<NativeRankResult>
  analyze(const NativeRankGraph &graph, const NativeEvalLayout &layout,
          runtime::ActivationOrder &order) const;
  static bool applyOrder(runtime::ActivationOrder &order,
                         llvm::ArrayRef<NativeRankEdge> edges,
                         llvm::ArrayRef<uint32_t> selected);

private:
  virtual llvm::Expected<NativeRankResult>
  refine(const NativeRankGraph &graph, const NativeEvalLayout &layout,
         runtime::ActivationOrder &order) const = 0;
};

} // namespace talos::analysis
#endif
