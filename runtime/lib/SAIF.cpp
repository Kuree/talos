//===- SAIF.cpp - Committed RTL switching activity (IEEE 1801 Annex I) ----===//

#include "ProcessPacking.h"
#include "ProcessShared.h"
#include "RuntimeInternal.h"

using namespace talos::process;

namespace {
struct Observation {
  std::string signal;
  uint64_t last = 0;
  uint64_t time[4] = {};
  uint64_t toggles = 0;
  uint32_t current = 0;
};
struct Instance {
  std::string name, virtualType;
  bool isVirtual = false;
  std::map<std::string, std::unique_ptr<Instance>> children;
  std::vector<size_t> ports, nets;
};
struct Watch {
  uint64_t bit;
  size_t observation;
};

constexpr size_t maxDecodedNameBytes = 16384;
constexpr size_t maxTokenBytes = 3 * maxDecodedNameBytes + 2;
constexpr size_t maxInstanceBytes = 128 * (maxTokenBytes + 1);

// Names arrive as compiler-escaped Annex I tokens. Check framing before
// writing them, so the public ABI cannot inject a record or a delimiter.
bool validToken(std::string_view token) {
  if (token.empty() || token.size() > maxTokenBytes)
    return false;
  size_t decodedBytes = 0;
  for (size_t i = 0; i < token.size(); ++i) {
    unsigned char c = token[i];
    if (c <= ' ' || c == 127)
      return false;
    if (c == '\\') {
      if (++i == token.size() || static_cast<unsigned char>(token[i]) <= ' ')
        return false;
      unsigned char escaped = token[i];
      bool alpha = (escaped >= 'a' && escaped <= 'z') ||
                   (escaped >= 'A' && escaped <= 'Z') || escaped == '_';
      bool digit = escaped >= '0' && escaped <= '9';
      if (alpha || (digit && i != 1))
        return false;
    } else if (c == '[' && i != 0) {
      // The only unescaped punctuation is a terminal decimal bit select.
      size_t first = ++i;
      while (i < token.size() && token[i] >= '0' && token[i] <= '9')
        ++i;
      return i > first && i - first <= maxDecodedNameBytes &&
             i + 1 == token.size() && token[i] == ']' &&
             (i == first + 1 || token[first] != '0');
    } else {
      bool alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
      if (!alpha && !(i != 0 && c >= '0' && c <= '9'))
        return false;
    }
    if (++decodedBytes > maxDecodedNameBytes)
      return false;
  }
  return true;
}

// Tick * femtosecond precision can exceed 64 bits. Decimal integer output
// retains exact residence times without floating point rounding.
std::string decimal(unsigned __int128 value) {
  char buffer[40];
  char *end = buffer + sizeof(buffer), *cursor = end;
  do {
    *--cursor = '0' + value % 10;
    value /= 10;
  } while (value);
  return std::string(cursor, end);
}

std::string quoted(std::string_view value) {
  // Annex I strings are literal, single-line strings, not C string escapes.
  return "\"" + std::string(value) + "\"";
}
} // namespace

struct SAIFState {
  std::string output;
  uint64_t precision = 1;
  bool sealed = false;
  bool finished = false;
  Instance root;
  std::vector<Observation> observations;
  std::unordered_map<uint32_t, std::vector<Watch>> watches;
};

extern "C" talos_rt_status talos_rt_v1_saif_configure(talos_rt_context *context,
                                                      const char *output,
                                                      uint64_t precision) {
  if (!context || !output || !*output || !precision)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    if (context->saif || context->schedulerTime)
      return TALOS_RT_INVALID_ARGUMENT;
    auto state = std::make_shared<SAIFState>();
    state->output = output;
    state->precision = precision;
    context->saif = std::move(state);
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
}

