//===- VCD.cpp - Value change dump over the canonical state planes -------===//
//
// Waveform collection is a once-per-time-slot difference over the canonical
// four-state planes, not a per-transition callback. No writer has to be
// instrumented, because the difference observes only the settled result of the
// slot -- which is also exactly VCD's required semantics. The traced set, its
// names, and its canonical bit ranges come from the design database.
//
//===----------------------------------------------------------------------===//

#include "DesignBytecodeNets.h"
#include "ProcessContext.h"
#include "RuntimeInternal.h"
#include "VCDCompact.h"
#include "VCDFormat.h"
#include "talos/Reflection/DesignReflection.h"

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__EMSCRIPTEN__)
#define TALOS_POSIX_COMPACT_VCD 1
#if defined(__linux__) || defined(__APPLE__)
#include <sys/xattr.h>
#endif
#ifdef __linux__
#include <linux/fs.h>
#include <sys/ioctl.h>
#endif
#ifdef __APPLE__
#include <copyfile.h>
#endif
#include <sys/stat.h>
#include <unistd.h>
#endif

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <functional>
#include <initializer_list>
#include <limits>
#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

constexpr uint64_t kScopeRecordSize = 64;
constexpr uint64_t kObjectRecordSize = 96;
constexpr uint64_t kTypeRecordSize = 80;

// Output is accumulated here and handed to libc in large pieces. VCD records
// are tiny and extremely numerous, so per-record stdio calls dominate the cost
// of the difference itself.
constexpr size_t kFlushThreshold = 1u << 16;

// Depth guard against a malformed type graph.
constexpr unsigned kMaxUnpackedDepth = 8;

// Default bound on unpacked-array expansion, matching the value Verilator
// settled on for the same trade-off: the cost of an expanded array is paid per
// element per time slot, in both file size and scan time. An array larger than
// this is omitted rather than degraded into some other shape -- VCD has no
// aggregate form, so the only alternatives are honest elements or a vector
// that misrepresents several signals as one.
constexpr uint64_t kDefaultMaxExpandedElements = 32;

// Byte gap below which two traced ranges are merged. Merging trades a few
// untraced bytes inside a memcmp for one fewer range in the scan loop.
constexpr uint64_t kRangeMergeGap = 32;
// Bound the number of individual tests a single changing bit usually triggers.
// Variables sharing a byte must stay together until all comparisons finish.
constexpr uint32_t kVariablesPerRange = 32;

uint32_t read32(const uint8_t *data) {
  uint32_t value = 0;
  for (unsigned byte = 0; byte != 4; ++byte)
    value |= uint32_t{data[byte]} << (byte * 8);
  return value;
}

uint64_t read64(const uint8_t *data) {
  uint64_t value = 0;
  for (unsigned byte = 0; byte != 8; ++byte)
    value |= uint64_t{data[byte]} << (byte * 8);
  return value;
}

int64_t readI64(const uint8_t *data) {
  return static_cast<int64_t>(read64(data));
}

// The database was validated before registration, so these only re-establish
// that a cursor points at a record of the expected kind.
bool isScopeOffset(const DesignDatabaseCache &database, uint64_t offset) {
  return offset >= database.scopes &&
         offset - database.scopes < database.scopeCount * kScopeRecordSize &&
         (offset - database.scopes) % kScopeRecordSize == 0;
}

bool isObjectOffset(const DesignDatabaseCache &database, uint64_t offset) {
  return offset >= database.objects &&
         offset - database.objects < database.objectCount * kObjectRecordSize &&
         (offset - database.objects) % kObjectRecordSize == 0;
}

bool isTypeOffset(const DesignDatabaseCache &database, uint64_t offset) {
  return offset >= database.types &&
         offset - database.types < database.typeCount * kTypeRecordSize &&
         (offset - database.types) % kTypeRecordSize == 0;
}

bool getRecord(const DesignDatabaseCache &database, uint64_t offset,
               const uint8_t *&record, uint32_t &kind) {
  if (isScopeOffset(database, offset) || isObjectOffset(database, offset))
    record = database.data + offset;
  else
    return false;
  kind = static_cast<uint32_t>(
      talos::reflection::unpackRecordKind(read32(record)));
  return true;
}

// String offsets stored in records are absolute image offsets, matching the
// reflection reader in DesignDatabase.cpp.
bool getString(const DesignDatabaseCache &database, uint64_t offset,
               std::string_view &text) {
  if (offset < database.strings ||
      offset - database.strings >= database.stringSize)
    return false;
  const char *begin = reinterpret_cast<const char *>(database.data + offset);
  uint64_t available = database.stringSize - (offset - database.strings);
  const void *end = std::memchr(begin, 0, static_cast<size_t>(available));
  if (!end)
    return false;
  text = std::string_view(
      begin, static_cast<size_t>(static_cast<const char *>(end) - begin));
  return true;
}

uint64_t firstChildOffset(const uint8_t *record) { return read64(record + 24); }

uint64_t nextSiblingOffset(const uint8_t *record, uint32_t kind) {
  return read64(record + (kind == TALOS_RT_DESIGN_RECORD_SCOPE ? 32 : 24));
}

uint64_t parentOffset(const uint8_t *record) { return read64(record + 16); }

uint64_t nameOffset(const uint8_t *record) { return read64(record + 40); }

// Records store the full hierarchical path; VCD declares the leaf name inside
// its enclosing `$scope`. Splitting on the last dot is wrong -- an escaped
// identifier may contain one -- so the leaf is taken as the suffix past the
// enclosing scope's own full name.
std::string_view leafName(std::string_view path, std::string_view parent) {
  if (!parent.empty() && path.size() > parent.size() + 1 &&
      path.compare(0, parent.size(), parent) == 0 && path[parent.size()] == '.')
    return path.substr(parent.size() + 1);
  size_t dot = path.rfind('.');
  return dot == std::string_view::npos ? path : path.substr(dot + 1);
}

// Storage and net records carry the canonical four-state location that VPI
// reads and language writes both address.
uint64_t objectTypeOffset(const uint8_t *record) { return read64(record + 48); }
uint64_t objectBitWidth(const uint8_t *record) { return read64(record + 56); }
uint64_t objectStateBit(const uint8_t *record) { return read64(record + 80); }

bool traceableObject(const DesignDatabaseCache &database, uint32_t kind,
                     const uint8_t *record);

bool bitAt(const uint8_t *plane, uint64_t bit) {
  return plane && (plane[bit / 8] & static_cast<uint8_t>(1u << (bit % 8))) != 0;
}

// Compare one bit range across two planes that use identical bit offsets. The
// shadow mirrors the live plane rather than holding an extracted copy, so no
// shifting is needed on the hot path and only the partial end bytes need
// masking.
bool bitRangeEqual(const uint8_t *left, const uint8_t *right, uint64_t bit,
                   uint64_t width) {
  uint64_t firstByte = bit / 8;
  uint64_t lastBit = bit + width - 1;
  uint64_t lastByte = lastBit / 8;
  unsigned lowShift = static_cast<unsigned>(bit % 8);
  unsigned highBit = static_cast<unsigned>(lastBit % 8);
  if (firstByte == lastByte) {
    uint8_t mask = static_cast<uint8_t>(
        ((highBit == 7 ? 0xffu : (1u << (highBit + 1)) - 1u)) &
        ~((1u << lowShift) - 1u));
    return ((left[firstByte] ^ right[firstByte]) & mask) == 0;
  }
  uint8_t firstMask = static_cast<uint8_t>(~((1u << lowShift) - 1u));
  if (((left[firstByte] ^ right[firstByte]) & firstMask) != 0)
    return false;
  uint8_t lastMask =
      static_cast<uint8_t>(highBit == 7 ? 0xffu : (1u << (highBit + 1)) - 1u);
  if (((left[lastByte] ^ right[lastByte]) & lastMask) != 0)
    return false;
  uint64_t middle = lastByte - firstByte - 1;
  return middle == 0 || std::memcmp(left + firstByte + 1, right + firstByte + 1,
                                    static_cast<size_t>(middle)) == 0;
}

char fourStateChar(bool value, bool unknown) {
  if (!unknown)
    return value ? '1' : '0';
  return value ? 'z' : 'x';
}

// VCD identifier codes are dense base-94 strings over the printable range.
std::string identifierCode(uint64_t index) {
  std::string code;
  do {
    code.push_back(static_cast<char>('!' + index % 94));
    index /= 94;
  } while (index != 0);
  return code;
}

// Resolve the byte-addressed canonical four-state planes.
//
// This deliberately matches the VPI backdoor rather than the Preponed
// snapshot. A generated schedule plan owns its state planes directly, so they
// are authoritative when one exists; otherwise the context's canonical store
// is, in every execution tier. `nativeStateValue` is only a lazily synced
// mirror -- reading it makes bytecode designs dump a waveform frozen at X.
talos_rt_status dumpPlanes(const talos_rt_context *context,
                           const uint8_t *&value, const uint8_t *&unknown) {
  const talos_rt_execution_descriptor_v1 &execution = *context->execution;
  const talos_rt_native_schedule_plan *plan = context->nativeSchedulePlan;
  if (plan && plan->state_bit_count == execution.state_bit_count &&
      plan->state_value && (plan->state_unknown || context->twoState())) {
    value = plan->state_value;
    unknown = context->twoState() ? nullptr : plan->state_unknown;
    return TALOS_RT_OK;
  }
  size_t stateWords =
      static_cast<size_t>((execution.state_bit_count + 63) / 64);
  if (context->stateValue.size() != stateWords ||
      (!context->twoState() && context->stateUnknown.size() != stateWords))
    return TALOS_RT_INVALID_DESIGN;
  value = reinterpret_cast<const uint8_t *>(context->stateValue.data());
  unknown =
      context->twoState()
          ? nullptr
          : reinterpret_cast<const uint8_t *>(context->stateUnknown.data());
  return TALOS_RT_OK;
}

// One traced canonical bit range. Several declared names may map onto it; the
// range is differenced and emitted once.
struct TraceVariable {
  uint64_t sourceBit = 0;
  uint64_t width = 0;
  // Index into VCDTraceState::codeText. Assigned in declaration order and
  // stable across the later sort into canonical-offset order.
  uint32_t code = 0;
  bool fourState = false;
  // Emitted as a VCD `r` record rather than a bit vector.
  bool isReal = false;
  // Zero for ordinary VCD. EVCD stores the port-direction capability bits.
  uint32_t portCaps = 0;
  // EVCD only: per bit, the drivers on both sides of the dumped instance
  // boundary (IEEE 1800-2023 21.7.4.3.2). Empty unless both sides drive.
  struct BoundaryDriver {
    uint64_t valueOffset;
    uint8_t strength0;
    uint8_t strength1;
    bool inside;
  };
  std::vector<std::vector<BoundaryDriver>> boundaryDrivers;
};

// One byte-aligned window of the canonical planes that covers a contiguous
// run of traced variables. The scan tests the window with memcmp and only
// descends to individual variables when the window moved.
struct TraceRange {
  uint64_t byteBegin = 0;
  uint64_t byteEnd = 0;
  uint32_t firstVariable = 0;
  uint32_t lastVariable = 0;
};

// Consecutive VCD declarations whose selected bits fit in one load from
// each plane. The fallback entry covers a single wider or unaligned view.
struct TraceWord {
  uint64_t byte;
  uint32_t end;
  bool fourState;
};

struct TraceSelection {
  std::string scope;
  uint64_t levels = 0;
};

// Preserve the live byte offsets for comparison, while only faulting pages
// that contain selected variables. An omitted unpacked memory can otherwise
// fill most of both shadows without contributing a single VCD record.
class TraceShadow {
public:
  void reset(size_t bytes) {
    CanonicalPlane fresh;
    fresh.assign(bytes / 8 + (bytes % 8 != 0), 0);
    storage.swap(fresh);
    byteCount = bytes;
  }
  size_t size() const { return byteCount; }
  uint8_t *data() { return reinterpret_cast<uint8_t *>(storage.data()); }
  const uint8_t *data() const {
    return reinterpret_cast<const uint8_t *>(storage.data());
  }

private:
  CanonicalPlane storage;
  size_t byteCount = 0;
};

// Output bytes not yet written to the file. A record is formatted directly at
// its tail and then committed, with no intermediate copy and no fill.
class OutputBuffer {
public:
  void append(const char *data, size_t size) {
    if (size == 0)
      return;
    std::memcpy(tail(size), data, size);
    used += size;
  }
  // Room for `capacity` more bytes, at the end of the committed ones.
  char *tail(size_t capacity) {
    if (capacity > storage.size() - used)
      grow(capacity);
    return storage.data() + used;
  }
  void commit(size_t size) { used += size; }
  void truncate(size_t size) { used = size; }
  const char *data() const { return storage.data(); }
  size_t size() const { return used; }
  bool empty() const { return used == 0; }
  void clear() { used = 0; }

private:
  [[gnu::noinline]] void grow(size_t capacity) {
    storage.resize(
        std::max(storage.size() * 2, used + capacity + kFlushThreshold));
  }

  std::vector<char> storage;
  size_t used = 0;
};

struct EVCDSession {
  ~EVCDSession() {
    if (file)
      std::fclose(file);
  }

  std::FILE *file = nullptr;
  std::string path;
  std::string buffer;
  bool timescaleSet = false;
  int32_t timescaleExponent = 0;
  uint64_t startTime = 0;
  std::vector<std::string> selections;
  bool planBuilt = false;
  bool planFailed = false;
  bool headerWritten = false;
  bool pendingInitial = false;
  bool enabled = true;
  std::vector<TraceVariable> variables;
  std::vector<std::string> codeText;
  std::vector<TraceRange> ranges;
  TraceShadow shadowValue;
  TraceShadow shadowUnknown;
  uint64_t limitBytes = 0;
  uint64_t writtenBytes = 0;
  bool limitReached = false;
  bool haveEmittedTime = false;
  uint64_t emittedTime = 0;
  std::string scratch;
  // The output so far ends a line: a limit comment needs no line break.
  bool atLineStart = true;
};

} // namespace

// Defined outside the anonymous namespace so the context can hold a pointer to
// it without exposing the layout to every translation unit.
struct CompactVCDState : talos::runtime::vcd::CompactTrace {
  OutputBuffer frame;
  std::vector<char> replay;
  std::chrono::steady_clock::time_point nextCheckpoint;
};

struct VCDTraceState {
  talos_rt_status outputStatus = TALOS_RT_OK;
  std::unique_ptr<CompactVCDState> compact;
  std::FILE *file = nullptr;
  std::string path;
  OutputBuffer buffer;
  bool timescaleSet = false;
  int32_t timescaleExponent = 0;

  std::vector<TraceSelection> selections;
  bool planBuilt = false;
  // A selection that never resolves is reported once and then abandoned, so a
  // mistyped scope cannot silently yield an empty waveform for the whole run.
  bool planFailed = false;
  bool headerWritten = false;
  bool pendingInitial = false;
  bool enabled = true;

  std::vector<TraceVariable> variables;
  // Identifier code per traced range, indexed by TraceVariable::code.
  std::vector<std::string> codeText;
  std::vector<TraceRange> ranges;
  std::vector<uint32_t> firstWord;
  std::vector<TraceWord> words;
  std::vector<uint64_t> fieldMasks;
  TraceShadow shadowValue;
  TraceShadow shadowUnknown;

  uint64_t maxExpandedElements = kDefaultMaxExpandedElements;
  bool limitSet = false;
  uint64_t limitBytes = 0;
  uint64_t writtenBytes = 0;
  bool limitReached = false;

