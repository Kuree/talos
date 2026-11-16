//===- SAIFInternal.h - Context-owned activity plans and event state ------===//
#ifndef TALOS_RUNTIME_SAIFINTERNAL_H
#define TALOS_RUNTIME_SAIFINTERNAL_H
#include "RuntimeInternal.h"

namespace talos::saifruntime {
struct Counts {
  uint64_t tc = 0, tg = 0, ig = 0;
  long double weightedIG = 0;
};
struct Observation {
  std::string signal;
  uint64_t last = 0;
  uint64_t time[4] = {};
  uint64_t toggles = 0;
  uint32_t current = 0;
  Counts extra;
  std::vector<std::pair<size_t, uint32_t>> cells;
};
struct Instance {
  std::string name, virtualType;
  bool isVirtual = false;
  std::map<std::string, std::unique_ptr<Instance>> children;
  std::vector<size_t> ports, nets, cells;
};
struct Watch {
  uint64_t bit;
  size_t observation;
};
struct ConditionToken {
  uint64_t opcode, pin;
};
struct Related {
  bool isDefault = false;
  std::vector<uint32_t> pins;
  Counts counts[2];
};
struct Rule {
  bool splitEdges = false;
  std::vector<ConditionToken> condition;
  std::vector<Related> paths;
  Counts counts[2];
  uint64_t timeTrue = 0;
};
struct Group {
  uint64_t observation = UINT64_MAX;
  bool leakage = false, conditional = false;
  std::vector<Rule> rules;
};
struct Pin {
  size_t observation;
  bool output;
};
struct Cell {
  Instance *instance = nullptr;
  std::vector<Pin> pins;
  std::vector<Group> groups;
  uint64_t last = 0;
};
struct CellEvent {
  size_t cell = 0;
  std::shared_ptr<const std::vector<uint8_t>> state;
  std::vector<uint32_t> related;
};
} // namespace talos::saifruntime

struct SAIFCause {
  std::shared_ptr<const std::vector<talos::saifruntime::CellEvent>> cells;
};
struct SAIFState {
  std::string output;
  uint64_t precision = 1, duration = 0;
  bool sealed = false, finished = false;
  talos::saifruntime::Instance root;
  std::vector<talos::saifruntime::Observation> observations;
  std::unordered_map<uint32_t, std::vector<talos::saifruntime::Watch>> watches;
  std::vector<talos::saifruntime::Cell> cells;
  std::unordered_map<uint64_t, std::shared_ptr<const SAIFCause>> wakeups;
  std::unordered_map<uint64_t, std::shared_ptr<const SAIFCause>> resumptions;
  std::shared_ptr<const SAIFCause> publicationCause;
  uint64_t activeLogical = 0;
};

namespace talos::saifruntime {
bool validToken(std::string_view token);
std::string decimal(unsigned __int128 value);
Instance *findInstance(SAIFState &state, const char *data, uint64_t size);
void flushCell(SAIFState &state, Cell &cell, uint64_t now);
std::shared_ptr<const SAIFCause>
preparePublication(talos_rt_context *context,
                   const std::vector<size_t> &changed);
void recordCellEdge(SAIFState &state, size_t observation, uint32_t from,
                    uint32_t to, unsigned metric,
                    const std::shared_ptr<const SAIFCause> &cause,
                    long double weight = 0,
                    const std::shared_ptr<const SAIFCause> &inputCause = {});
void writeGroups(FILE *file, const SAIFState &state, const Instance &instance,
                 uint64_t observation, uint64_t duration);
} // namespace talos::saifruntime
#endif
