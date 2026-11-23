// Generic VPI object-model walker for the vpi-object-model-*.sv tests.
//
// The design calls vpi_object_model_audit() once. The walker asks every
// null-root property and relation, visits each object reachable from the root
// relations once (deduplicated with vpi_compare_objects, IEEE 1800-2023 38.3),
// and asks every property and relation that the generated LRM model
// (VPIObjectModel.h.inc, the runtime's own legality table) declares for that
// object's kind. A property counts as answered when vpi_get/vpi_get64 does not
// return vpiUndefined or vpi_get_str does not return NULL (38.6, 38.7, 38.11;
// a few legal integer values coincide with vpiUndefined, e.g. vpiTimeUnit -1),
// and a relation when vpi_handle/vpi_iterate returns a handle (38.18, 38.23).
//
// Output, one line per reached kind in model order:
//   <kind> objects=N properties=P/LP relations=R/LR answers=A
// P and R count the legal queries that answered on at least one object of the
// kind, LP and LR the legal queries, and A the answered (object, query) pairs.
// Standard error gets one line per legal (kind, query) with how many objects
// answered and its first VPI error. lit shows it when a check fails, and a
// before/after diff of it names the query that moved.

#include "sv_vpi_user.h"
#include "talos/Reflection/VPIObjectModel.h"

#include <cstdio>

using namespace talos::reflection;

namespace {
constexpr unsigned kPropertyCount =
    sizeof(vpiProperties) / sizeof(vpiProperties[0]);
constexpr unsigned kTraversalCount =
    sizeof(vpiTraversals) / sizeof(vpiTraversals[0]);
constexpr unsigned kMaxObjects = 4096;
constexpr unsigned kMaxScan = 256;
constexpr unsigned kKindLimit = 4096;
constexpr unsigned kErrorLength = 96;

// Per legal query: objects asked, objects that answered, first VPI error.
struct Tally {
  unsigned asked = 0, answered = 0;
  char error[kErrorLength] = {};
};
Tally propertyTally[kPropertyCount], traversalTally[kTraversalCount];
unsigned objectsOfKind[kKindLimit], answersOfKind[kKindLimit];
int objectKinds[kMaxObjects];
vpiHandle objects[kMaxObjects];
unsigned objectCount = 0;

void record(Tally &tally, unsigned kind, bool answered) {
  ++tally.asked;
  if (answered) {
    ++tally.answered;
    ++answersOfKind[kind];
  }
  s_vpi_error_info info{};
  if (!tally.error[0] && vpi_chk_error(&info) && info.message)
    std::snprintf(tally.error, kErrorLength, "%s", info.message);
}

void visit(vpiHandle object) {
  if (!object || objectCount == kMaxObjects)
    return;
  int kind = vpi_get(vpiType, object);
  if (kind <= 0 || kind >= static_cast<int>(kKindLimit))
    return;
  for (unsigned index = 0; index != objectCount; ++index)
    if (objectKinds[index] == kind &&
        vpi_compare_objects(objects[index], object))
      return;
  objectKinds[objectCount] = kind;
  objects[objectCount++] = object;
}

// Asks every legal query of `kind` on `object` (NULL for the null root).
void ask(vpiHandle object, unsigned kind) {
  ++objectsOfKind[kind];
  for (unsigned index = 0; index != kPropertyCount; ++index) {
    const auto &property = vpiProperties[index];
    if (property.sourceType != kind)
      continue;
    const auto selector = static_cast<PLI_INT32>(property.property);
    bool answered;
    if (property.valueKind == VPIPropertyValueKind::String)
      answered = vpi_get_str(selector, object) != nullptr;
    else if (property.valueKind == VPIPropertyValueKind::Int64)
      answered = vpi_get64(selector, object) != vpiUndefined;
    else
      answered = vpi_get(selector, object) != vpiUndefined;
    record(propertyTally[index], kind, answered);
  }
  for (unsigned index = 0; index != kTraversalCount; ++index) {
    const auto &traversal = vpiTraversals[index];
    if (traversal.sourceType != kind)
      continue;
    const auto selector = static_cast<PLI_INT32>(traversal.selector);
    if (traversal.mode == VPITraversalMode::Handle) {
      vpiHandle target = vpi_handle(selector, object);
      record(traversalTally[index], kind, target != nullptr);
      visit(target);
      continue;
    }
    vpiHandle iterator = vpi_iterate(selector, object);
    record(traversalTally[index], kind, iterator != nullptr);
    unsigned scanned = 0;
    while (iterator) {
      vpiHandle target = vpi_scan(iterator);
      if (!target)
        break; // An exhausted iterator is already released (38.40).
      visit(target);
      if (++scanned == kMaxScan) {
        vpi_release_handle(iterator); // Not exhausted (38.38).
        break;
      }
    }
  }
}

void report(unsigned kind, const char *name) {
  unsigned properties = 0, propertiesAnswered = 0;
  unsigned relations = 0, relationsAnswered = 0;
  for (unsigned index = 0; index != kPropertyCount; ++index)
    if (vpiProperties[index].sourceType == kind) {
      ++properties;
      propertiesAnswered += propertyTally[index].answered != 0;
    }
  for (unsigned index = 0; index != kTraversalCount; ++index)
    if (vpiTraversals[index].sourceType == kind) {
      ++relations;
      relationsAnswered += traversalTally[index].answered != 0;
    }
  std::printf("%s objects=%u properties=%u/%u relations=%u/%u answers=%u\n",
              name, objectsOfKind[kind], propertiesAnswered, properties,
              relationsAnswered, relations, answersOfKind[kind]);
}

void detail(unsigned kind, const char *name) {
  for (unsigned index = 0; index != kPropertyCount; ++index)
    if (vpiProperties[index].sourceType == kind) {
      const Tally &tally = propertyTally[index];
      std::fprintf(stderr, "%s property %s %u/%u %s\n", name,
                  vpiProperties[index].apiName, tally.answered, tally.asked,
                  tally.error);
    }
  for (unsigned index = 0; index != kTraversalCount; ++index)
    if (vpiTraversals[index].sourceType == kind) {
      const Tally &tally = traversalTally[index];
      std::fprintf(stderr, "%s %s %s %u/%u %s\n", name,
                  vpiTraversals[index].mode == VPITraversalMode::Handle
                      ? "handle"
                      : "iterate",
                  vpiTraversals[index].selectorName, tally.answered,
                  tally.asked, tally.error);
    }
}
} // namespace

extern "C" void vpi_object_model_audit(void) {
  ask(nullptr, 0);
  // Visiting appends objects; each is asked exactly once.
  for (unsigned index = 0; index != objectCount; ++index)
    ask(objects[index], static_cast<unsigned>(objectKinds[index]));
  report(0, "null");
  detail(0, "null");
  for (const auto &descriptor : vpiObjectKinds) {
    const unsigned kind = descriptor.value;
    if (kind == 0 || kind >= kKindLimit || !objectsOfKind[kind] ||
        (descriptor.aliasOf && descriptor.aliasOf[0]))
      continue;
    report(kind, descriptor.apiName);
    detail(kind, descriptor.apiName);
  }
  std::printf("audit end\n");
}