  bool haveEmittedTime = false;
  uint64_t emittedTime = 0;

  // The output so far ends a line: a limit comment needs no line break.
  bool atLineStart = true;
};

struct EVCDTraceState {
  std::vector<std::unique_ptr<EVCDSession>> sessions;
};

namespace {

bool limitEnabled(const VCDTraceState &state) { return state.limitSet; }

// EVCD retains its existing Annex-I convention that a zero limit disables
// limiting. Ordinary Clause-21 VCD instead tracks whether $dumplimit was
// called, so `$dumplimit(0)` is the normative zero-byte maximum.
bool limitEnabled(const EVCDSession &state) { return state.limitBytes != 0; }

template <typename State> void flushBuffer(State &state) {
  if (!state.file)
    return;
  bool ok = true;
  if (!state.buffer.empty()) {
    ok = std::fwrite(state.buffer.data(), 1, state.buffer.size(), state.file) ==
         state.buffer.size();
    state.buffer.clear();
  }
  if (std::fflush(state.file) != 0 || std::ferror(state.file))
    ok = false;
  if constexpr (std::is_same_v<State, VCDTraceState>)
    if (!ok)
      state.outputStatus = TALOS_RT_IO_ERROR;
}

template <typename State> void closeFile(State &state) {
  if (!state.file)
    return;
  flushBuffer(state);
  int result = std::fclose(state.file);
  state.file = nullptr;
  if constexpr (std::is_same_v<State, VCDTraceState>)
    if (result != 0)
      state.outputStatus = TALOS_RT_IO_ERROR;
}

template <typename State>
void appendRaw(State &state, const char *data, size_t size) {
  if (!state.file)
    return;
  if constexpr (std::is_same_v<State, VCDTraceState>)
    if (state.compact && state.compact->journal &&
        state.compact->collectingHeader)
      state.compact->header.append(data, size);
  state.buffer.append(data, size);
  if (size != 0)
    state.atLineStart = data[size - 1] == '\n';
  if (state.buffer.size() >= kFlushThreshold)
    flushBuffer(state);
}

template <typename State> void append(State &state, std::string_view text) {
  if (state.limitReached)
    return;
  if (limitEnabled(state) &&
      (state.writtenBytes >= state.limitBytes ||
       text.size() > state.limitBytes - state.writtenBytes)) {
    state.limitReached = true;
    return;
  }
  state.writtenBytes += text.size();
  appendRaw(state, text.data(), text.size());
}

/// Appends one record built from `parts` at once, so a $dumplimit stops before
/// the whole record or after it, never inside it (21.7.1.5, Syntax 21-20).
/// The record is built in `state.scratch`: no part may view that buffer.
void appendRecord(EVCDSession &state,
                  std::initializer_list<std::string_view> parts) {
  std::string &record = state.scratch;
  record.clear();
  for (std::string_view part : parts)
    record.append(part);
  append(state, std::string_view(record));
}

template <typename State> void appendUnsigned(State &state, uint64_t value) {
  char digits[24];
  int length = std::snprintf(digits, sizeof(digits), "%llu",
                             static_cast<unsigned long long>(value));
  if (length > 0)
    append(state, std::string_view(digits, static_cast<size_t>(length)));
}

template <typename State> void appendSigned(State &state, int64_t value) {
  char digits[24];
  int length = std::snprintf(digits, sizeof(digits), "%lld",
                             static_cast<long long>(value));
  if (length > 0)
    append(state, std::string_view(digits, static_cast<size_t>(length)));
}

// The limit comment is expressly outside the limited waveform payload: IEEE
// 21.7.1.5 requires it after dumping reaches the requested maximum. Use the
// raw buffered path so the limiter cannot suppress its own diagnostic.
void finishLimit(VCDTraceState &state) {
  if (!state.file || !state.limitSet ||
      (!state.limitReached && state.writtenBytes < state.limitBytes))
    return;
  state.limitReached = true;
  std::string comment =
      std::string(state.atLineStart ? "" : "\n") + "$comment dump limit of " +
      std::to_string(state.limitBytes) + " bytes reached $end\n";
  appendRaw(state, comment.data(), comment.size());
  closeFile(state);
  state.compact.reset();
}

template <typename State>
int32_t resolveTimescale(const talos_rt_context *context, const State &state) {
  if (state.timescaleSet)
    return state.timescaleExponent;
  if (context->execution && context->execution->dpi_time_precision != 0)
    return context->execution->dpi_time_precision;
  // The elaborated default precision used by the compiler when a design
  // declares no timescale.
  return -9;
}

std::string timescaleText(int32_t exponent) {
  if (exponent > 2 || exponent < -15)
    exponent = -9;
  if (exponent == 1)
    return "10s";
  if (exponent == 2)
    return "100s";
  static const char *const units[] = {"s", "ms", "us", "ns", "ps", "fs"};
  int32_t magnitude = -exponent;
  const char *unit = units[magnitude / 3];
  switch (magnitude % 3) {
  case 0:
    return std::string("1") + unit;
  case 1:
    return std::string("100") + units[magnitude / 3 + 1];
  default:
    return std::string("10") + units[magnitude / 3 + 1];
  }
}

//===----------------------------------------------------------------------===//
// Plan construction
//===----------------------------------------------------------------------===//

// Resolve a selection to the scope or variable it names. An empty path selects
// the root. Records carry their full hierarchical name, so this is a direct
// match rather than a segment walk.
bool resolveSelection(const DesignDatabaseCache &database,
                      const std::string &path, uint64_t &offset,
                      uint32_t &kind) {
  if (path.empty()) {
    offset = database.root;
    kind = TALOS_RT_DESIGN_RECORD_SCOPE;
    return true;
  }
  std::string_view wanted(path);
  if (wanted.rfind("$root.", 0) == 0)
    wanted.remove_prefix(6);
  auto find = [&](uint64_t begin, uint64_t count, uint64_t size) {
    for (uint64_t index = 0; index != count; ++index) {
      uint64_t candidate = begin + index * size;
      const uint8_t *record;
      uint32_t candidateKind;
      std::string_view name;
      if (!getRecord(database, candidate, record, candidateKind) ||
          !getString(database, nameOffset(record), name) || name != wanted)
        continue;
      if (candidateKind != TALOS_RT_DESIGN_RECORD_SCOPE &&
          !traceableObject(database, candidateKind, record))
        continue;
      offset = candidate;
      kind = candidateKind;
      return true;
    }
    return false;
  };
  return find(database.scopes, database.scopeCount, kScopeRecordSize) ||
         find(database.objects, database.objectCount, kObjectRecordSize);
}

// Collect every traceable object at or below `scopeOffset`. `levels` follows
// the IEEE `$dumpvars` depth, where zero means unlimited and one means the
// named scope only.
void collectScope(const DesignDatabaseCache &database, uint64_t scopeOffset,
                  uint64_t levels, std::unordered_set<uint64_t> &objects) {
  struct Frame {
    uint64_t offset;
    uint64_t depth;
  };
  std::vector<Frame> pending{{scopeOffset, 1}};
  while (!pending.empty()) {
    Frame frame = pending.back();
    pending.pop_back();
    const uint8_t *record;
    uint32_t kind;
    if (!getRecord(database, frame.offset, record, kind) ||
        kind != TALOS_RT_DESIGN_RECORD_SCOPE)
      continue;
    uint64_t child = firstChildOffset(record);
    while (child != 0) {
      const uint8_t *childRecord;
      uint32_t childKind;
      if (!getRecord(database, child, childRecord, childKind))
        break;
      if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE) {
        if (levels == 0 || frame.depth < levels)
          pending.push_back({child, frame.depth + 1});
      } else if (traceableObject(database, childKind, childRecord)) {
        objects.insert(child);
      }
      child = nextSiblingOffset(childRecord, childKind);
    }
  }
}

// Type record accessors. A type is reached through an object or through an
// enclosing array's element pointer, so these take the offset rather than the
// declaring object.
uint32_t typeKind(const DesignDatabaseCache &database, uint64_t typeOffset) {
  return read32(database.data + typeOffset + 4) & UINT32_C(0xff);
}

uint32_t typeFlags(const DesignDatabaseCache &database, uint64_t typeOffset) {
  return read32(database.data + typeOffset + 4) >> 8;
}

uint64_t typeWidth(const DesignDatabaseCache &database, uint64_t typeOffset) {
  return read64(database.data + typeOffset + 8);
}

int64_t typeLeft(const DesignDatabaseCache &database, uint64_t typeOffset) {
  return readI64(database.data + typeOffset + 16);
}

int64_t typeRight(const DesignDatabaseCache &database, uint64_t typeOffset) {
  return readI64(database.data + typeOffset + 24);
}

uint64_t typeElement(const DesignDatabaseCache &database, uint64_t typeOffset) {
  return read64(database.data + typeOffset + 32);
}

// Real storage is serialized as a non-packed scalar named "real" or
// "shortreal". Nothing else in the type record distinguishes those payloads
// from ordinary 64-bit and 32-bit bit vectors.
bool typeIsReal(const DesignDatabaseCache &database, uint64_t typeOffset) {
  if (!isTypeOffset(database, typeOffset))
    return false;
  std::string_view name;
  if (!getString(database, read64(database.data + typeOffset + 72), name))
    return false;
  uint64_t width = typeWidth(database, typeOffset);
  return (name == "real" && width == 64) ||
         (name == "shortreal" && width == 32);
}

bool typeFourState(const DesignDatabaseCache &database, uint64_t typeOffset) {
  if (!isTypeOffset(database, typeOffset))
    return true;
  return (typeFlags(database, typeOffset) & TALOS_RT_DESIGN_TYPE_FOUR_STATE) !=
         0;
}

// An unpacked array occupies a contiguous canonical range but is not a value:
// each element is an independent signal and gets its own `$var`. A packed
// array is an ordinary vector and stays whole.
bool typeIsUnpackedArray(const DesignDatabaseCache &database,
                         uint64_t typeOffset) {
  return isTypeOffset(database, typeOffset) &&
         typeKind(database, typeOffset) == TALOS_RT_DESIGN_TYPE_ARRAY &&
         (typeFlags(database, typeOffset) & TALOS_RT_DESIGN_TYPE_PACKED) == 0;
}

// A managed SystemVerilog string occupies a 64-bit GC word in the canonical
// state plane, but that word is not a waveform value. The physical type name
// is an image-level classification (as it already is for real/shortreal).
// Follow aggregate element/field links so arrays or records containing a
// managed string are excluded as a whole instead of exposing handle bits.
bool typeContainsManagedString(const DesignDatabaseCache &database,
                               uint64_t typeOffset, uint64_t depth = 0) {
  if (!isTypeOffset(database, typeOffset) || depth > database.typeCount)
    return true;
  const uint32_t kind = typeKind(database, typeOffset);
  if (kind == TALOS_RT_DESIGN_TYPE_SCALAR) {
    std::string_view name;
    if (!getString(database, read64(database.data + typeOffset + 72), name))
      return true;
    return name == "string";
  }
  switch (kind) {
  case TALOS_RT_DESIGN_TYPE_ARRAY:
  case TALOS_RT_DESIGN_TYPE_FIELD:
    return typeContainsManagedString(
        database, typeElement(database, typeOffset), depth + 1);
  case TALOS_RT_DESIGN_TYPE_STRUCT:
  case TALOS_RT_DESIGN_TYPE_UNION: {
    uint64_t firstChild = read64(database.data + typeOffset + 40);
    uint64_t childCount = read64(database.data + typeOffset + 48);
    for (uint64_t child = 0; child != childCount; ++child)
      if (typeContainsManagedString(
              database, firstChild + child * kTypeRecordSize, depth + 1))
        return true;
    return false;
  }
  default:
    return false;
  }
}

bool traceableObject(const DesignDatabaseCache &database, uint32_t kind,
                     const uint8_t *record) {
  if (kind != TALOS_RT_DESIGN_RECORD_STORAGE &&
      kind != TALOS_RT_DESIGN_RECORD_NET)
    return false;
  return (read32(record + 4) & TALOS_RT_DESIGN_CAP_READ) != 0 &&
         objectBitWidth(record) != 0 &&
         !typeContainsManagedString(database, objectTypeOffset(record));
}

// Write the `$scope`/`$var`/`$upscope` structure and assign identifier codes.
//
// IEEE 1364 lets several `$var` declarations share one identifier code when the
// variables always hold the same value. Declarations addressing the identical
// canonical range qualify unconditionally — they are the same storage — so they
// fold to one traced range with several `$var` lines, removing the duplicate
// from both the file and the per-slot difference. Merely-connected nets are not
// folded: that needs connectivity metadata only the bytecode tier carries, and
// would make one design dump differently per execution tier.
struct PlanBuilder {
  const talos_rt_context *context;
  VCDTraceState &state;
  const DesignDatabaseCache &database;
  const std::unordered_set<uint64_t> &selected;
  // Scopes on the path to at least one selected object.
  std::unordered_set<uint64_t> liveScopes;
  // Canonical (bit offset, width) to the traced range that already owns a code.
  std::map<std::pair<uint64_t, uint64_t>, uint32_t> codeByRange;

  void markLiveScopes() {
    for (uint64_t object : selected) {
      const uint8_t *record;
      uint32_t kind;
      if (!getRecord(database, object, record, kind))
        continue;
      uint64_t scope = parentOffset(record);
      while (scope != 0 && liveScopes.insert(scope).second) {
        const uint8_t *scopeRecord;
        uint32_t scopeKind;
        if (!getRecord(database, scope, scopeRecord, scopeKind))
          break;
        scope = parentOffset(scopeRecord);
      }
    }
  }

  // Determine whether expanding every unpacked dimension stays within one
  // object's declaration budget. Checking only each dimension admits an
  // exponential number of leaves for nested arrays.
  bool expandedLeafCount(uint64_t typeOffset, uint64_t width, unsigned depth,
                         uint64_t limit, uint64_t &count) const {
    if (depth == kMaxUnpackedDepth ||
        !typeIsUnpackedArray(database, typeOffset)) {
      count = 1;
      return true;
    }
    uint64_t element = typeElement(database, typeOffset);
    uint64_t elementWidth =
        isTypeOffset(database, element) ? typeWidth(database, element) : 0;
    int64_t left = typeLeft(database, typeOffset);
    int64_t right = typeRight(database, typeOffset);
    uint64_t extent = left >= right ? static_cast<uint64_t>(left - right) + 1
                                    : static_cast<uint64_t>(right - left) + 1;
    if (elementWidth == 0 || extent == 0 || width % extent != 0 ||
        elementWidth > width / extent) {
      count = 1;
      return true;
    }
    if (extent > limit)
      return false;
    uint64_t childCount = 0;
    if (!expandedLeafCount(element, elementWidth, depth + 1, limit / extent,
                           childCount))
      return false;
    count = extent * childCount;
    return true;
  }

