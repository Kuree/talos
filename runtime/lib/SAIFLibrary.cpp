//===- SAIFLibrary.cpp - State/path characterization plans and counters
//----===//
#include "SAIFInternal.h"
#include <array>
using namespace talos::saifruntime;

namespace {
bool matches(const Rule &rule, const std::vector<uint8_t> &pins) {
  if (rule.condition.empty())
    return true;
  std::array<uint8_t, 4096> stack;
  size_t depth = 0;
  for (auto token : rule.condition) {
    if (!token.opcode) {
      stack[depth++] = std::min<uint8_t>(2, pins[token.pin]);
      continue;
    }
    uint8_t b = stack[--depth];
    if (token.opcode == 1) {
      stack[depth++] = b < 2 ? !b : 2;
      continue;
    }
    uint8_t a = stack[--depth];
    stack[depth++] = token.opcode == 2   ? (a == 0 || b == 0   ? 0
                                            : a == 1 && b == 1 ? 1
                                                               : 2)
                     : token.opcode == 3 ? (a < 2 && b < 2 ? a ^ b : 2)
                                         : (a == 1 || b == 1   ? 1
                                            : a == 0 && b == 0 ? 0
                                                               : 2);
  }
  return stack[0] == 1;
}
std::vector<uint8_t> pinState(const SAIFState &state, const Cell &cell) {
  std::vector<uint8_t> result;
  result.reserve(cell.pins.size());
  for (auto pin : cell.pins)
    result.push_back(state.observations[pin.observation].current);
  return result;
}
void count(Counts &counts, unsigned metric, long double weight) {
  if (metric == 0) {
    ++counts.tc;
  } else if (metric == 1)
    ++counts.tg;
  else {
    ++counts.ig;
    counts.weightedIG += weight;
  }
}
void printCondition(FILE *file, const Rule &rule, const SAIFState &state,
                    const Cell &cell) {
  struct Node {
    ConditionToken token;
    size_t left = 0, right = 0;
  };
  std::vector<Node> nodes;
  std::vector<size_t> roots;
  for (auto token : rule.condition) {
    Node node{token};
    if (token.opcode) {
      node.right = roots.back();
      roots.pop_back();
    }
    if (token.opcode > 1) {
      node.left = roots.back();
      roots.pop_back();
    }
    roots.push_back(nodes.size());
    nodes.push_back(node);
  }
  struct Action {
    size_t node;
    unsigned stage;
  };
  std::vector<Action> pending{{roots.back(), 0}};
  while (!pending.empty()) {
    auto action = pending.back();
    pending.pop_back();
    const auto &node = nodes[action.node];
    if (!node.token.opcode) {
      std::fputs(state.observations[cell.pins[node.token.pin].observation]
                     .signal.c_str(),
                 file);
    } else if (!action.stage) {
      std::fputc('(', file);
      pending.push_back({action.node, 2});
      pending.push_back({node.right, 0});
      if (node.token.opcode == 1)
        std::fputc('!', file);
      else {
        pending.push_back({action.node, 1});
        pending.push_back({node.left, 0});
      }
    } else if (action.stage == 1)
      std::fputc(node.token.opcode == 2   ? '*'
                 : node.token.opcode == 3 ? '^'
                                          : '|',
                 file);
    else
      std::fputc(')', file);
  }
}
void printMetric(FILE *file, const Counts &counts, unsigned metric) {
  if (metric < 3)
    std::fprintf(file, "(%s %s)",
                 metric == 0   ? "TC"
                 : metric == 1 ? "TG"
                               : "IG",
                 decimal(metric == 0   ? counts.tc
                         : metric == 1 ? counts.tg
                                       : counts.ig)
                     .c_str());
  else
    std::fprintf(file, "(IK %.17Lg)",
                 counts.ig ? counts.weightedIG / counts.ig : 0.0L);
}
} // namespace