extern "C" talos_rt_status
talos_rt_v1_saif_bind(talos_rt_context *context, uint64_t handle,
                      const char *instance, uint64_t instanceBytes,
                      const char *signal, uint32_t port,
                      const char *virtualType, uint32_t initial) {
  if (!context || !instance || !instanceBytes ||
      instanceBytes > maxInstanceBytes || instance[instanceBytes - 1] != '\0' ||
      !signal || port > 1 || initial > 3 || !validToken(signal) ||
      (virtualType && !port))
    return TALOS_RT_INVALID_ARGUMENT;
  if (virtualType && std::string_view(virtualType).find_first_of("\"\n\r") !=
                         std::string_view::npos)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    auto *state = context->saif.get();
    if (!state || state->sealed || state->observations.size() >= (1 << 20) ||
        context->schedulerTime)
      return TALOS_RT_INVALID_ARGUMENT;
    uint32_t id;
    int64_t offset;
    if (!decodeNativeStatic(handle, id, offset) || offset < 0)
      return TALOS_RT_INVALID_HANDLE;
    const NativeStaticState *native = findNativeStaticState(context, id);
    if (!native || uint64_t(offset) >= native->bitWidth)
      return TALOS_RT_INVALID_HANDLE;
    Instance *node = &state->root;
    size_t depth = 0;
    for (uint64_t begin = 0; begin < instanceBytes;) {
      std::string_view component(instance + begin);
      if (++depth > 128 || !validToken(component))
        return TALOS_RT_INVALID_ARGUMENT;
      auto &child = node->children[std::string(component)];
      if (!child) {
        child = std::make_unique<Instance>();
        child->name = component;
      }
      node = child.get();
      begin += component.size() + 1;
    }
    if (virtualType) {
      if (node->isVirtual && node->virtualType != virtualType)
        return TALOS_RT_INVALID_ARGUMENT;
      node->isVirtual = true;
      node->virtualType = virtualType;
    }
    auto &points = port ? node->ports : node->nets;
    size_t index = state->observations.size();
    state->observations.push_back({signal, 0, {}, 0, initial});
    points.push_back(index);
    state->watches[id].push_back({uint64_t(offset), index});
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
}

extern "C" talos_rt_status talos_rt_v1_saif_seal(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    auto *state = context->saif.get();
    if (!state || state->sealed)
      return TALOS_RT_INVALID_ARGUMENT;
    std::vector<const Instance *> pending{&state->root};
    while (!pending.empty()) {
      const Instance *node = pending.back();
      pending.pop_back();
      if (node->isVirtual && (!node->nets.empty() || !node->children.empty()))
        return TALOS_RT_INVALID_ARGUMENT;
      for (const auto *points : {&node->ports, &node->nets}) {
        std::unordered_set<std::string_view> names;
        for (size_t index : *points)
          if (!names.insert(state->observations[index].signal).second)
            return TALOS_RT_INVALID_ARGUMENT;
      }
      for (const auto &child : node->children)
        pending.push_back(child.second.get());
    }
    for (auto &entry : state->watches)
      std::sort(entry.second.begin(), entry.second.end(),
                [](const Watch &a, const Watch &b) { return a.bit < b.bit; });
    state->sealed = true;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
}

bool talos_rt_saif_tracks_static_state_unlocked(const talos_rt_context *context,
                                                uint32_t id) {
  return context && context->saif && context->saif->sealed &&
         context->saif->watches.count(id);
}

void talos_rt_saif_record_transition_unlocked(talos_rt_context *context,
                                              uint64_t handle, uint64_t width,
                                              const uint8_t *changed,
                                              const uint8_t *newValue,
                                              const uint8_t *newUnknown) {
  auto *state = context->saif.get();
  if (!state || !state->sealed || state->finished || !changed || !width)
    return;
  uint32_t id;
  int64_t offset;
  if (!decodeNativeStatic(handle, id, offset) || offset < 0 ||
      width > UINT64_MAX - uint64_t(offset))
    return;
  auto found = state->watches.find(id);
  if (found == state->watches.end())
    return;
  const NativeStaticState *native =
      newValue ? nullptr : findNativeStaticState(context, id);
  const auto &watches = found->second;
  auto it = std::lower_bound(
      watches.begin(), watches.end(), uint64_t(offset),
      [](const Watch &watch, uint64_t low) { return watch.bit < low; });
  for (; it != watches.end() && it->bit < uint64_t(offset) + width; ++it) {
    uint64_t relative = it->bit - offset;
    if (!byteBit(changed, relative))
      continue;
    bool value, unknown;
    if (newValue) {
      value = byteBit(newValue, relative);
      unknown = byteBit(newUnknown, relative);
    } else {
      if (!native || it->bit >= native->bitWidth)
        continue;
      uint64_t bit = native->bitOffset + it->bit;
      value = (context->stateValue[bit / 64] >> (bit % 64)) & 1;
      unknown = (context->stateUnknown[bit / 64] >> (bit % 64)) & 1;
    }
    uint32_t current = unknown ? (value ? 3 : 2) : (value ? 1 : 0);
    Observation &point = state->observations[it->observation];
    if (current == point.current)
      continue;
    uint64_t now = context->schedulerTime;
    if (now < point.last ||
        (current < 2 && point.current < 2 && point.toggles == UINT64_MAX)) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return;
    }
    point.time[point.current] += now - point.last;
    // I.3.5.1: X/Z transitions do not contribute to TC.
    point.toggles += current < 2 && point.current < 2;
    point.last = now;
    point.current = current;
  }
}