  // Declare one traced range: a scalar, a vector, or one element of an
  // unpacked array. `name` is already the fully qualified leaf spelling.
  void declareLeaf(uint64_t typeOffset, uint64_t sourceBit, uint64_t width,
                   std::string_view name, std::string_view keyword) {
    const uint64_t *aliases = context->vcdAliasRows;
    if (aliases) {
      uint64_t lo = 0, hi = context->vcdAliasCount;
      while (lo < hi) {
        uint64_t mid = lo + (hi - lo) / 2;
        if (aliases[3 * mid] <= sourceBit)
          lo = mid + 1;
        else
          hi = mid;
      }
      if (lo) {
        const uint64_t *alias = aliases + 3 * (lo - 1);
        uint64_t low = sourceBit - alias[0];
        if (low < alias[2] && width <= alias[2] - low) {
          const uint8_t *value = nullptr, *unknown = nullptr;
          uint64_t alternative = alias[1] + low;
          bool same = dumpPlanes(context, value, unknown) == TALOS_RT_OK;
          for (uint64_t bit = 0; same && bit != width; ++bit)
            same = bitAt(value, sourceBit + bit) ==
                       bitAt(value, alternative + bit) &&
                   bitAt(unknown, sourceBit + bit) ==
                       bitAt(unknown, alternative + bit);
          if (same)
            sourceBit = alternative;
        }
      }
    }
    bool isReal = typeIsReal(database, typeOffset);
    auto [entry, inserted] =
        codeByRange.try_emplace(std::make_pair(sourceBit, width),
                                static_cast<uint32_t>(state.codeText.size()));
    uint32_t code = entry->second;
    bool fourState = !isReal && typeFourState(database, typeOffset);
    if (inserted) {
      TraceVariable variable;
      variable.sourceBit = sourceBit;
      variable.width = width;
      variable.code = code;
      variable.fourState = fourState;
      variable.isReal = isReal;
      std::string text = identifierCode(code);
      state.variables.push_back(variable);
      state.codeText.push_back(std::move(text));
    } else if (fourState) {
      // Two names for one range may disagree on four-state-ness only if one is
      // a two-state view of four-state storage. Emit the wider interpretation
      // so an X deposited through the other name is still visible. Variables
      // are still in code order here; buildRanges sorts them afterwards.
      state.variables[code].fourState = true;
    }
    append(state, "$var ");
    append(state, isReal ? "real" : keyword);
    append(state, " ");
    appendUnsigned(state, width);
    append(state, " ");
    if (state.compact->journal)
      state.compact->headerCodes.push_back(
          {state.compact->header.size(), code, state.codeText[code].size()});
    append(state, state.codeText[code]);
    append(state, " ");
    append(state, name);
    // A real carries no bit range; a viewer reads its `r` records as numbers.
    // The declared range describes the bit extent only when it spans exactly
    // the traced width, so a range that enumerates anything else is replaced.
    if (width > 1 && !isReal) {
      int64_t left = 0;
      int64_t right = 0;
      uint64_t extent = 0;
      if (isTypeOffset(database, typeOffset)) {
        left = typeLeft(database, typeOffset);
        right = typeRight(database, typeOffset);
        extent = left >= right ? static_cast<uint64_t>(left - right) + 1
                               : static_cast<uint64_t>(right - left) + 1;
      }
      if (extent != width) {
        left = static_cast<int64_t>(width) - 1;
        right = 0;
      }
      append(state, " [");
      appendSigned(state, left);
      append(state, ":");
      appendSigned(state, right);
      append(state, "]");
    }
    append(state, " $end\n");
  }

  // Expand unpacked dimensions into one declaration per element, the form a
  // waveform viewer renders as an array. Element ordinal zero occupies the
  // lowest canonical bits and carries the leftmost declared index.
  void declareType(uint64_t typeOffset, uint64_t sourceBit, uint64_t width,
                   const std::string &name, std::string_view keyword,
                   unsigned depth) {
    if (depth == kMaxUnpackedDepth ||
        !typeIsUnpackedArray(database, typeOffset))
      return declareLeaf(typeOffset, sourceBit, width, name, keyword);
    uint64_t element = typeElement(database, typeOffset);
    uint64_t elementWidth =
        isTypeOffset(database, element) ? typeWidth(database, element) : 0;
    int64_t left = typeLeft(database, typeOffset);
    int64_t right = typeRight(database, typeOffset);
    uint64_t extent = left >= right ? static_cast<uint64_t>(left - right) + 1
                                    : static_cast<uint64_t>(right - left) + 1;
    if (elementWidth == 0 || extent == 0 || width % extent != 0 ||
        elementWidth > width / extent)
      return declareLeaf(typeOffset, sourceBit, width, name, keyword);
    int64_t step = right >= left ? 1 : -1;
    for (uint64_t ordinal = 0; ordinal != extent; ++ordinal) {
      std::string elementName = name;
      elementName.push_back('[');
      elementName.append(
          std::to_string(left + step * static_cast<int64_t>(ordinal)));
      elementName.push_back(']');
      declareType(element, sourceBit + ordinal * (width / extent), elementWidth,
                  elementName, keyword, depth + 1);
    }
  }

  void emitVariable(const uint8_t *record, std::string_view name,
                    std::string_view scopeName) {
    std::string leaf(leafName(name, scopeName));
    uint64_t leafCount = 0;
    if (!expandedLeafCount(objectTypeOffset(record), objectBitWidth(record), 0,
                           state.maxExpandedElements, leafCount)) {
      // Omit rather than smash. A single wide vector would be well-formed VCD
      // that silently presents several independent signals as one value, with
      // nothing in the file to say so.
      std::fprintf(stderr,
                   "talos: not dumping %s: the unpacked array exceeds the "
                   "waveform array limit of %llu "
                   "(raise TALOS_RT_DUMP_MAX_ARRAY to include it)\n",
                   leaf.c_str(),
                   static_cast<unsigned long long>(state.maxExpandedElements));
      return;
    }
    declareType(objectTypeOffset(record), objectStateBit(record),
                objectBitWidth(record), leaf, varKeyword(record), 0);
  }

  // IEEE 1800-2023 Table 21-11 masquerades int and a default-based enum as
  // integer, and every other integral variable as reg. integer and time keep
  // their IEEE 1364-2005 VCD types. A 32-bit enum's base type is not recorded,
  // so an explicitly based one also reads as the default integer.
  std::string_view varKeyword(const uint8_t *record) const {
    uint32_t packed = read32(record);
    if (static_cast<uint32_t>(talos::reflection::unpackRecordKind(packed)) ==
        TALOS_RT_DESIGN_RECORD_NET)
      return "wire";
    // vpiIntVar, vpiIntegerVar, vpiTimeVar and vpiEnumVar respectively.
    switch (talos::reflection::unpackRecordKindPayload(packed)) {
    case 612:
    case 25:
      return "integer";
    case 63:
      return "time";
    case 617:
      return objectBitWidth(record) == 32 ? "integer" : "reg";
    default:
      return "reg";
    }
  }

  void emitScope(uint64_t scopeOffset, std::string_view parentName) {
    const uint8_t *record;
    uint32_t kind;
    if (!getRecord(database, scopeOffset, record, kind) ||
        kind != TALOS_RT_DESIGN_RECORD_SCOPE)
      return;
    std::string_view name;
    if (!getString(database, nameOffset(record), name))
      return;
    append(state, "$scope module ");
    append(state, leafName(name, parentName));
    append(state, " $end\n");
    uint64_t child = firstChildOffset(record);
    while (child != 0) {
      const uint8_t *childRecord;
      uint32_t childKind;
      if (!getRecord(database, child, childRecord, childKind))
        break;
      if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE) {
        if (liveScopes.count(child) != 0)
          emitScope(child, name);
      } else if (selected.count(child) != 0) {
        std::string_view childName;
        if (getString(database, nameOffset(childRecord), childName))
          emitVariable(childRecord, childName, name);
      }
      child = nextSiblingOffset(childRecord, childKind);
    }
    append(state, "$upscope $end\n");
  }

  // The design database has a synthetic SystemVerilog `$root` record so VPI
  // and hierarchical lookup have a concrete anchor. VCD has an implicit root;
  // its conventional hierarchy starts with the top-level modules themselves.
  // Preserve explicitly named roots supplied by runtime clients, but flatten
  // the compiler-generated root and emit its live children as VCD roots.
  void emitDesign() {
    const uint8_t *rootRecord;
    uint32_t rootKind;
    std::string_view rootName;
    if (!getRecord(database, database.root, rootRecord, rootKind) ||
        rootKind != TALOS_RT_DESIGN_RECORD_SCOPE ||
        !getString(database, nameOffset(rootRecord), rootName))
      return;
    if (rootName != "$root" && rootName != "\\$root ") {
      emitScope(database.root, {});
      return;
    }

    uint64_t child = firstChildOffset(rootRecord);
    while (child != 0) {
      const uint8_t *childRecord;
      uint32_t childKind;
      if (!getRecord(database, child, childRecord, childKind))
        break;
      if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE) {
        if (liveScopes.count(child) != 0)
          emitScope(child, rootName);
      } else if (selected.count(child) != 0) {
        std::string_view childName;
        if (getString(database, nameOffset(childRecord), childName))
          emitVariable(childRecord, childName, rootName);
      }
      child = nextSiblingOffset(childRecord, childKind);
    }
  }
};

// Coalesce the traced variables into byte-aligned windows and size the shadow
// planes. Variables are sorted by canonical offset so each window owns a
// contiguous index range.
template <typename State>
void buildRanges(State &state, uint64_t stateBitCount, bool twoState) {
  std::sort(state.variables.begin(), state.variables.end(),
            [](const TraceVariable &left, const TraceVariable &right) {
              if (left.sourceBit != right.sourceBit)
                return left.sourceBit < right.sourceBit;
              return left.width < right.width;
            });
  uint64_t stateBytes = (stateBitCount + 7) / 8;
  state.shadowValue.reset(static_cast<size_t>(stateBytes));
  if (!twoState)
    state.shadowUnknown.reset(static_cast<size_t>(stateBytes));
  state.ranges.clear();
  for (uint32_t index = 0; index != state.variables.size(); ++index) {
    TraceVariable &variable = state.variables[index];
    // A two-state simulation can retain a four-state source declaration.
    // Its trace uses the value plane alone, including when no X/Z plane exists.
    variable.fourState &= !twoState;
    uint64_t begin = variable.sourceBit / 8;
    uint64_t end = (variable.sourceBit + variable.width + 7) / 8;
    if (end > stateBytes)
      end = stateBytes;
    if (!state.ranges.empty()) {
      TraceRange &last = state.ranges.back();
      if (begin < last.byteEnd ||
          (index - last.firstVariable < kVariablesPerRange &&
           begin - last.byteEnd <= kRangeMergeGap)) {
        last.byteEnd = std::max(last.byteEnd, end);
        last.lastVariable = index + 1;
        continue;
      }
    }
    TraceRange range;
    range.byteBegin = begin;
    range.byteEnd = end;
    range.firstVariable = index;
    range.lastVariable = index + 1;
    state.ranges.push_back(range);
  }
}

// Precompute the masks once, after aliases and the trace order are fixed.
// Overlapping declarations compare against the same old shadow until the
// complete byte range has been emitted (21.7.2).
void buildTraceWords(VCDTraceState &state) {
  const uint64_t bytes = state.shadowValue.size();
  state.firstWord.clear();
  state.words.clear();
  state.fieldMasks.resize(state.variables.size());
  for (const TraceRange &range : state.ranges) {
    state.firstWord.push_back(state.words.size());
    for (uint32_t i = range.firstVariable; i < range.lastVariable;) {
      const TraceVariable &first = state.variables[i];
      uint64_t byte = bytes >= 8 ? std::min(first.sourceBit / 8, bytes - 8) : 0;
      uint32_t begin = i;
      while (bytes >= 8 && i < range.lastVariable) {
        const TraceVariable &v = state.variables[i];
        uint64_t shift = v.sourceBit - 8 * byte;
        if (v.isReal || v.fourState != first.fourState || shift >= 64 ||
            v.width > 64 - shift)
          break;
        uint64_t mask =
            v.width == 64 ? UINT64_MAX : (uint64_t{1} << v.width) - 1;
        state.fieldMasks[i++] = mask << shift;
      }
      if (i == begin) {
        ++i;
        byte = UINT64_MAX;
      }
      state.words.push_back({byte, i, first.fourState});
    }
  }
  state.firstWord.push_back(state.words.size());
}

//===----------------------------------------------------------------------===//
// Emission
//===----------------------------------------------------------------------===//

/// Writes `value` in decimal ending just before `end`; returns its start.
char *formatDecimal(uint64_t value, char *end) {
  do {
    *--end = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value != 0);
  return end;
}

void emitTime(EVCDSession &state, uint64_t time) {
  if (state.haveEmittedTime && state.emittedTime == time)
    return;
  // `#`, at most 20 digits and a newline, as one record.
  char text[24];
  char *end = text + sizeof(text);
  *--end = '\n';
  char *begin = formatDecimal(time, end);
  *--begin = '#';
  append(state, std::string_view(
                    begin, static_cast<size_t>(text + sizeof(text) - begin)));
  state.haveEmittedTime = true;
  state.emittedTime = time;
}

/// The eight binary digits of each byte value, most significant first.
struct ByteDigits {
  // A zero row follows the last value, so an eight-byte read from inside the
  // last row stays in the table.
  char digits[257][8];
  constexpr ByteDigits() : digits() {
    for (unsigned value = 0; value != 256; ++value)
      for (unsigned bit = 0; bit != 8; ++bit)
        digits[value][bit] =
            static_cast<char>('0' + ((value >> (7 - bit)) & 1));
  }
};
constexpr ByteDigits kByteDigits;

/// Writes the binary digits of a known `value` without leading zeros (a zero
/// value is "0", 21.7.2.2) to `out`; returns the end. `out` must have eight
/// bytes of room past the digits.
char *formatKnownBinary(uint64_t value, char *out) {
  if (value == 0) {
    *out++ = '0';
    return out;
  }
  unsigned digits = 64 - static_cast<unsigned>(__builtin_clzll(value));
  unsigned head = (digits - 1) % 8 + 1;
  unsigned shift = digits - head;
  // Eight bytes are always copied: the caller provides that much room past
  // the digits, and the bytes beyond `head` are overwritten next.
  std::memcpy(out, kByteDigits.digits[(value >> shift) & 0xff] + (8 - head),
              8);
  out += head;
  while (shift != 0) {
    shift -= 8;
    std::memcpy(out, kByteDigits.digits[(value >> shift) & 0xff], 8);
    out += 8;
  }
  return out;
}

/// The `width` (at most 64) bits of `plane` starting at `bit`, bit 0 lowest.
uint64_t loadBits(const uint8_t *plane, uint64_t bit, uint64_t width) {
  const uint8_t *base = plane + bit / 8;
  unsigned shift = static_cast<unsigned>(bit % 8);
  size_t bytes = static_cast<size_t>((shift + width + 7) / 8);
  uint64_t low = 0;
  for (size_t index = 0; index != bytes && index != 8; ++index)
    low |= uint64_t{base[index]} << (8 * index);
  uint64_t value = low >> shift;
  if (bytes > 8)
    value |= uint64_t{base[8]} << (64 - shift);
  if (width < 64)
    value &= (uint64_t{1} << width) - 1;
  return value;
}

/// loadBits for a plane of `planeBytes` bytes: one eight-byte load (and one
/// more byte when the bits straddle it) where the plane has room for it.
uint64_t loadWord(const uint8_t *plane, size_t planeBytes, uint64_t bit,
                  uint64_t width) {
  // The runtime ABI is little-endian (ABI.cpp), as loadBits assumes too.
  uint64_t byte = bit / 8;
  if (byte + 9 > planeBytes)
    return loadBits(plane, bit, width);
  unsigned shift = static_cast<unsigned>(bit % 8);
  uint64_t low;
  std::memcpy(&low, plane + byte, sizeof(low));
  uint64_t value = low >> shift;
  if (shift != 0 && shift + width > 64)
    value |= uint64_t{plane[byte + 8]} << (64 - shift);
  if (width < 64)
    value &= (uint64_t{1} << width) - 1;
  return value;
}