extern "C" talos_rt_status
talos_rt_v1_saif_cell(talos_rt_context *context, const char *instance,
                      uint64_t instanceBytes, const char *cellType,
                      const uint64_t *words, uint64_t size) {
  if (!context || !cellType || !words || size < 3 || size > (1 << 22) ||
      std::string_view(cellType).find_first_of("\"\n\r") !=
          std::string_view::npos)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    auto *state = context->saif.get();
    if (!state || state->sealed || state->cells.size() >= (1 << 20))
      return TALOS_RT_INVALID_ARGUMENT;
    uint64_t cursor = 0;
    auto take = [&](uint64_t &out) {
      if (cursor == size)
        return false;
      out = words[cursor++];
      return true;
    };
    uint64_t version, pinCount, groupCount;
    if (!take(version) || version != 1 || !take(pinCount) ||
        !take(groupCount) || pinCount > (1 << 20) || groupCount > size)
      return TALOS_RT_INVALID_ARGUMENT;
    Cell cell;
    cell.instance = findInstance(*state, instance, instanceBytes);
    if (!cell.instance || !cell.instance->cells.empty())
      return TALOS_RT_INVALID_ARGUMENT;
    std::unordered_set<size_t> instancePins(cell.instance->ports.begin(),
                                            cell.instance->ports.end()),
        pins;
    for (uint64_t i = 0; i < pinCount; ++i) {
      uint64_t observation, output;
      if (!take(observation) || !take(output) || output > 1 ||
          !instancePins.count(observation) || !pins.insert(observation).second)
        return TALOS_RT_INVALID_ARGUMENT;
      cell.pins.push_back({size_t(observation), bool(output)});
    }
    for (uint64_t i = 0; i < groupCount; ++i) {
      Group group;
      uint64_t flags, ruleCount;
      if (!take(group.observation) || !take(flags) || flags > 3 ||
          !take(ruleCount) || !ruleCount || ruleCount > size)
        return TALOS_RT_INVALID_ARGUMENT;
      group.leakage = flags & 1;
      group.conditional = flags & 2;
      if (group.leakage && !group.conditional)
        return TALOS_RT_INVALID_ARGUMENT;
      if (group.leakage ? group.observation != UINT64_MAX
                        : !pins.count(group.observation))
        return TALOS_RT_INVALID_ARGUMENT;
      if (!group.conditional && ruleCount != 1)
        return TALOS_RT_INVALID_ARGUMENT;
      bool seenDefault = false;
      bool hasCondition = false;
      for (uint64_t j = 0; j < ruleCount; ++j) {
        Rule rule;
        uint64_t split, tokenCount, pathCount;
        if (!take(split) || split > 1 || !take(tokenCount) ||
            tokenCount > 4096 || !take(pathCount) || pathCount > size ||
            seenDefault)
          return TALOS_RT_INVALID_ARGUMENT;
        rule.splitEdges = split;
        if (split && !group.conditional)
          return TALOS_RT_INVALID_ARGUMENT;
        hasCondition |= tokenCount != 0;
        if (group.leakage && (split || pathCount))
          return TALOS_RT_INVALID_ARGUMENT;
        if (pathCount &&
            std::none_of(
                cell.pins.begin(), cell.pins.end(), [&](const Pin &pin) {
                  return pin.observation == group.observation && pin.output;
                }))
          return TALOS_RT_INVALID_ARGUMENT;
        if (!group.conditional && tokenCount)
          return TALOS_RT_INVALID_ARGUMENT;
        seenDefault = group.conditional && !tokenCount;
        uint64_t stack = 0;
        for (uint64_t k = 0; k < tokenCount; ++k) {
          ConditionToken token;
          if (!take(token.opcode) || !take(token.pin) || token.opcode > 4)
            return TALOS_RT_INVALID_ARGUMENT;
          if (!token.opcode) {
            if (token.pin >= pinCount)
              return TALOS_RT_INVALID_ARGUMENT;
            ++stack;
          } else if (token.opcode == 1) {
            if (!stack)
              return TALOS_RT_INVALID_ARGUMENT;
          } else {
            if (stack < 2)
              return TALOS_RT_INVALID_ARGUMENT;
            --stack;
          }
          rule.condition.push_back(token);
        }
        if (tokenCount && stack != 1)
          return TALOS_RT_INVALID_ARGUMENT;
        std::unordered_set<uint32_t> relatedPins;
        bool pathDefault = false;
        bool hasRelated = false;
        for (uint64_t k = 0; k < pathCount; ++k) {
          Related related;
          uint64_t isDefault, count;
          if (!take(isDefault) || isDefault > 1 || !take(count) ||
              count > pinCount || pathDefault || bool(isDefault) != !count)
            return TALOS_RT_INVALID_ARGUMENT;
          related.isDefault = isDefault;
          pathDefault = isDefault;
          hasRelated |= !isDefault;
          for (uint64_t n = 0; n < count; ++n) {
            uint64_t pin;
            if (!take(pin) || pin >= pinCount || cell.pins[pin].output ||
                !relatedPins.insert(pin).second)
              return TALOS_RT_INVALID_ARGUMENT;
            related.pins.push_back(pin);
          }
          rule.paths.push_back(std::move(related));
        }
        if (pathCount && !hasRelated)
          return TALOS_RT_INVALID_ARGUMENT;
        group.rules.push_back(std::move(rule));
      }
      if (group.conditional && !hasCondition)
        return TALOS_RT_INVALID_ARGUMENT;
      cell.groups.push_back(std::move(group));
    }
    if (cursor != size)
      return TALOS_RT_INVALID_ARGUMENT;
    size_t id = state->cells.size();
    for (size_t pin = 0; pin < cell.pins.size(); ++pin)
      state->observations[cell.pins[pin].observation].cells.push_back(
          {id, uint32_t(pin)});
    cell.instance->cells.push_back(id);
    if (!cell.instance->isVirtual)
      cell.instance->virtualType = cellType;
    state->cells.push_back(std::move(cell));
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
}

