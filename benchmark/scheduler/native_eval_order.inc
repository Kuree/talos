// Record the executable graph before deriving activity domains. Recompute
// all backward-wake and forward-publication proofs from the selected order.
if (const char *contractPath = std::getenv("TALOS_EVAL_CONTRACT")) {
  std::string inventory;
  llvm::raw_string_ostream os(inventory);
  os << "H " << result.size() << " " << realNodeCount << "\n";
  for (unsigned pos = 0; pos < order.nodes.size(); ++pos) {
    const unsigned n = order.nodes[pos];
    const auto &node = result[n];
    bool real = n < realNodeCount;
    const auto *direct =
        real ? directByWrapper.lookup(plan.mergedExecutors[node.owner])
             : nullptr;
    os << "N " << n << " " << pos << " " << order.componentOf[n] << " "
       << node.island << " " << real << " " << node.boundary << " "
       << node.clocked << " " << node.repeatable << " "
       << !node.twoStateBody.empty() << " "
       << bool(direct && direct->runtimeCheckpoint) << " "
       << bool(direct && direct->deferred) << " "
       << bool(direct && direct->tier2Convergence) << " "
       << (direct ? direct->wrapper : "-") << " " << node.body << "\n";
  }
  auto canonical = edges;
  llvm::sort(canonical);
  canonical.erase(std::unique(canonical.begin(), canonical.end()),
                  canonical.end());
  for (auto [a, b] : canonical)
    os << "E " << a << " " << b << "\n";
  os.flush();
  auto digest = llvm::toHex(
      llvm::SHA256::hash(llvm::arrayRefFromStringRef(inventory)), true);
  std::ofstream model(contractPath);
  model << inventory;
  model.close();
  if (!model)
    llvm::report_fatal_error("cannot write native eval contract");
  llvm::errs() << "RF native contract " << digest << " nodes=" << result.size()
               << " edges=" << canonical.size() << "\n";
  if (const char *input = std::getenv("TALOS_EVAL_ORDER")) {
    std::ifstream planFile(input);
    std::string signature;
    planFile >> signature;
    if (signature != digest)
      llvm::report_fatal_error("native eval contract digest mismatch");
    std::vector<unsigned> selected;
    std::vector<bool> seen(result.size());
    unsigned id;
    while (planFile >> id) {
      if (id >= result.size() || seen[id])
        llvm::report_fatal_error("invalid native eval order");
      seen[id] = true;
      selected.push_back(id);
    }
    if (selected.size() != order.nodes.size())
      llvm::report_fatal_error("native eval order length mismatch");
    unsigned changed = 0;
    for (unsigned i = 0; i < selected.size(); ++i) {
      const unsigned a = order.nodes[i], b = selected[i];
      if (a == b)
        continue;
      if (order.componentOf[a] != order.componentOf[b] ||
          result[a].island != result[b].island || a >= realNodeCount ||
          b >= realNodeCount || result[a].boundary || result[b].boundary ||
          result[a].clocked || result[b].clocked)
        llvm::report_fatal_error("native eval order crossed a frozen boundary");
      ++changed;
    }
    // Check executor capability before accepting a permutation. The solver
    // additionally checks the post-lowering dataflow chain inventory.
    std::vector<unsigned> oldPos(result.size()), newPos(result.size());
    unsigned window = 0;
    std::vector<unsigned> windows(result.size());
    for (unsigned i = 0; i < selected.size(); ++i) {
      unsigned v = order.nodes[i];
      oldPos[v] = i;
      newPos[selected[i]] = i;
      if (i && order.componentOf[v] != order.componentOf[order.nodes[i - 1]])
        ++window;
      bool eligible =
          v < realNodeCount && !result[v].boundary && !result[v].clocked;
      if (eligible) {
        auto *direct =
            directByWrapper.lookup(plan.mergedExecutors[result[v].owner]);
        eligible = direct && !direct->runtimeCheckpoint && !direct->deferred;
      }
      if (!eligible) {
        ++window;
        if (v != selected[i])
          llvm::report_fatal_error(
              "moved a checkpoint or unavailable native executor");
      }
      windows[v] = window;
      if (!eligible)
        ++window;
    }
    for (unsigned i = 0; i < selected.size(); ++i) {
      unsigned a = order.nodes[i], b = selected[i];
      if (windows[a] != windows[b] ||
          result[a].repeatable != result[b].repeatable ||
          result[a].twoStateBody.empty() != result[b].twoStateBody.empty())
        llvm::report_fatal_error(
            "changed native predicate or checkpoint interval");
    }
    for (auto [a, b] : canonical)
      if (oldPos[a] < oldPos[b] && newPos[a] >= newPos[b] &&
          !result[b].repeatable)
        llvm::report_fatal_error("introduced an unsupported backward wake");
    order.nodes = std::move(selected);
    std::vector<unsigned> pos(result.size());
    for (unsigned i = 0; i < order.nodes.size(); ++i)
      pos[order.nodes[i]] = i;
    order.feedback.clear();
    for (auto [a, b] : canonical)
      if (pos[a] >= pos[b])
        order.feedback.emplace_back(a, b);
    llvm::errs() << "RF installed checked native order changed=" << changed
                 << " feedback=" << order.feedback.size() << "\n";
  }
}