/// The eight value characters of one plane byte, most significant bit first,
/// as a little-endian word: `0`/`1` where `unknown` is clear, `x` (value 0) or
/// `z` (value 1) where it is set. Each byte of the word is computed
/// independently: no step carries or borrows across bytes.
uint64_t byteCharacters(unsigned value, unsigned unknown) {
  uint64_t digits;
  std::memcpy(&digits, kByteDigits.digits[value], sizeof(digits));
  if (unknown == 0)
    return digits;
  constexpr uint64_t kZeros = 0x3030303030303030ull; // '0' x 8
  constexpr uint64_t kXs = 0x7878787878787878ull;    // 'x' x 8
  uint64_t mask;
  std::memcpy(&mask, kByteDigits.digits[unknown], sizeof(mask));
  // Bytes of 0 or 1 become 0x00 or 0xff; the products do not overlap.
  mask = (mask - kZeros) * 0xff;
  uint64_t unknownCharacters = kXs + 2 * (digits - kZeros); // 'x' + 2 == 'z'
  return (digits & ~mask) | (unknownCharacters & mask);
}

/// Writes the characters of the low `count` (1 to 64) bits of `value` and
/// `unknown`, most significant first, at `out`, which has eight bytes of room
/// past them; returns their end.
char *formatWordDigits(uint64_t value, uint64_t unknown, unsigned count,
                       char *out) {
  unsigned head = (count - 1) % 8 + 1;
  unsigned shift = count - head;
  // The head byte's characters for bits above `count` lead the word.
  uint64_t characters = byteCharacters((value >> shift) & 0xff,
                                       (unknown >> shift) & 0xff) >>
                        (8 * (8 - head));
  std::memcpy(out, &characters, sizeof(characters));
  out += head;
  while (shift != 0) {
    shift -= 8;
    characters =
        byteCharacters((value >> shift) & 0xff, (unknown >> shift) & 0xff);
    std::memcpy(out, &characters, sizeof(characters));
    out += 8;
  }
  return out;
}

[[gnu::noinline]] int formatRealWord(uint64_t word, uint64_t width,
                                     char *text) {
  double value = 0;
  if (width == 32) {
    uint32_t shortBits = static_cast<uint32_t>(word);
    float shortValue = 0;
    std::memcpy(&shortValue, &shortBits, sizeof(shortValue));
    value = shortValue;
  } else {
    std::memcpy(&value, &word, sizeof(value));
  }
  return std::snprintf(text, 40, "r%.16g", value);
}

void updateShadow(VCDTraceState &state, const uint8_t *valuePlane,
                  const uint8_t *unknownPlane) {
  for (const TraceRange &range : state.ranges) {
    size_t length = static_cast<size_t>(range.byteEnd - range.byteBegin);
    std::memcpy(state.shadowValue.data() + range.byteBegin,
                valuePlane + range.byteBegin, length);
    if (unknownPlane)
      std::memcpy(state.shadowUnknown.data() + range.byteBegin,
                  unknownPlane + range.byteBegin, length);
  }
}

using talos::runtime::vcd::CompactTrace;

// Small indices, frame sizes and time deltas occupy a single byte.
char *writeJournalNumber(char *p, uint64_t n) {
  while (n >= 128) {
    *p++ = static_cast<char>((n & 127) | 128);
    n >>= 7;
  }
  *p++ = static_cast<char>(n);
  return p;
}

bool readJournalNumber(const char *&p, const char *end, uint64_t &value) {
  value = 0;
  for (unsigned shift = 0; shift < 64 && p != end; shift += 7) {
    auto byte = static_cast<uint8_t>(*p++);
    if (shift == 63 && byte > 1)
      return false;
    value |= uint64_t(byte & 127) << shift;
    if (!(byte & 128))
      return true;
  }
  return false;
}

void appendJournalNumber(OutputBuffer &buffer, uint64_t n) {
  char *begin = buffer.tail(10);
  buffer.commit(writeJournalNumber(begin, n) - begin);
}

void appendPlane(OutputBuffer &frame, const uint8_t *plane, size_t planeBytes,
                 const TraceVariable &v) {
  size_t bytes = (v.width + 7) / 8;
  char *out = frame.tail(bytes + 8);
  if (v.sourceBit % 8 == 0) {
    std::memcpy(out, plane + v.sourceBit / 8, bytes);
  } else {
    for (uint64_t low = 0; low < v.width; low += 64) {
      uint64_t word = loadWord(plane, planeBytes, v.sourceBit + low,
                               std::min<uint64_t>(64, v.width - low));
      std::memcpy(out + low / 8, &word, sizeof(word));
    }
  }
  frame.commit(bytes);
}

enum class FrameKind : uint8_t { Changes, Initial, All, Off, On };

std::string_view commandFor(FrameKind kind) {
  switch (kind) {
  case FrameKind::Initial:
    return "$dumpvars\n";
  case FrameKind::All:
    return "$dumpall\n";
  case FrameKind::Off:
    return "$dumpoff\n";
  case FrameKind::On:
    return "$dumpon\n";
  case FrameKind::Changes:
    return {};
  }
  return {};
}

// A journal frame contains one packed value per distinct changed history,
// including X/Z. Scalar changes need just a node index and a value byte.
bool captureFrame(VCDTraceState &state, const uint8_t *value,
                  const uint8_t *unknown, uint64_t time, FrameKind kind) {
  auto &trace = *state.compact;
  auto &out = trace.frame;
  out.clear();
  // Reserve a prefix for the frame size, filled once the last change is known.
  out.tail(10);
  out.commit(10);
  appendJournalNumber(out, time - state.emittedTime);
  char command = static_cast<char>(kind);
  out.append(&command, 1);
  for (uint32_t c : trace.changed) {
    const auto &field = trace.fields[c];
    const auto &group = trace.groups[field.group];
    const auto &v = state.variables[c];
    char *start = out.tail(32);
    char *p = writeJournalNumber(start, group.node);
    if (kind == FrameKind::Off) {
      // Each selected integral value has an all-X checkpoint. The node
      // supplies its width at replay, so the payload is implicit.
      out.commit(p - start);
    } else if (v.width == 1 && !v.isReal) {
      *p++ = fourStateChar(group.value, group.unknown);
      out.commit(p - start);
    } else if (v.width <= 64) {
      size_t bytes = (v.width + 7) / 8;
      *p++ = group.unknown != 0;
      std::memcpy(p, &group.value, sizeof(group.value));
      p += bytes;
      if (group.unknown) {
        std::memcpy(p, &group.unknown, sizeof(group.unknown));
        p += bytes;
      }
      out.commit(p - start);
    } else {
      char hasUnknown = !v.isReal && v.fourState && unknown;
      *p++ = hasUnknown;
      out.commit(p - start);
      appendPlane(out, value, state.shadowValue.size(), v);
      if (hasUnknown)
        appendPlane(out, unknown, state.shadowValue.size(), v);
    }
  }
  if (!trace.journal)
    return true;
  uint64_t size = out.size() - 10;
  char prefix[10];
  size_t prefixSize = writeJournalNumber(prefix, size) - prefix;
  char *data = out.tail(0) - size - prefixSize;
  std::memcpy(data, prefix, prefixSize);
  if (std::fwrite(data, 1, prefixSize + size, trace.journal.get()) !=
      prefixSize + size)
    return false;
  trace.bytes += prefixSize + size;
  return true;
}

// Convert one packed sample or explicit checkpoint to complete VCD records.
bool renderFrame(const VCDTraceState &state, const CompactTrace::Layout &layout,
                 const char *frame, size_t length, OutputBuffer &out,
                 uint64_t &time, bool firstFrame) {
  const char *p = frame, *end = frame + length;
  uint64_t delta;
  if (!readJournalNumber(p, end, delta) || p == end)
    return false;
  auto kind = static_cast<FrameKind>(static_cast<uint8_t>(*p++));
  if (kind > FrameKind::On)
    return false;
  time += delta;
  if (firstFrame || delta) {
    char digits[24];
    char *endDigits = digits + sizeof(digits);
    *--endDigits = '\n';
    char *begin = formatDecimal(time, endDigits);
    *--begin = '#';
    out.append(begin, digits + sizeof(digits) - begin);
  }
  auto command = commandFor(kind);
  out.append(command.data(), command.size());
  while (p != end) {
    uint64_t node;
    if (!readJournalNumber(p, end, node) || node >= layout.spans.size() ||
        (p == end && kind != FrameKind::Off))
      return false;
    const auto &v = state.variables[state.compact->nodes[node].variable];
    size_t start = out.size();
    if (kind == FrameKind::Off) {
      if (v.width == 1)
        out.append("x", 1);
      else
        out.append("bx ", 3);
    } else if (v.width == 1 && !v.isReal) {
      out.append(p++, 1);
    } else {
      bool hasUnknown = *p++;
      size_t bytes = (v.width + 7) / 8;
      if (static_cast<size_t>(end - p) / (hasUnknown ? 2 : 1) < bytes)
        return false;
      const auto *value = reinterpret_cast<const uint8_t *>(p);
      const auto *unknown = hasUnknown ? value + bytes : nullptr;
      p += bytes * (hasUnknown ? 2 : 1);
      if (v.isReal) {
        uint64_t word = 0;
        std::memcpy(&word, value, std::min(bytes, sizeof(word)));
        char *text = out.tail(41);
        int n = formatRealWord(word, v.width, text);
        if (n <= 0 || n >= 40)
          return false;
        text[n] = ' ';
        out.commit(n + 1);
      } else if (v.width <= 64 &&
                 (!hasUnknown || loadWord(unknown, bytes, 0, v.width) == 0)) {
        uint64_t word = 0;
        std::memcpy(&word, value, bytes);
        if (v.width < 64)
          word &= (uint64_t{1} << v.width) - 1;
        char *text = out.tail(v.width + 10);
        *text = 'b';
        char *last = formatKnownBinary(word, text + 1);
        *last++ = ' ';
        out.commit(last - text);
      } else {
        size_t width = talos::runtime::vcd::compactVectorWidth(
            value, unknown, bytes, 0, v.width);
        char *text = out.tail(width + 10);
        *text = 'b';
        char *last = talos::runtime::vcd::formatVectorDigits(
            value, unknown, bytes, 0, width, text + 1);
        *last++ = ' ';
        out.commit(last - text);
      }
    }
    const size_t prefix = out.size() - start;
    auto span = layout.spans[node];
    for (uint32_t id = span.begin; id < span.end; ++id) {
      const auto &code = layout.codes[id];
      if (id != span.begin) {
        char *dest = out.tail(prefix + 8);
        std::memcpy(dest, out.data() + start, prefix);
        out.commit(prefix);
      }
      std::memcpy(out.tail(8), &code.text, 8);
      out.commit(code.length);
    }
  }
  if (!command.empty())
    out.append("$end\n", 5);
  return true;
}

#ifdef TALOS_POSIX_COMPACT_VCD
bool stillNamesSnapshotTarget(const std::string &path,
                              const struct stat &opened) {
  struct stat named{};
  return ::lstat(path.c_str(), &named) == 0 && S_ISREG(named.st_mode) &&
         named.st_nlink == 1 && named.st_dev == opened.st_dev &&
         named.st_ino == opened.st_ino && named.st_mode == opened.st_mode &&
         named.st_uid == opened.st_uid && named.st_gid == opened.st_gid;
}

bool stillNamesOpenFile(const std::string &path, int fd) {
  struct stat opened{};
  return ::fstat(fd, &opened) == 0 && stillNamesSnapshotTarget(path, opened);
}

struct TemporaryTraceFile {
  std::string path;
  std::FILE *file = nullptr;
  bool open(const std::string &destination, bool anonymous) {
    std::string pattern = destination + ".XXXXXX";
    int fd = ::mkstemp(pattern.data());
    if (fd < 0)
      return false;
    path = std::move(pattern);
    file = ::fdopen(fd, "w+b");
    if (!file) {
      if (stillNamesOpenFile(path, fd))
        ::unlink(path.c_str());
      ::close(fd);
      return false;
    }
    talos_rt_close_on_exec(file);
    if (anonymous) {
      if (!stillNamesOpenFile(path, fd) || ::unlink(path.c_str()))
        return false;
      path.clear();
    }
    return true;
  }
  ~TemporaryTraceFile() {
    if (file) {
      if (!path.empty() && stillNamesOpenFile(path, fileno(file)))
        ::unlink(path.c_str());
      std::fclose(file);
    }
  }
};
#endif

CompactTrace::Code packIdentifier(std::string_view id) {
  // A base-94 uint32_t identifier and its terminating newline fit in a word.
  CompactTrace::Code packed{0, id.size() + 1};
  std::memcpy(&packed.text, id.data(), id.size());
  reinterpret_cast<char *>(&packed.text)[id.size()] = '\n';
  return packed;
}

// A value change, command, or timestamp occupies one complete line.
void truncateAtRecordBoundary(OutputBuffer &out, size_t limit) {
  while (limit && out.data()[limit - 1] != '\n')
    --limit;
  out.truncate(limit);
}

#ifdef TALOS_POSIX_COMPACT_VCD
// Files carrying metadata the replacement cannot reproduce keep their inode.
bool prepareSnapshotMetadata(int source, const struct stat &original,
                             int target) {
  struct stat created{};
  if (::fstat(target, &created) || created.st_uid != original.st_uid ||
      created.st_gid != original.st_gid || (original.st_mode & 07000))
    return false;
#if defined(__linux__)
  auto plain = [](int fd) {
    auto size = ::flistxattr(fd, nullptr, 0);
    return size == 0 || (size < 0 && errno == ENOTSUP);
  };
  // Backup and copy-on-write policies are inode flags, separate from xattrs.
  auto readFlags = [](int fd, unsigned long &flags) {
    return ::ioctl(fd, FS_IOC_GETFLAGS, &flags) == 0 || errno == ENOTTY ||
           errno == EOPNOTSUPP;
  };
  unsigned long sourceFlags = 0, targetFlags = 0;
  if (!plain(source) || !plain(target) || !readFlags(source, sourceFlags) ||
      !readFlags(target, targetFlags) || sourceFlags != targetFlags)
    return false;
#elif defined(__APPLE__)
  if (original.st_flags ||
      ::fcopyfile(source, target, nullptr, COPYFILE_ACL | COPYFILE_XATTR))
    return false;
#else
  return false;
#endif
  return ::fchmod(target, original.st_mode & 0777) == 0;
}
#endif