namespace talos::saifruntime {
void flushCell(SAIFState &state, Cell &cell, uint64_t now) {
  if (now == cell.last)
    return;
  auto pins = pinState(state, cell);
  for (auto &group : cell.groups)
    if (group.leakage)
      for (auto &rule : group.rules)
        if (matches(rule, pins)) {
          rule.timeTrue += now - cell.last;
          break;
        }
  cell.last = now;
}
std::shared_ptr<const SAIFCause>
preparePublication(talos_rt_context *context,
                   const std::vector<size_t> &changed) {
  auto &state = *context->saif;
  auto result = std::make_shared<SAIFCause>();
  if (auto cause = talos_rt_saif_current_cause_unlocked(context))
    *result = *cause;
  auto snapshots = std::make_shared<std::vector<CellEvent>>();
  std::unordered_map<size_t, std::vector<uint32_t>> cells;
  for (size_t observation : changed)
    for (auto reference : state.observations[observation].cells) {
      auto &inputs = cells[reference.first];
      if (!state.cells[reference.first].pins[reference.second].output)
        inputs.push_back(reference.second);
    }
  for (auto &entry : cells) {
    auto &cell = state.cells[entry.first];
    flushCell(state, cell, context->schedulerTime);
    snapshots->push_back(
        {entry.first,
         std::make_shared<const std::vector<uint8_t>>(pinState(state, cell)),
         std::move(entry.second)});
  }
  result->cells = std::move(snapshots);
  state.publicationCause = result;
  return result;
}
void recordCellEdge(SAIFState &state, size_t observation, uint32_t from,
                    uint32_t to, unsigned metric,
                    const std::shared_ptr<const SAIFCause> &cause,
                    long double weight,
                    const std::shared_ptr<const SAIFCause> &inputCause) {
  if (from >= 2 || to >= 2 || from == to)
    return;
  for (auto [cellId, pin] : state.observations[observation].cells) {
    auto &cell = state.cells[cellId];
    const CellEvent *event = nullptr;
    const auto &selectedCause =
        !cell.pins[pin].output && inputCause ? inputCause : cause;
    if (selectedCause && selectedCause->cells)
      for (const auto &candidate : *selectedCause->cells)
        if (candidate.cell == cellId) {
          event = &candidate;
          break;
        }
    auto current = event ? std::vector<uint8_t>{} : pinState(state, cell);
    const auto &pins = event ? *event->state : current;
    for (auto &group : cell.groups) {
      if (group.leakage || group.observation != observation)
        continue;
      for (auto &rule : group.rules) {
        if (!matches(rule, pins))
          continue;
        unsigned edge = rule.splitEdges && !to ? 1 : 0;
        if (rule.paths.empty()) {
          count(rule.counts[edge], metric, weight);
        } else
          for (auto &related : rule.paths) {
            bool matchesPath = related.isDefault;
            if (event)
              for (auto input : event->related)
                matchesPath |=
                    std::find(related.pins.begin(), related.pins.end(),
                              input) != related.pins.end();
            if (matchesPath) {
              count(related.counts[edge], metric, weight);
              break;
            }
          }
        break;
      }
    }
  }
}
void writeGroups(FILE *file, const SAIFState &state, const Instance &instance,
                 uint64_t observation, uint64_t duration) {
  bool leakage = observation == UINT64_MAX;
  bool opened = false;
  for (size_t id : instance.cells) {
    const auto &cell = state.cells[id];
    for (const auto &group : cell.groups) {
      if (group.observation != observation)
        continue;
      if (leakage && !opened) {
        std::fputs("(LEAKAGE ", file);
        opened = true;
      }
      for (unsigned metric = 0; metric < (leakage ? 1u : 4u); ++metric) {
        if (metric) {
          bool present = false;
          for (const auto &rule : group.rules) {
            for (unsigned edge = 0; edge < 2; ++edge)
              present |= metric == 1 ? rule.counts[edge].tg != 0
                                     : rule.counts[edge].ig != 0;
            for (const auto &path : rule.paths)
              for (unsigned edge = 0; edge < 2; ++edge)
                present |= metric == 1 ? path.counts[edge].tg != 0
                                       : path.counts[edge].ig != 0;
          }
          if (!present)
            continue;
        }
        if (group.conditional)
          std::fputc('(', file);
        for (const auto &rule : group.rules)
          for (unsigned edge = 0; edge < (rule.splitEdges ? 2u : 1u); ++edge) {
            if (group.conditional) {
              std::fputs(rule.condition.empty() ? "COND_DEFAULT " : "COND ",
                         file);
              if (!rule.condition.empty()) {
                printCondition(file, rule, state, cell);
                std::fputc(' ', file);
              }
              if (rule.splitEdges)
                std::fputs(edge ? "(FALL) " : "(RISE) ", file);
            }
            if (leakage) {
              std::fprintf(
                  file, "(T1 %s) (T0 %s) ",
                  decimal(static_cast<unsigned __int128>(rule.timeTrue) *
                          state.precision)
                      .c_str(),
                  decimal(
                      static_cast<unsigned __int128>(duration - rule.timeTrue) *
                      state.precision)
                      .c_str());
            } else if (rule.paths.empty()) {
              printMetric(file, rule.counts[edge], metric);
              std::fputc(' ', file);
            } else {
              std::fputc('(', file);
              for (const auto &related : rule.paths) {
                std::fputs(related.isDefault ? "IOPATH_DEFAULT " : "IOPATH ",
                           file);
                for (auto pin : related.pins)
                  std::fprintf(file, "%s ",
                               state.observations[cell.pins[pin].observation]
                                   .signal.c_str());
                printMetric(file, related.counts[edge], metric);
                std::fputc(' ', file);
              }
              std::fputs(") ", file);
            }
          }
        if (group.conditional)
          std::fputs(") ", file);
      }
    }
  }
  if (opened)
    std::fputs(")\n", file);
}
} // namespace talos::saifruntime