namespace {
void writeInstance(FILE *file, const SAIFState &state, const Instance &node) {
  std::fprintf(file, "(%s %s%s\n",
               node.isVirtual ? "VIRTUAL_INSTANCE" : "INSTANCE",
               node.isVirtual ? (quoted(node.virtualType) + " ").c_str() : "",
               node.name.c_str());
  auto writePoints = [&](const char *kind, const std::vector<size_t> &points) {
    if (points.empty())
      return;
    std::fprintf(file, "(%s\n", kind);
    for (size_t index : points) {
      const Observation &point = state.observations[index];
      std::fprintf(file, "(%s (T0 %s) (T1 %s) (TX %s) (TZ %s) (TC %s))\n",
                   point.signal.c_str(),
                   decimal(static_cast<unsigned __int128>(point.time[0]) *
                           state.precision)
                       .c_str(),
                   decimal(static_cast<unsigned __int128>(point.time[1]) *
                           state.precision)
                       .c_str(),
                   decimal(static_cast<unsigned __int128>(point.time[2]) *
                           state.precision)
                       .c_str(),
                   decimal(static_cast<unsigned __int128>(point.time[3]) *
                           state.precision)
                       .c_str(),
                   decimal(point.toggles).c_str());
    }
    std::fputs(")\n", file);
  };
  writePoints("PORT", node.ports);
  writePoints("NET", node.nets);
  for (const auto &child : node.children)
    writeInstance(file, state, *child.second);
  std::fputs(")\n", file);
}
} // namespace

extern "C" talos_rt_status talos_rt_v1_saif_finish(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    auto *state = context->saif.get();
    if (!state || !state->sealed || state->finished)
      return TALOS_RT_INVALID_ARGUMENT;
    for (auto &point : state->observations) {
      if (context->schedulerTime < point.last)
        return TALOS_RT_OUT_OF_RESOURCES;
      point.time[point.current] += context->schedulerTime - point.last;
      point.last = context->schedulerTime;
    }
    state->finished = true;
    std::unique_ptr<FILE, decltype(&std::fclose)> file(
        std::fopen(state->output.c_str(), "w"), &std::fclose);
    if (!file) {
      std::fprintf(stderr, "talos: cannot open SAIF output '%s'\n",
                   state->output.c_str());
      return TALOS_RT_IO_ERROR;
    }
    std::fprintf(
        file.get(),
        "(SAIFILE\n(SAIFVERSION \"2.0\") (DIRECTION \"backward\")\n"
        "(DESIGN) (DATE) (VENDOR) (PROGRAM_NAME \"talos\") (PROGRAM_VERSION)\n"
        "(DIVIDER /) (TIMESCALE 1 fs) (DURATION %s)\n",
        decimal(static_cast<unsigned __int128>(context->schedulerTime) *
                state->precision)
            .c_str());
    for (const auto &child : state->root.children)
      writeInstance(file.get(), *state, *child.second);
    std::fputs(")\n", file.get());
    bool failed = std::ferror(file.get());
    failed |= std::fclose(file.release()) != 0;
    if (failed)
      std::fprintf(stderr, "talos: cannot write SAIF output '%s'\n",
                   state->output.c_str());
    return failed ? TALOS_RT_IO_ERROR : TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
}