bool publishSnapshot(VCDTraceState &state, bool separate) {
#ifdef TALOS_POSIX_COMPACT_VCD
  auto &trace = *state.compact;
  auto started = std::chrono::steady_clock::now();
  flushBuffer(state);
  struct stat opened{};
  if (state.outputStatus != TALOS_RT_OK ||
      ::fstat(fileno(state.file), &opened) ||
      !stillNamesSnapshotTarget(state.path, opened))
    return false;
  TemporaryTraceFile temporary;
  if (!temporary.open(state.path, false))
    return false;
  std::setvbuf(temporary.file, nullptr, _IONBF, 0);
  auto layout = trace.layout(
      separate, [](uint32_t id) { return packIdentifier(identifierCode(id)); });
  OutputBuffer out;
  size_t consumed = 0;
  for (const auto &decl : trace.headerCodes) {
    out.append(trace.header.data() + consumed, decl.offset - consumed);
    auto id = identifierCode(layout.physical[decl.code]);
    out.append(id.data(), id.size());
    consumed = decl.offset + decl.length;
  }
  out.append(trace.header.data() + consumed, trace.header.size() - consumed);
  uint64_t written = 0;
  auto flush = [&]() {
    bool ok =
        std::fwrite(out.data(), 1, out.size(), temporary.file) == out.size();
    written += out.size();
    out.clear();
    return ok;
  };
  if (std::fflush(trace.journal.get()) ||
      ::fseeko(trace.journal.get(), 0, SEEK_SET))
    return false;
  uint64_t remaining = trace.bytes, time = 0, replayed = 0;
  auto fitsLimit = [&]() {
    return !state.limitSet || (written <= state.limitBytes &&
                               out.size() <= state.limitBytes - written);
  };
  while (remaining && fitsLimit()) {
    char prefix[10];
    size_t length = 0;
    do {
      int byte = std::fgetc(trace.journal.get());
      if (byte == EOF || length == sizeof(prefix) || !remaining)
        return false;
      --remaining;
      prefix[length++] = static_cast<char>(byte);
    } while (static_cast<uint8_t>(prefix[length - 1]) & 128);
    const char *begin = prefix;
    uint64_t size;
    if (!readJournalNumber(begin, prefix + length, size) || size > remaining ||
        size > SIZE_MAX)
      return false;
    trace.replay.resize(size);
    if (std::fread(trace.replay.data(), 1, size, trace.journal.get()) != size ||
        !renderFrame(state, layout, trace.replay.data(), size, out, time,
                     replayed == 0))
      return false;
    remaining -= size;
    if (!fitsLimit() && replayed >= trace.publishedSamples) {
      // All previously visible frames fit. Keep each complete new record
      // that also fits, even when the last frame contains a much wider value.
      truncateAtRecordBoundary(out,
                               static_cast<size_t>(state.limitBytes - written));
      state.limitReached = true;
      break;
    }
    ++replayed;
    if (out.size() >= kFlushThreshold && fitsLimit() && !flush())
      return false;
  }
  if (::fseeko(trace.journal.get(), 0, SEEK_END))
    return false;
  if (!fitsLimit()) {
    // The previously published prefix is valid. Extending it with the
    // requested independent identifiers would exceed the active limit.
    state.limitReached = true;
    return true;
  }
  if (!flush() || std::fflush(temporary.file) ||
      !prepareSnapshotMetadata(fileno(state.file), opened,
                               fileno(temporary.file)) ||
      !stillNamesOpenFile(temporary.path, fileno(temporary.file)) ||
      !stillNamesSnapshotTarget(state.path, opened) ||
      std::rename(temporary.path.c_str(), state.path.c_str()))
    return false;
  temporary.path.clear();
  std::swap(state.file, temporary.file);
  state.writtenBytes = written;
  auto finished = std::chrono::steady_clock::now();
  // Large traces can take seconds to replay. Leave at least four replay
  // durations between scheduled rewrites while a partition keeps splitting.
  trace.nextCheckpoint =
      finished + std::max<std::chrono::steady_clock::duration>(
                     std::chrono::seconds(1), 4 * (finished - started));
  trace.checkpointBytes = trace.bytes;
  trace.publishedSamples = replayed;
  trace.published = std::move(layout);
  if (trace.groups.size() == trace.fields.size()) {
    // Distinct histories never merge. All subsequent frames can use this
    // published layout directly; no later force can require replay.
    trace.journal.reset();
    std::string{}.swap(trace.header);
    std::vector<CompactTrace::HeaderCode>{}.swap(trace.headerCodes);
    std::vector<char>{}.swap(trace.replay);
  }
  return true;
#else
  return false;
#endif
}

// Pipes and other append-only destinations cannot replace a published header.
// Give each physical range a permanent node and identifier. Capture and render
// use the same packed frames as replaceable files, without a replay journal.
void initializeFixedLayout(VCDTraceState &state) {
  auto &trace = *state.compact;
  auto count = state.variables.size();
  trace.fields.resize(count);
  trace.groups.resize(count);
  trace.nodes.resize(count);
  trace.published.spans.resize(count);
  trace.published.codes.resize(count);
  for (uint32_t i = 0; i < count; ++i) {
    const auto code = state.variables[i].code;
    trace.fields[i] = {i, CompactTrace::none, code};
    trace.groups[i].size = 1;
    trace.groups[i].node = i;
    trace.nodes[i] = {CompactTrace::none, i};
    trace.published.spans[i] = {i, i + 1};
    trace.published.codes[i] = packIdentifier(state.codeText[code]);
  }
}

bool fixIdentifiers(VCDTraceState &state) {
  if (!state.file || !state.compact->journal)
    return true;
  auto fixed = std::make_unique<CompactVCDState>();
  if (state.compact->samples && !publishSnapshot(state, true)) {
    state.outputStatus = TALOS_RT_IO_ERROR;
    closeFile(state);
    return false;
  }
  state.compact = std::move(fixed);
  if (state.planBuilt)
    initializeFixedLayout(state);
  finishLimit(state);
  return true;
}

bool finishCompacting(VCDTraceState &state) {
  bool ok = state.outputStatus == TALOS_RT_OK;
  if (state.file && state.compact && state.compact->journal && ok &&
      state.compact->samples &&
      state.compact->published.spans.size() != state.compact->nodes.size() &&
      !publishSnapshot(state, false)) {
    ok = false;
    state.outputStatus = TALOS_RT_IO_ERROR;
  }
  finishLimit(state);
  state.compact.reset();
  return ok && state.outputStatus == TALOS_RT_OK;
}

} // namespace

//===----------------------------------------------------------------------===//
// Context-facing entry points
//===----------------------------------------------------------------------===//

namespace {

VCDTraceState *traceState(talos_rt_context *context) {
  return context ? context->vcdState : nullptr;
}

talos_rt_status ensureState(talos_rt_context *context, VCDTraceState *&state) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  if (!context->vcdState) {
    context->vcdState = new (std::nothrow) VCDTraceState();
    if (!context->vcdState)
      return TALOS_RT_OUT_OF_MEMORY;
    // The traced shape is chosen at run time by $dumpvars, so the bound on
    // array expansion belongs here rather than in the compiled image.
    if (const char *limit = std::getenv("TALOS_RT_DUMP_MAX_ARRAY")) {
      char *end = nullptr;
      unsigned long long parsed = std::strtoull(limit, &end, 10);
      if (end && *end == '\0')
        context->vcdState->maxExpandedElements = parsed;
    }
  }
  state = context->vcdState;
  return TALOS_RT_OK;
}

// Something is selected for dumping: a generated periodic loop now ends each
// of its slots in the runtime (talos_rt_v1_scheduler_postponed_slot_aot).
// talos_rt_dump_slot_unlocked clears the bit once no dump file is open. A
// file alone ($dumpfile without $dumpvars) never dumps, so it arms nothing.
void armDumpSlotHook(talos_rt_context *context) {
  context->postponedSlotHooks |= kDumpSlotHook;
}

template <typename State>
talos_rt_status openFile(talos_rt_context *context, State &state,
                         const std::string &path) {
  bool closingPrevious = state.file != nullptr;
  closeFile(state);
  const char *output = path.c_str();
  if constexpr (std::is_same_v<State, VCDTraceState>) {
    state.compact.reset();
    if (closingPrevious && state.outputStatus != TALOS_RT_OK)
      return state.outputStatus;
    const char *overridePath = std::getenv("TALOS_RT_VCD_COMPACT_FILE");
    if (overridePath && *overridePath)
      output = overridePath;
  }
  state.file = std::fopen(output, "wb");
  // The writer buffers whole records itself (kFlushThreshold); a second stdio
  // buffer would only copy them again.
  if (state.file)
    std::setvbuf(state.file, nullptr, _IONBF, 0);
  talos_rt_close_on_exec(state.file);
  if (!state.file)
    return TALOS_RT_IO_ERROR;
  state.path = output;
  if constexpr (std::is_same_v<State, VCDTraceState>) {
    state.outputStatus = TALOS_RT_OK;
    state.compact = std::make_unique<CompactVCDState>();
#ifdef TALOS_POSIX_COMPACT_VCD
    struct stat named{}, opened{};
    if (!state.limitSet && !::lstat(output, &named) && S_ISREG(named.st_mode) &&
        named.st_nlink == 1 && !::fstat(fileno(state.file), &opened) &&
        named.st_dev == opened.st_dev && named.st_ino == opened.st_ino) {
      // A DPI client may chdir after $dumpfile. Keep replay anchored to the
      // file opened here, including when the HDL supplied a relative name.
      std::unique_ptr<char, decltype(&std::free)> absolute(
          ::realpath(output, nullptr), &std::free);
      TemporaryTraceFile journal;
      if (absolute && journal.open(absolute.get(), true)) {
        state.path = absolute.get();
        state.compact->journal.reset(std::exchange(journal.file, nullptr));
      }
    }
#endif
  }
  state.writtenBytes = 0;
  state.limitReached = false;
  state.buffer.clear();
  state.atLineStart = true;
  // A $dumpfile after selections (one that replaces a closed file) dumps them.
  if (!state.selections.empty())
    armDumpSlotHook(context);
  return TALOS_RT_OK;
}

template <typename State>
void writeHeader(talos_rt_context *context, State &state) {
  if (state.headerWritten)
    return;
  state.headerWritten = true;
  std::time_t now = std::time(nullptr);
  char stamp[64];
  stamp[0] = '\0';
  std::tm broken{};
#if defined(_WIN32)
  if (localtime_s(&broken, &now) == 0)
#else
  if (localtime_r(&now, &broken) != nullptr)
#endif
    std::strftime(stamp, sizeof(stamp), "%a %b %e %H:%M:%S %Y", &broken);
  append(state, "$date\n\t");
  append(state, stamp);
  append(state, "\n$end\n");
  append(state, "$version\n\tTalos\n$end\n");
  append(state, "$timescale\n\t");
  append(state, timescaleText(resolveTimescale(context, state)));
  append(state, "\n$end\n");
}

// Materialize the traced set, its VCD declarations, and the shadow planes.
talos_rt_status buildPlan(talos_rt_context *context, VCDTraceState &state) {
  if (state.planBuilt)
    return TALOS_RT_OK;
  const DesignDatabaseCache &database = context->designDatabase;
  if (!database.validated || !context->execution)
    return TALOS_RT_INVALID_DESIGN;

  std::unordered_set<uint64_t> selected;
  for (const TraceSelection &selection : state.selections) {
    uint64_t offset = 0;
    uint32_t kind = TALOS_RT_DESIGN_RECORD_INVALID;
    if (!resolveSelection(database, selection.scope, offset, kind)) {
      std::fprintf(stderr,
                   "talos: $dumpvars selection '%s' does not name a design "
                   "scope or variable; no waveform will be written\n",
                   selection.scope.c_str());
      return TALOS_RT_INVALID_HANDLE;
    }
    if (kind == TALOS_RT_DESIGN_RECORD_SCOPE)
      collectScope(database, offset, selection.levels, selected);
    else
      selected.insert(offset);
  }

  writeHeader(context, state);
  PlanBuilder builder{context, state, database, selected, {}, {}};
  builder.markLiveScopes();
  builder.emitDesign();
  append(state, "$enddefinitions $end\n");

  buildRanges(state, context->execution->state_bit_count, context->twoState());
  buildTraceWords(state);
  // A split tree over N ranges has at most 2N-1 nodes.
  if (state.compact->journal && state.variables.size() > UINT32_MAX / 2)
    state.compact = std::make_unique<CompactVCDState>();
  state.compact->collectingHeader = false;
  if (state.compact->journal)
    state.compact->initialize(state.variables);
  else
    initializeFixedLayout(state);
  state.planBuilt = true;
  state.pendingInitial = true;
  finishLimit(state);
  return state.outputStatus;
}

// Difference the traced windows against the shadow and emit what moved.
talos_rt_status emitSlot(talos_rt_context *context, VCDTraceState &state,
                         FrameKind kind = FrameKind::Changes) {
  if (!state.file || !state.planBuilt)
    return state.outputStatus;
  finishLimit(state);
  if (!state.file)
    return state.outputStatus;
  const uint8_t *valuePlane = nullptr;
  const uint8_t *unknownPlane = nullptr;
  talos_rt_status status = dumpPlanes(context, valuePlane, unknownPlane);
  if (status != TALOS_RT_OK)
    return status;

  uint64_t time = context->schedulerTime;

  auto planeWord = [&](const TraceVariable &v, uint64_t low,
                       bool unknown) -> uint64_t {
    const uint8_t *plane =
        unknown ? (v.fourState ? unknownPlane : nullptr) : valuePlane;
    return plane ? loadWord(plane, state.shadowValue.size(), v.sourceBit + low,
                            std::min<uint64_t>(64, v.width - low))
                 : 0;
  };
  auto recordWord = [&](const TraceVariable &v, uint64_t val, uint64_t unk) {
    state.compact->change(
        static_cast<uint32_t>(&v - state.variables.data()), val, unk,
        [&](const auto &g) { return val == g.value && unk == g.unknown; });
  };
  auto recordRange = [&](const TraceVariable &v) {
    if (v.width <= 64) {
      recordWord(v, planeWord(v, 0, false), planeWord(v, 0, true));
    } else {
      state.compact->change(
          static_cast<uint32_t>(&v - state.variables.data()), 0, 0,
          [&](const auto &g) {
            const auto &peer = state.variables[g.first];
            for (uint64_t i = 0; i < v.width; i += 64)
              if (planeWord(v, i, false) != planeWord(peer, i, false) ||
                  planeWord(v, i, true) != planeWord(peer, i, true))
                return false;
            return true;
          });
    }
  };
  if (kind == FrameKind::Changes && state.pendingInitial)
    kind = FrameKind::Initial;
  if (kind == FrameKind::Off) {
    for (uint32_t i = 0; i < state.variables.size(); ++i)
      if (!state.variables[i].isReal)
        state.compact->change(i, 0, 0, [](const auto &) { return true; });
  } else if (kind != FrameKind::Changes) {
    for (const TraceVariable &v : state.variables)
      recordRange(v);
    if (kind != FrameKind::All || !state.pendingInitial)
      updateShadow(state, valuePlane, unknownPlane);
  } else if (!state.enabled) {
    return TALOS_RT_OK;
  } else {
    for (size_t r = 0; r < state.ranges.size(); ++r) {
      const auto &range = state.ranges[r];
      size_t length = static_cast<size_t>(range.byteEnd - range.byteBegin);
      if (length == 0)
        continue;
      bool moved = std::memcmp(state.shadowValue.data() + range.byteBegin,
                               valuePlane + range.byteBegin, length) != 0 ||
                   (unknownPlane &&
                    std::memcmp(state.shadowUnknown.data() + range.byteBegin,
                                unknownPlane + range.byteBegin, length) != 0);
      if (!moved)
        continue;
      uint32_t index = range.firstVariable;
      for (uint32_t w = state.firstWord[r]; w < state.firstWord[r + 1]; ++w) {
        const auto &word = state.words[w];
        if (word.byte == UINT64_MAX) {
          const auto &v = state.variables[index++];
          if (!bitRangeEqual(state.shadowValue.data(), valuePlane, v.sourceBit,
                             v.width) ||
              (v.fourState &&
               !bitRangeEqual(state.shadowUnknown.data(), unknownPlane,
                              v.sourceBit, v.width))) {
            recordRange(v);
          }
          continue;
        }
        auto load = [&](const uint8_t *plane) {
          uint64_t bits;
          std::memcpy(&bits, plane + word.byte, sizeof(bits));
          return bits;
        };
        uint64_t value = load(valuePlane);
        uint64_t delta = value ^ load(state.shadowValue.data());
        uint64_t unknown = 0;
        if (word.fourState) {
          unknown = load(unknownPlane);
          delta |= unknown ^ load(state.shadowUnknown.data());
        }
        if (delta) {
          for (; index != word.end; ++index) {
            uint64_t mask = state.fieldMasks[index];
            if (!(delta & mask))
              continue;
            const auto &v = state.variables[index];
            unsigned shift = static_cast<unsigned>(v.sourceBit - 8 * word.byte);
            recordWord(v, (value & mask) >> shift, (unknown & mask) >> shift);
          }
        }
        index = word.end;
      }
      std::memcpy(state.shadowValue.data() + range.byteBegin,
                  valuePlane + range.byteBegin, length);
      if (unknownPlane)
        std::memcpy(state.shadowUnknown.data() + range.byteBegin,
                    unknownPlane + range.byteBegin, length);
    }
  }
  auto &trace = *state.compact;
  if (trace.touched.empty() && trace.changed.empty() &&
      kind == FrameKind::Changes)
    return TALOS_RT_OK;
  size_t oldNodes = trace.nodes.size();
  trace.refine(
      [&](uint32_t code) {
        const auto &v = state.variables[code];
        std::string key;
        for (uint64_t low = 0; low < v.width; low += 64) {
          uint64_t val = planeWord(v, low, false);
          uint64_t unk = planeWord(v, low, true);
          key.append(reinterpret_cast<const char *>(&val), sizeof(val));
          key.append(reinterpret_cast<const char *>(&unk), sizeof(unk));
        }
        return key;
      },
      [&](uint32_t code, auto &group) {
        const auto &v = state.variables[code];
        if (v.width <= 64) {
          group.value = planeWord(v, 0, false);
          group.unknown = planeWord(v, 0, true);
        }
      });
  if (state.outputStatus != TALOS_RT_OK)
    return state.outputStatus;
  bool ok = captureFrame(state, valuePlane, unknownPlane, time, kind);
  trace.changed.clear();
  const bool split = oldNodes != trace.nodes.size();
  const bool stableBeforeSplit = trace.samples - trace.lastSplit >= 128;
  if (split)
    trace.lastSplit = trace.samples;
  if (ok && trace.published.spans.size() == trace.nodes.size() &&
      (!trace.journal || trace.samples > 1)) {
    size_t prior = state.buffer.size();
    uint64_t previousTime = state.emittedTime;
    ok = renderFrame(state, trace.published, trace.frame.data() + 10,
                     trace.frame.size() - 10, state.buffer, previousTime,
                     !state.haveEmittedTime);
    if (state.limitSet &&
        state.buffer.size() - prior > state.limitBytes - state.writtenBytes) {
      truncateAtRecordBoundary(
          state.buffer,
          prior + static_cast<size_t>(state.limitBytes - state.writtenBytes));
      state.limitReached = true;
    }
    state.writtenBytes += state.buffer.size() - prior;
    trace.publishedSamples = trace.samples;
    if (!state.haveEmittedTime || state.buffer.size() >= kFlushThreshold ||
        trace.samples % 128 == 0)
      flushBuffer(state);
  } else if (ok &&
             (trace.samples == 1 || state.limitSet ||
              (split && stableBeforeSplit && trace.bytes < 1024 * 1024) ||
              (trace.bytes < 1024 * 1024 &&
               trace.bytes - trace.checkpointBytes >= kFlushThreshold) ||
              (trace.samples % 128 == 0 &&
               std::chrono::steady_clock::now() >= trace.nextCheckpoint))) {
    ok = publishSnapshot(state, false);
    if (!ok && trace.samples == 1 && state.outputStatus == TALOS_RT_OK) {
      // No shared ID has been published yet. The existing header already
      // has physical IDs, so the complete first checkpoint can be retried
      // against that descriptor if the filesystem disallows replacement.
      state.compact = std::make_unique<CompactVCDState>();
      initializeFixedLayout(state);
      return emitSlot(context, state, kind);
    }
  }
  state.haveEmittedTime = true;
  state.emittedTime = time;
  if (kind == FrameKind::Initial)
    state.pendingInitial = false;
  if (!ok || state.outputStatus != TALOS_RT_OK) {
    state.outputStatus = TALOS_RT_IO_ERROR;
    closeFile(state);
    return TALOS_RT_IO_ERROR;
  }
  finishLimit(state);
  return state.outputStatus;
}

char evcdValueChar(const TraceVariable &variable, bool value, bool unknown) {
  bool input = (variable.portCaps & TALOS_RT_DESIGN_CAP_PORT_INPUT) != 0;
  bool output = (variable.portCaps & TALOS_RT_DESIGN_CAP_PORT_OUTPUT) != 0;
  if (input && !output) {
    if (unknown)
      return value ? 'Z' : 'N';
    return value ? 'U' : 'D';
  }
  if (output && !input) {
    if (unknown)
      return value ? 'T' : 'X';
    return value ? 'H' : 'L';
  }
  if (unknown)
    return value ? 'F' : '?';
  return value ? '1' : '0';
}

bool resolveEVCDConflict(
    const std::vector<TraceVariable::BoundaryDriver> &drivers,
    const uint8_t *valuePlane, const uint8_t *unknownPlane, char &state,
    int &strength0, int &strength1);

void emitEVCDValue(EVCDSession &state, const TraceVariable &variable,
                   const uint8_t *valuePlane, const uint8_t *unknownPlane) {
  std::string states, zeroStrengths, oneStrengths;
  for (uint64_t bit = variable.width; bit != 0; --bit) {
    bool value = bitAt(valuePlane, variable.sourceBit + bit - 1);
    bool unknown =
        variable.fourState && bitAt(unknownPlane, variable.sourceBit + bit - 1);
    char character = evcdValueChar(variable, value, unknown);
    char strength0 = unknown && value ? '0' : value ? '0' : '6';
    char strength1 = unknown ? (value ? '0' : '6') : (value ? '6' : '0');
    // IEEE 1800-2023 21.7.4.3.2: competing drivers on both sides of the
    // dumped instance take the conflict states and the winning strength.
    if (!variable.boundaryDrivers.empty() &&
        !variable.boundaryDrivers[bit - 1].empty()) {
      int resolved0 = 0, resolved1 = 0;
      if (resolveEVCDConflict(variable.boundaryDrivers[bit - 1], valuePlane,
                              unknownPlane, character, resolved0,
                              resolved1)) {
        strength0 = static_cast<char>('0' + resolved0);
        strength1 = static_cast<char>('0' + resolved1);
      }
    }
    states.push_back(character);
    zeroStrengths.push_back(strength0);
    oneStrengths.push_back(strength1);
  }
  state.scratch.clear();
  state.scratch.push_back('p');
  state.scratch.append(states);
  state.scratch.push_back(' ');
  state.scratch.append(zeroStrengths);
  state.scratch.push_back(' ');
  state.scratch.append(oneStrengths);
  state.scratch.push_back(' ');
  state.scratch.append(state.codeText[variable.code]);
  state.scratch.push_back('\n');
  append(state, state.scratch);
}

// Driver records by state bit, with the scope that declares each.
using DriverScopeMap = std::map<uint64_t, std::pair<uint64_t, uint64_t>>;

void collectDriverScopes(const DesignDatabaseCache &database, uint64_t scope,
                         DriverScopeMap &result) {
  const uint8_t *scopeRecord = database.data + scope;
  for (uint64_t child = firstChildOffset(scopeRecord); child != 0;) {
    const uint8_t *record;
    uint32_t childKind;
    if (!getRecord(database, child, record, childKind))
      return;
    if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE)
      collectDriverScopes(database, child, result);
    else if (childKind == TALOS_RT_DESIGN_RECORD_DRIVER)
      result[objectStateBit(record)] = {objectBitWidth(record), scope};
    child = nextSiblingOffset(record, childKind);
  }
}

// IEEE 1800-2023 21.7.4.3.2 compares the drivers of a port's net that lie
// inside the dumped instance (the output) with those outside it (the input).
void classifyBoundaryDrivers(talos_rt_context *context,
                             const DesignDatabaseCache &database,
                             const DriverScopeMap &driverScopes,
                             uint64_t dumpedScope, TraceVariable &variable) {
  auto inside = [&](uint64_t driverScope) {
    for (uint64_t scope = driverScope; scope != 0;) {
      if (scope == dumpedScope)
        return true;
      const uint8_t *record;
      uint32_t kind;
      if (!getRecord(database, scope, record, kind) ||
          kind != TALOS_RT_DESIGN_RECORD_SCOPE)
        return false;
      scope = parentOffset(record);
    }
    return false;
  };
  variable.boundaryDrivers.resize(variable.width);
  bool any = false;
  std::vector<talos_rt_net_driver_bit> drivers;
  for (uint64_t bit = 0; bit != variable.width; ++bit) {
    if (talos_rt_design_net_drivers(context, variable.sourceBit + bit,
                                    drivers) != TALOS_RT_OK)
      continue;
    bool hasInside = false, hasOutside = false;
    std::vector<TraceVariable::BoundaryDriver> classified;
    for (const talos_rt_net_driver_bit &driver : drivers) {
      auto found = driverScopes.upper_bound(driver.valueOffset);
      if (found == driverScopes.begin())
        continue;
      --found;
      if (driver.valueOffset - found->first >= found->second.first)
        continue;
      bool isInside = inside(found->second.second);
      (isInside ? hasInside : hasOutside) = true;
      classified.push_back({driver.valueOffset, driver.strength0,
                            driver.strength1, isInside});
    }
    if (hasInside && hasOutside) {
      variable.boundaryDrivers[bit] = std::move(classified);
      any = true;
    }
  }
  if (!any)
    variable.boundaryDrivers.clear();
}

// IEEE 1800-2023 21.7.4.3.2: resolve competing input and output drivers of
// one port bit. Returns false when the bit is not a conflict the clause
// describes, leaving the direction-based character in force.
bool resolveEVCDConflict(const std::vector<TraceVariable::BoundaryDriver> &drivers,
                         const uint8_t *valuePlane, const uint8_t *unknownPlane,
                         char &state, int &strength0, int &strength1) {
  struct Side {
    int level = 0;
    int value = 0;
    bool active = false;
  } input, output;
  for (const TraceVariable::BoundaryDriver &driver : drivers) {
    if (unknownPlane && bitAt(unknownPlane, driver.valueOffset))
      return false;
    int value = bitAt(valuePlane, driver.valueOffset) ? 1 : 0;
    int level = value ? driver.strength1 : driver.strength0;
    // The input drives from outside the instance, the output from inside.
    Side &side = driver.inside ? output : input;
    if (level == 0)
      continue;
    if (!side.active || level > side.level) {
      side = {level, value, true};
    } else if (level == side.level && value != side.value) {
      return false;
    }
  }
  if (!input.active || !output.active)
    return false;
  auto strong = [](int level) { return level >= 5; };
  int level;
  if (strong(input.level) && !strong(output.level)) {
    // Different strength ranges pick the state whatever the two values are.
    state = input.value ? 'u' : 'd';
    level = input.level;
  } else if (!strong(input.level) && strong(output.level)) {
    state = output.value ? 'h' : 'l';
    level = output.level;
  } else if (input.value == output.value) {
    // Same value with the same strength range: a conflict resolved to 0/1 at
    // the stronger of the two strengths.
    state = input.value ? '1' : '0';
    level = std::max(input.level, output.level);
  } else {
    return false;
  }
  int value = (state == '1' || state == 'u' || state == 'h') ? 1 : 0;
  strength0 = value ? 0 : level;
  strength1 = value ? level : 0;
  return true;
}

void emitEVCDOff(EVCDSession &state, const TraceVariable &variable) {
  state.scratch.clear();
  state.scratch.push_back('p');
  state.scratch.append(static_cast<size_t>(variable.width), 'f');
  state.scratch.push_back(' ');
  state.scratch.append(static_cast<size_t>(variable.width), '0');
  state.scratch.push_back(' ');
  state.scratch.append(static_cast<size_t>(variable.width), '0');
  state.scratch.push_back(' ');
  state.scratch.append(state.codeText[variable.code]);
  state.scratch.push_back('\n');
  append(state, state.scratch);
}

talos_rt_status buildEVCDPlan(talos_rt_context *context, EVCDSession &state) {
  if (state.planBuilt)
    return TALOS_RT_OK;
  const DesignDatabaseCache &database = context->designDatabase;
  if (!database.validated || !context->execution)
    return TALOS_RT_INVALID_DESIGN;

  std::unordered_set<uint64_t> selectedScopes;
  std::unordered_set<uint64_t> liveScopes;
  for (const std::string &selection : state.selections) {
    uint64_t scope = 0;
    uint32_t kind = TALOS_RT_DESIGN_RECORD_INVALID;
    if (!resolveSelection(database, selection, scope, kind) ||
        kind != TALOS_RT_DESIGN_RECORD_SCOPE)
      return TALOS_RT_INVALID_HANDLE;
    if (!selectedScopes.insert(scope).second)
      continue;
    for (uint64_t ancestor = scope; ancestor != 0;) {
      if (!liveScopes.insert(ancestor).second)
        break;
      const uint8_t *record;
      uint32_t ancestorKind;
      if (!getRecord(database, ancestor, record, ancestorKind) ||
          ancestorKind != TALOS_RT_DESIGN_RECORD_SCOPE)
        return TALOS_RT_INVALID_DESIGN;
      ancestor = parentOffset(record);
    }
  }

  writeHeader(context, state);
  uint32_t nextCode = 0;
  DriverScopeMap driverScopes;
  collectDriverScopes(database, database.root, driverScopes);
  std::function<talos_rt_status(uint64_t, std::string_view)> emitScope =
      [&](uint64_t scope, std::string_view parentName) -> talos_rt_status {
    const uint8_t *scopeRecord = database.data + scope;
    std::string_view scopeName;
    if (!getString(database, nameOffset(scopeRecord), scopeName))
      return TALOS_RT_INVALID_DESIGN;
    append(state, "$scope module ");
    append(state, leafName(scopeName, parentName));
    append(state, " $end\n");
    std::vector<uint64_t> ports;
    for (uint64_t child = firstChildOffset(scopeRecord); child != 0;) {
      const uint8_t *record;
      uint32_t childKind;
      if (!getRecord(database, child, record, childKind))
        return TALOS_RT_INVALID_DESIGN;
      uint32_t caps = read32(record + 4);
      if (selectedScopes.count(scope) != 0 &&
          (childKind == TALOS_RT_DESIGN_RECORD_PORT ||
           (caps & (TALOS_RT_DESIGN_CAP_PORT_INPUT |
                    TALOS_RT_DESIGN_CAP_PORT_OUTPUT)) != 0))
        ports.push_back(child);
      child = nextSiblingOffset(record, childKind);
    }
    std::sort(ports.begin(), ports.end(), [&](uint64_t lhs, uint64_t rhs) {
      uint32_t lhsCaps = read32(database.data + lhs + 4);
      uint32_t rhsCaps = read32(database.data + rhs + 4);
      uint32_t lhsOrdinal = (lhsCaps & TALOS_RT_DESIGN_CAP_PORT_ORDINAL_MASK) >>
                            TALOS_RT_DESIGN_CAP_PORT_ORDINAL_SHIFT;
      uint32_t rhsOrdinal = (rhsCaps & TALOS_RT_DESIGN_CAP_PORT_ORDINAL_MASK) >>
                            TALOS_RT_DESIGN_CAP_PORT_ORDINAL_SHIFT;
      return std::tie(lhsOrdinal, lhs) < std::tie(rhsOrdinal, rhs);
    });
    for (uint64_t offset : ports) {
      const uint8_t *record = database.data + offset;
      uint64_t width = objectBitWidth(record);
      if (width == 0)
        continue;
      std::string_view name;
      if (!getString(database, nameOffset(record), name))
        return TALOS_RT_INVALID_DESIGN;
      TraceVariable variable;
      variable.sourceBit = objectStateBit(record);
      variable.width = width;
      variable.code = nextCode++;
      variable.fourState = typeFourState(database, objectTypeOffset(record));
      variable.portCaps = read32(record + 4);
      classifyBoundaryDrivers(context, database, driverScopes, scope, variable);
      state.variables.push_back(std::move(variable));
      state.codeText.push_back("<" + std::to_string(state.variables.back().code));
      append(state, "$var port ");
      if (width == 1) {
        append(state, "1");
      } else {
        append(state, "[");
        appendSigned(state, readI64(record + 64));
        append(state, ":");
        appendSigned(state, readI64(record + 72));
        append(state, "]");
      }
      append(state, " ");
      append(state, state.codeText.back());
      append(state, " ");
      append(state, leafName(name, scopeName));
      append(state, " $end\n");
    }
    for (uint64_t child = firstChildOffset(scopeRecord); child != 0;) {
      const uint8_t *record;
      uint32_t childKind;
      if (!getRecord(database, child, record, childKind))
        return TALOS_RT_INVALID_DESIGN;
      if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE &&
          liveScopes.count(child) != 0) {
        talos_rt_status status = emitScope(child, scopeName);
        if (status != TALOS_RT_OK)
          return status;
      }
      child = nextSiblingOffset(record, childKind);
    }
    append(state, "$upscope $end\n");
    return TALOS_RT_OK;
  };
  const uint8_t *rootRecord;
  uint32_t rootKind;
  std::string_view rootName;
  if (!getRecord(database, database.root, rootRecord, rootKind) ||
      rootKind != TALOS_RT_DESIGN_RECORD_SCOPE ||
      !getString(database, nameOffset(rootRecord), rootName))
    return TALOS_RT_INVALID_DESIGN;
  if (rootName != "$root" && rootName != "\\$root ") {
    talos_rt_status status = emitScope(database.root, {});
    if (status != TALOS_RT_OK)
      return status;
  } else {
    for (uint64_t child = firstChildOffset(rootRecord); child != 0;) {
      const uint8_t *record;
      uint32_t childKind;
      if (!getRecord(database, child, record, childKind))
        return TALOS_RT_INVALID_DESIGN;
      if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE &&
          liveScopes.count(child) != 0) {
        talos_rt_status status = emitScope(child, rootName);
        if (status != TALOS_RT_OK)
          return status;
      }
      child = nextSiblingOffset(record, childKind);
    }
  }
  append(state, "$enddefinitions $end\n");
  buildRanges(state, context->execution->state_bit_count, context->twoState());
  state.planBuilt = true;
  state.pendingInitial = true;
  return TALOS_RT_OK;
}

// IEEE 1800-2023 21.7.3.6.1: $vcdclose records the final simulation time when
// the file closes. Like the 21.7.3.4 comment below, it is outside the limited
// waveform payload, so it uses the raw path the limiter cannot suppress.
void closeEVCDFile(EVCDSession &state, uint64_t time) {
  if (!state.file)
    return;
  std::string close = "$vcdclose #" + std::to_string(time) + " $end\n";
  appendRaw(state, close.data(), close.size());
  closeFile(state);
}

// IEEE 1800-2023 21.7.3.4: reaching the size limit stops dumping and inserts a
// comment recording that the limit was attained.
void finishEVCDLimit(EVCDSession &state, uint64_t time) {
  if (!state.file || !state.limitReached)
    return;
  std::string comment = std::string(state.atLineStart ? "" : "\n") +
                        "$comment dumpports limit of " +
                        std::to_string(state.limitBytes) +
                        " bytes reached $end\n";
  appendRaw(state, comment.data(), comment.size());
  closeEVCDFile(state, time);
}

talos_rt_status emitEVCDSlot(talos_rt_context *context, EVCDSession &state,
                             bool forceAll, std::string_view checkpoint = {}) {
  if (state.limitReached)
    finishEVCDLimit(state, context->schedulerTime);
  if (!state.file || state.limitReached || !state.planBuilt)
    return TALOS_RT_OK;
  const uint8_t *valuePlane = nullptr;
  const uint8_t *unknownPlane = nullptr;
  talos_rt_status status = dumpPlanes(context, valuePlane, unknownPlane);
  if (status != TALOS_RT_OK)
    return status;
  if (state.pendingInitial) {
    emitTime(state, context->schedulerTime);
    append(state, "$dumpports\n");
    for (const TraceVariable &variable : state.variables)
      emitEVCDValue(state, variable, valuePlane, unknownPlane);
    append(state, "$end\n");
    state.pendingInitial = false;
    for (const TraceRange &range : state.ranges) {
      size_t length = static_cast<size_t>(range.byteEnd - range.byteBegin);
      std::memcpy(state.shadowValue.data() + range.byteBegin,
                  valuePlane + range.byteBegin, length);
      if (unknownPlane)
        std::memcpy(state.shadowUnknown.data() + range.byteBegin,
                    unknownPlane + range.byteBegin, length);
    }
    return TALOS_RT_OK;
  } else if (!checkpoint.empty()) {
    emitTime(state, context->schedulerTime);
    appendRecord(state, {checkpoint, "\n"});
    for (const TraceVariable &variable : state.variables)
      emitEVCDValue(state, variable, valuePlane, unknownPlane);
    append(state, "$end\n");
    for (const TraceRange &range : state.ranges) {
      size_t length = static_cast<size_t>(range.byteEnd - range.byteBegin);
      std::memcpy(state.shadowValue.data() + range.byteBegin,
                  valuePlane + range.byteBegin, length);
      if (unknownPlane)
        std::memcpy(state.shadowUnknown.data() + range.byteBegin,
                    unknownPlane + range.byteBegin, length);
    }
    return TALOS_RT_OK;
  }
  if (!state.enabled)
    return TALOS_RT_OK;
  for (const TraceRange &range : state.ranges) {
    size_t length = static_cast<size_t>(range.byteEnd - range.byteBegin);
    bool moved = forceAll ||
                 std::memcmp(state.shadowValue.data() + range.byteBegin,
                             valuePlane + range.byteBegin, length) != 0 ||
                 (unknownPlane &&
                  std::memcmp(state.shadowUnknown.data() + range.byteBegin,
                              unknownPlane + range.byteBegin, length) != 0);
    if (moved)
      for (uint32_t index = range.firstVariable; index != range.lastVariable;
           ++index) {
        const TraceVariable &variable = state.variables[index];
        if (forceAll ||
            !bitRangeEqual(state.shadowValue.data(), valuePlane,
                           variable.sourceBit, variable.width) ||
            (variable.fourState &&
             !bitRangeEqual(state.shadowUnknown.data(), unknownPlane,
                            variable.sourceBit, variable.width))) {
          emitTime(state, context->schedulerTime);
          emitEVCDValue(state, variable, valuePlane, unknownPlane);
        }
      }
    if (moved) {
      std::memcpy(state.shadowValue.data() + range.byteBegin,
                  valuePlane + range.byteBegin, length);
      if (unknownPlane)
        std::memcpy(state.shadowUnknown.data() + range.byteBegin,
                    unknownPlane + range.byteBegin, length);
    }
  }
  finishEVCDLimit(state, context->schedulerTime);
  return TALOS_RT_OK;
}

talos_rt_status prepareEVCDSession(talos_rt_context *context,
                                   EVCDSession &session) {
  if (session.planBuilt)
    return TALOS_RT_OK;
  if (session.planFailed || session.selections.empty())
    return TALOS_RT_OK;
  talos_rt_status status = buildEVCDPlan(context, session);
  if (status != TALOS_RT_OK) {
    session.planFailed = true;
    closeFile(session);
  }
  return status;
}

} // namespace

talos_rt_status talos_rt_dump_slot_unlocked(talos_rt_context *context) {
  VCDTraceState *state = traceState(context);
  if (state && state->file) {
    // The plan is materialized at the end of the slot that made the first
    // selection, so every $dumpvars issued during that slot is accounted for
    // before the header is closed.
    if (!state->planBuilt) {
      if (!state->planFailed && !state->selections.empty()) {
        talos_rt_status status = buildPlan(context, *state);
        if (status != TALOS_RT_OK) {
          state->planFailed = true;
          closeFile(*state);
          return status;
        }
      }
    }
    if (state->planBuilt) {
      talos_rt_status status = emitSlot(context, *state);
      if (status != TALOS_RT_OK)
        return status;
    }
  }
  if (context && context->evcdState)
    for (const std::unique_ptr<EVCDSession> &session :
         context->evcdState->sessions) {
      talos_rt_status status = prepareEVCDSession(context, *session);
      if (status != TALOS_RT_OK)
        return status;
      status = emitEVCDSlot(context, *session, false);
      if (status != TALOS_RT_OK)
        return status;
    }
  if (context && (context->postponedSlotHooks & kDumpSlotHook) &&
      !talos_rt_dump_active_unlocked(context)) {
    context->postponedSlotHooks &= ~kDumpSlotHook;
    context->postponedHooksDisarmed = true;
  }
  return TALOS_RT_OK;
}

uint64_t talos_rt_dump_traced_range_count(const talos_rt_context *context) {
  if (!context || !context->vcdState)
    return 0;
  return context->vcdState->variables.size();
}

bool talos_rt_dump_active_unlocked(const talos_rt_context *context) {
  if (!context)
    return false;
  if (context->vcdState && context->vcdState->file)
    return true;
  if (context->evcdState)
    for (const std::unique_ptr<EVCDSession> &session :
         context->evcdState->sessions)
      if (session->file)
        return true;
  return false;
}

std::string talos_rt_interactive_first_scope(talos_rt_context *context) {
  const DesignDatabaseCache &database = context->designDatabase;
  const uint8_t *root;
  uint32_t kind;
  if (!database.validated || !getRecord(database, database.root, root, kind))
    return {};
  for (uint64_t child = firstChildOffset(root); child != 0;) {
    const uint8_t *record;
    uint32_t childKind;
    if (!getRecord(database, child, record, childKind))
      return {};
    std::string_view name;
    if (childKind == TALOS_RT_DESIGN_RECORD_SCOPE &&
        getString(database, nameOffset(record), name))
      return std::string(name);
    child = nextSiblingOffset(record, childKind);
  }
  return {};
}

talos_rt_status talos_rt_interactive_scope_objects(
    talos_rt_context *context, const std::string &scope,
    std::vector<std::string> &paths) {
  const DesignDatabaseCache &database = context->designDatabase;
  uint64_t offset;
  uint32_t kind;
  const uint8_t *record;
  if (!database.validated || !resolveSelection(database, scope, offset, kind) ||
      kind != TALOS_RT_DESIGN_RECORD_SCOPE ||
      !getRecord(database, offset, record, kind))
    return TALOS_RT_OK;
  for (uint64_t child = firstChildOffset(record); child != 0;) {
    const uint8_t *childRecord;
    uint32_t childKind;
    if (!getRecord(database, child, childRecord, childKind))
      break;
    std::string_view name;
    if (traceableObject(database, childKind, childRecord) &&
        getString(database, nameOffset(childRecord), name))
      paths.emplace_back(name);
    child = nextSiblingOffset(childRecord, childKind);
  }
  return TALOS_RT_OK;
}

talos_rt_status
talos_rt_interactive_show_vars(talos_rt_context *context,
                               const std::vector<std::string> &paths) {
  const DesignDatabaseCache &database = context->designDatabase;
  if (!database.validated)
    return TALOS_RT_OK;
  const uint8_t *valuePlane = nullptr;
  const uint8_t *unknownPlane = nullptr;
  if (talos_rt_status status =
          dumpPlanes(context, valuePlane, unknownPlane);
      status != TALOS_RT_OK)
    return status;
  // Generated code without a schedule plan owns its planes, and they alone hold
  // what it initialized and wrote since the last commit point.
  if (!context->nativeSchedulePlan && context->nativeStateValue &&
      (context->execution->flags & TALOS_RT_EXECUTION_HAS_BYTECODE) == 0) {
    valuePlane = context->nativeStateValue;
    unknownPlane = context->nativeStateUnknown;
  }
  // IEEE 1800-2023 D.13: status information for each named reg and net, in the
  // whole vector even when only a select of it is named.
  std::string listing;
  for (const std::string &path : paths) {
    uint64_t offset;
    uint32_t kind;
    const uint8_t *record;
    if (!resolveSelection(database, path, offset, kind) ||
        !getRecord(database, offset, record, kind) ||
        !traceableObject(database, kind, record))
      continue;
    uint64_t width = objectBitWidth(record);
    uint64_t start = objectStateBit(record);
    listing += path;
    listing += kind == TALOS_RT_DESIGN_RECORD_NET ? " net " : " reg ";
    listing += "[" + std::to_string(width - 1) + ":0] = " +
               std::to_string(width) + "'b";
    for (uint64_t bit = width; bit != 0; --bit) {
      bool value = bitAt(valuePlane, start + bit - 1);
      bool unknown = unknownPlane && bitAt(unknownPlane, start + bit - 1);
      listing.push_back(unknown ? (value ? 'z' : 'x') : (value ? '1' : '0'));
    }
    listing.push_back('\n');
  }
  return writeUnlocked(context, 1, listing.data(), listing.size(), nullptr);
}

void talos_rt_dump_destroy(talos_rt_context *context) noexcept {
  if (!context)
    return;
  if (context->vcdState) {
    VCDTraceState *state = context->vcdState;
    bool wasOpen = state->file != nullptr;
    TALOS_RT_TRY {
      if (state->file && !state->planBuilt && !state->planFailed &&
          !state->selections.empty())
        (void)buildPlan(context, *state);
      if (state->file && state->planBuilt)
        (void)emitSlot(context, *state);
      finishCompacting(*state);
    }
    TALOS_RT_CATCH_ALL {
      // Teardown must not propagate; the file is still closed below.
    }
    closeFile(*state);
    if (wasOpen && state->outputStatus == TALOS_RT_IO_ERROR)
      std::fprintf(stderr, "talos: failed to finish VCD file '%s'\n",
                   state->path.c_str());
    delete state;
    context->vcdState = nullptr;
  }
  if (context->evcdState) {
    for (const std::unique_ptr<EVCDSession> &session :
         context->evcdState->sessions) {
      TALOS_RT_TRY {
        if (session->file && !session->planBuilt)
          (void)prepareEVCDSession(context, *session);
        if (session->file && session->planBuilt)
          (void)emitEVCDSlot(context, *session, false);
      }
      TALOS_RT_CATCH_ALL {}
      closeEVCDFile(*session, context->schedulerTime);
    }
    delete context->evcdState;
    context->evcdState = nullptr;
  }
  context->postponedSlotHooks &= ~kDumpSlotHook;
}

extern "C" talos_rt_status talos_rt_v1_dump_open(talos_rt_context *context,
                                                 const uint8_t *path,
                                                 uint64_t pathSize) {
  if (!context || (!path && pathSize != 0) || pathSize == 0)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = nullptr;
    talos_rt_status status = ensureState(context, state);
    if (status != TALOS_RT_OK)
      return status;
    // IEEE 1800 leaves a second $dumpfile after dumping has started
    // unspecified; reject it rather than silently splitting the waveform.
    if (state->planBuilt)
      return TALOS_RT_INVALID_LIFECYCLE;
    status = openFile(context, *state,
                      std::string(reinterpret_cast<const char *>(path),
                                  static_cast<size_t>(pathSize)));
    if (status != TALOS_RT_OK)
      return status;
    finishLimit(*state);
    return state->outputStatus;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

extern "C" talos_rt_status
talos_rt_v1_dump_open_string(talos_rt_context *context,
                             talos_rt_string_v1 path) {
  char scratch[8] = {};
  const char *bytes = nullptr;
  uint64_t size = 0;
  talos_rt_status status =
      talos_rt_v1_string_view(path, scratch, &bytes, &size);
  return status == TALOS_RT_OK
             ? talos_rt_v1_dump_open(
                   context, reinterpret_cast<const uint8_t *>(bytes), size)
             : status;
}

extern "C" talos_rt_status talos_rt_v1_dump_timescale(talos_rt_context *context,
                                                      int32_t exponent) {
  if (!context || exponent > 2 || exponent < -15)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = nullptr;
    talos_rt_status status = ensureState(context, state);
    if (status != TALOS_RT_OK)
      return status;
    // Lowered dump tasks carry the design timescale at each call site. Once
    // the header exists, repeating that same annotation is idempotent; only a
    // conflicting late change is invalid.
    if (state->headerWritten)
      return state->timescaleSet && state->timescaleExponent == exponent
                 ? TALOS_RT_OK
                 : TALOS_RT_INVALID_LIFECYCLE;
    state->timescaleSet = true;
    state->timescaleExponent = exponent;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_ARGUMENT; }
}

extern "C" talos_rt_status talos_rt_v1_dump_vars(talos_rt_context *context,
                                                 uint64_t levels,
                                                 const uint8_t *scope,
                                                 uint64_t scopeSize) {
  if (!context || (!scope && scopeSize != 0))
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = nullptr;
    talos_rt_status status = ensureState(context, state);
    if (status != TALOS_RT_OK)
      return status;
    if (!context->designDatabase.validated)
      return TALOS_RT_INVALID_DESIGN;
    // Every selection must be registered before the plan is materialized,
    // because a VCD header is complete before the first value record.
    if (state->planBuilt)
      return TALOS_RT_OK;
    if (!state->file && !state->limitReached) {
      status = openFile(context, *state, "dump.vcd");
      if (status != TALOS_RT_OK)
        return status;
      finishLimit(*state);
      if (state->outputStatus != TALOS_RT_OK)
        return state->outputStatus;
    }
    TraceSelection selection;
    selection.levels = levels;
    if (scopeSize != 0)
      selection.scope.assign(reinterpret_cast<const char *>(scope),
                             static_cast<size_t>(scopeSize));
    state->selections.push_back(std::move(selection));
    // A closed file ($dumplimit reached) dumps nothing; a later $dumpfile
    // arms the hook for the pending selections (openFile).
    if (state->file)
      armDumpSlotHook(context);
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_ARGUMENT; }
}

// The compiler supplies distinct physical storage for each name. Only a
// Postponed dump uses the proven source range (1800-2023 21.7.2.3); VPI
// reads and value-change subscriptions keep the declaration's real offset.
extern "C" talos_rt_status
talos_rt_v1_dump_bind_aliases(talos_rt_context *context, const uint64_t *rows,
                              uint64_t count) {
  if (!context || !context->execution || !rows ||
      count > SIZE_MAX / (3 * sizeof(uint64_t)))
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  ContextMutexLock lock(context);
  if (context->vcdState)
    return TALOS_RT_INVALID_LIFECYCLE;
  uint64_t bits = context->execution->state_bit_count;
  uint64_t end = 0;
  for (uint64_t i = 0; i < count; ++i) {
    const uint64_t dst = rows[3 * i], src = rows[3 * i + 1],
                   width = rows[3 * i + 2];
    if (dst < end || !width || dst > bits || width > bits - dst || src > bits ||
        width > bits - src)
      return TALOS_RT_INVALID_DESIGN;
    end = dst + width;
  }
  context->vcdAliasRows = rows;
  context->vcdAliasCount = count;
  return TALOS_RT_OK;
}

extern "C" talos_rt_status talos_rt_v1_dump_all(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = traceState(context);
    if (!state || !state->file ||
        (!state->planBuilt && state->selections.empty()))
      return state ? state->outputStatus : TALOS_RT_OK;
    talos_rt_status status = buildPlan(context, *state);
    if (status != TALOS_RT_OK)
      return status;
    return emitSlot(context, *state, FrameKind::All);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

extern "C" talos_rt_status talos_rt_v1_dump_control(talos_rt_context *context,
                                                    uint32_t enabled) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = traceState(context);
    if (!state || !state->file ||
        (!state->planBuilt && state->selections.empty()))
      return state ? state->outputStatus : TALOS_RT_OK;
    talos_rt_status status = buildPlan(context, *state);
    if (status != TALOS_RT_OK)
      return status;
    bool wanted = enabled != 0;
    if (wanted == state->enabled)
      return TALOS_RT_OK;
    // Settle the slot under the previous mode before switching.
    status = emitSlot(context, *state);
    if (status != TALOS_RT_OK)
      return status;
    if (!state->file)
      return TALOS_RT_OK;
    state->enabled = wanted;
    return emitSlot(context, *state, wanted ? FrameKind::On : FrameKind::Off);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

extern "C" talos_rt_status talos_rt_v1_dump_limit(talos_rt_context *context,
                                                  uint64_t bytes) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = nullptr;
    talos_rt_status status = ensureState(context, state);
    if (status != TALOS_RT_OK)
      return status;
    // Drain the existing samples in their compact representation before
    // applying the new maximum. A late limit must not expand the file simply
    // by assigning distinct identifiers to an already published history.
    if (state->compact && state->compact->journal && state->compact->samples) {
      if (state->file &&
          state->compact->published.spans.size() !=
              state->compact->nodes.size() &&
          !publishSnapshot(*state, false)) {
        state->outputStatus = TALOS_RT_IO_ERROR;
        closeFile(*state);
        return TALOS_RT_IO_ERROR;
      }
    } else if (!fixIdentifiers(*state)) {
      return TALOS_RT_IO_ERROR;
    }
    state->limitSet = true;
    state->limitBytes = bytes;
    if (state->file && state->writtenBytes >= bytes)
      state->limitReached = true;
    finishLimit(*state);
    return state->outputStatus;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_ARGUMENT; }
}

extern "C" talos_rt_status talos_rt_v1_dump_flush(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = traceState(context);
    if (!state)
      return TALOS_RT_OK;
    if (state->compact && state->compact->journal && state->limitSet) {
      // Assigning optional independent IDs could itself consume the
      // remaining byte budget. Flush the current representation instead.
      if (state->file &&
          state->compact->published.spans.size() !=
              state->compact->nodes.size() &&
          !publishSnapshot(*state, false)) {
        state->outputStatus = TALOS_RT_IO_ERROR;
        closeFile(*state);
        return TALOS_RT_IO_ERROR;
      }
      finishLimit(*state);
    } else if (!fixIdentifiers(*state)) {
      return TALOS_RT_IO_ERROR;
    }
    flushBuffer(*state);
    return state->outputStatus;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

extern "C" talos_rt_status talos_rt_v1_dump_close(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    VCDTraceState *state = traceState(context);
    if (!state)
      return TALOS_RT_OK;
    auto status = state->file && state->planBuilt ? emitSlot(context, *state)
                                                  : TALOS_RT_OK;
    if (!finishCompacting(*state) && status == TALOS_RT_OK)
      status = TALOS_RT_IO_ERROR;
    closeFile(*state);
    if (!talos_rt_dump_active_unlocked(context))
      context->postponedSlotHooks &= ~kDumpSlotHook;
    return status == TALOS_RT_OK ? state->outputStatus : status;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

extern "C" talos_rt_status talos_rt_v1_dump_ports(talos_rt_context *context,
                                                  talos_rt_string_v1 pathValue,
                                                  talos_rt_string_v1 scopeValue,
                                                  int32_t timescaleExponent) {
  if (!context || timescaleExponent > 2 || timescaleExponent < -15)
    return TALOS_RT_INVALID_ARGUMENT;
  char pathScratch[8] = {};
  char scopeScratch[8] = {};
  const char *pathBytes = nullptr;
  const char *scopeBytes = nullptr;
  uint64_t pathSize = 0;
  uint64_t scopeSize = 0;
  talos_rt_status status =
      talos_rt_v1_string_view(pathValue, pathScratch, &pathBytes, &pathSize);
  if (status != TALOS_RT_OK)
    return status;
  status = talos_rt_v1_string_view(scopeValue, scopeScratch, &scopeBytes,
                                   &scopeSize);
  if (status != TALOS_RT_OK || pathSize == 0 || scopeSize == 0)
    return status == TALOS_RT_OK ? TALOS_RT_INVALID_ARGUMENT : status;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    std::string path;
    if (pathSize != 0)
      path.assign(pathBytes, static_cast<size_t>(pathSize));
    std::string scope(scopeBytes, static_cast<size_t>(scopeSize));
    ContextMutexLock lock(context);
    if (!context->designDatabase.validated)
      return TALOS_RT_INVALID_DESIGN;
    uint64_t selectedScope = 0;
    uint32_t selectedKind = TALOS_RT_DESIGN_RECORD_INVALID;
    if (!resolveSelection(context->designDatabase, scope, selectedScope,
                          selectedKind) ||
        selectedKind != TALOS_RT_DESIGN_RECORD_SCOPE)
      return TALOS_RT_INVALID_HANDLE;
    if (!context->evcdState) {
      context->evcdState = new (std::nothrow) EVCDTraceState();
      if (!context->evcdState)
        return TALOS_RT_OUT_OF_MEMORY;
    }
    EVCDTraceState &state = *context->evcdState;
    EVCDSession *session = nullptr;
    for (const std::unique_ptr<EVCDSession> &candidate : state.sessions)
      if (candidate->path == path) {
        session = candidate.get();
        break;
      }
    if (!session) {
      auto created = std::make_unique<EVCDSession>();
      created->path = path;
      created->timescaleSet = true;
      created->timescaleExponent = timescaleExponent;
      created->startTime = context->schedulerTime;
      status = openFile(context, *created, path);
      if (status != TALOS_RT_OK)
        return status;
      session = created.get();
      state.sessions.push_back(std::move(created));
    } else if (session->startTime != context->schedulerTime ||
               session->timescaleExponent != timescaleExponent) {
      return TALOS_RT_INVALID_LIFECYCLE;
    }
    // Selections are unique per output file. The same module may be present
    // in several independent EVCD sessions, and repeating it for one file is
    // idempotent while the initial selection slot is still open.
    if (std::find(session->selections.begin(), session->selections.end(),
                  scope) != session->selections.end())
      return TALOS_RT_OK;
    if (session->planBuilt)
      return TALOS_RT_INVALID_LIFECYCLE;
    session->selections.push_back(std::move(scope));
    armDumpSlotHook(context);
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

extern "C" talos_rt_status
talos_rt_v1_dump_ports_control(talos_rt_context *context,
                               talos_rt_string_v1 pathValue, uint32_t action,
                               uint64_t value) {
  if (!context || action > 4)
    return TALOS_RT_INVALID_ARGUMENT;
  char scratch[8] = {};
  const char *pathBytes = nullptr;
  uint64_t pathSize = 0;
  talos_rt_status status =
      talos_rt_v1_string_view(pathValue, scratch, &pathBytes, &pathSize);
  if (status != TALOS_RT_OK)
    return status;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    std::string path;
    if (pathSize != 0)
      path.assign(pathBytes, static_cast<size_t>(pathSize));
    ContextMutexLock lock(context);
    if (!context->evcdState)
      return TALOS_RT_OK;
    for (const std::unique_ptr<EVCDSession> &candidate :
         context->evcdState->sessions) {
      EVCDSession &session = *candidate;
      if (!path.empty() && session.path != path)
        continue;
      if (action == 3) {
        flushBuffer(session);
        continue;
      }
      if (action == 4) {
        session.limitBytes = value;
        continue;
      }
      status = prepareEVCDSession(context, session);
      if (status != TALOS_RT_OK)
        return status;
      if (!session.file)
        continue;
      if (action == 2) {
        status = emitEVCDSlot(context, session, true, "$dumpportsall");
        if (status != TALOS_RT_OK)
          return status;
        continue;
      }
      bool wanted = action == 1;
      if (wanted == session.enabled)
        continue;
      status = emitEVCDSlot(context, session, false);
      if (status != TALOS_RT_OK)
        return status;
      session.enabled = wanted;
      emitTime(session, context->schedulerTime);
      append(session, wanted ? "$dumpportson\n" : "$dumpportsoff\n");
      if (wanted) {
        const uint8_t *valuePlane = nullptr;
        const uint8_t *unknownPlane = nullptr;
        status = dumpPlanes(context, valuePlane, unknownPlane);
        if (status != TALOS_RT_OK)
          return status;
        for (const TraceVariable &variable : session.variables)
          emitEVCDValue(session, variable, valuePlane, unknownPlane);
        for (const TraceRange &range : session.ranges) {
          size_t length = static_cast<size_t>(range.byteEnd - range.byteBegin);
          std::memcpy(session.shadowValue.data() + range.byteBegin,
                      valuePlane + range.byteBegin, length);
          if (unknownPlane)
            std::memcpy(session.shadowUnknown.data() + range.byteBegin,
                        unknownPlane + range.byteBegin, length);
        }
      } else {
        for (const TraceVariable &variable : session.variables)
          emitEVCDOff(session, variable);
      }
      append(session, "$end\n");
    }
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_IO_ERROR; }
}

char *talos::runtime::vcd::formatVectorDigits(const uint8_t *value,
                                              const uint8_t *unknown,
                                              size_t planeBytes,
                                              uint64_t sourceBit,
                                              uint64_t width, char *out) {
  // The most significant chunk holds the bits above the last whole word.
  uint64_t low = (width - 1) / 64 * 64;
  auto count = static_cast<unsigned>(width - low);
  for (;;) {
    uint64_t chunkValue = loadWord(value, planeBytes, sourceBit + low, count);
    uint64_t chunkUnknown =
        unknown ? loadWord(unknown, planeBytes, sourceBit + low, count) : 0;
    out = formatWordDigits(chunkValue, chunkUnknown, count, out);
    if (low == 0)
      return out;
    low -= 64;
    count = 64;
  }
}

size_t talos::runtime::vcd::compactVectorWidth(const uint8_t *value,
                                              const uint8_t *unknown,
                                              size_t planeBytes, uint64_t bit,
                                              uint64_t width) {
  uint64_t top = bit + width - 1;
  bool leadingValue = bitAt(value, top);
  bool leadingUnknown = bitAt(unknown, top);
  if (leadingValue && !leadingUnknown)
    return width;
  for (uint64_t end = width; end;) {
    unsigned count = (end - 1) % 64 + 1;
    uint64_t low = end - count;
    uint64_t v = loadWord(value, planeBytes, bit + low, count);
    uint64_t u = unknown ? loadWord(unknown, planeBytes, bit + low, count) : 0;
    uint64_t different = (leadingValue ? ~v : v) | (leadingUnknown ? ~u : u);
    different &= UINT64_MAX >> (64 - count);
    if (different) {
      unsigned last = 63 - __builtin_clzll(different);
      // Table 21-9: zero before a one is implicit. X or Z extension, or a
      // leading zero before X/Z, must retain one character of the prefix.
      bool nextIsOne = ((v & ~u) >> last) & 1;
      return low + last + 1 + (leadingUnknown || !nextIsOne);
    }
    end = low;
  }
  return 1;
}
