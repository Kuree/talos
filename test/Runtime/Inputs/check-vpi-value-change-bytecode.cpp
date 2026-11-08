#include "sv_vpi_user.h"
#include "talos/Runtime/Runtime.h"
#include "vpi_user.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

static uint64_t allocations, deallocations;
void *operator new(size_t size) {
  ++allocations;
  if (void *memory = std::malloc(size ? size : 1))
    return memory;
  std::abort();
}
void operator delete(void *memory) noexcept {
  deallocations += memory != nullptr;
  std::free(memory);
}
void operator delete(void *memory, size_t) noexcept {
  ::operator delete(memory);
}

extern "C" const talos_rt_execution_descriptor_v1
    __talos_execution_descriptor_v1;
extern "C" const talos_rt_process_descriptor_v1 rootDescriptor
#if defined(__APPLE__)
    __asm__("_root.__talos_process_descriptor");
#else
    __asm__("root.__talos_process_descriptor");
#endif

static vpiHandle object, later, bitCallback, lateCallback;
static unsigned calls, bits, lateCalls, depth;
static bool putting;
static vpiHandle churnHandle;
static unsigned churnCalls;

static PLI_INT32 churn(p_cb_data data) {
  assert(!putting && !data->time && data->value);
  assert(data->value->format == vpiIntVal);
  assert(data->value->value.integer == (churnCalls & 1));
  ++churnCalls;
  assert(vpi_remove_cb(churnHandle) == 1);
  return 0;
}
static constexpr unsigned values[] = {0, 1, 5, 6, 2, 3, 4, 255, 0};
static constexpr unsigned unknowns[] = {0, 0, 0, 0, 0, 0, 0, 255, 255};

static PLI_INT32 late(p_cb_data data) {
  assert(!depth && !putting && !data->time && data->value);
  assert(data->value->format == vpiIntVal);
  assert(data->value->value.integer == (lateCalls ? 6 : 5));
  ++lateCalls;
  return 0;
}

static PLI_INT32 bitChanged(p_cb_data data) {
  assert(!depth && !putting && data->value);
  assert(data->value->format == vpiScalarVal);
  assert(data->value->value.scalar == (bits == 1 ? vpi1 : vpi0));
  ++bits;
  return 0;
}

static PLI_INT32 changed(p_cb_data data) {
  assert(!depth && !putting && data->time && data->value && data->obj);
  ++depth;
  assert(calls < 9 && data->reason == cbValueChange);
  assert(data->cb_rtn == changed && data->index == 0);
  assert(data->user_data ==
         reinterpret_cast<char *>(static_cast<uintptr_t>(17)));
  assert(data->time->type == vpiSimTime && data->time->high == 0);
  assert(data->time->low == (calls < 7 ? 0u : 1u));
  assert(data->value->format == vpiVectorVal);
  assert(data->value->value.vector[0].aval == values[calls]);
  assert(data->value->value.vector[0].bval == unknowns[calls]);
  assert(std::strcmp(vpi_get_str(vpiFullName, data->obj), "top.value") == 0);
  object = data->obj;
  s_vpi_value state{};
  state.format = vpiIntVal;
  vpi_get_value(later, &state);
  assert(state.value.integer == (calls < 5 ? 0 : 9));
  const unsigned current = calls++;
  if (current == 1) {
    s_vpi_time time{};
    time.type = vpiSuppressTime;
    s_vpi_value value{};
    value.format = vpiIntVal;
    s_cb_data registration{};
    registration.reason = cbValueChange;
    registration.cb_rtn = late;
    registration.obj = object;
    registration.time = &time;
    registration.value = &value;
    lateCallback = vpi_register_cb(&registration);
    assert(lateCallback);
    putting = true;
    value.value.integer = 5;
    vpi_put_value(object, &value, nullptr, vpiNoDelay);
    value.value.integer = 6;
    vpi_put_value(object, &value, nullptr, vpiNoDelay);
    assert(calls == 2 && !lateCalls); // Neither put called the client.
    putting = false;
    // A nested public vector read overwrites its own scratch, not this event.
    value.format = vpiVectorVal;
    vpi_get_value(object, &value);
    assert(value.value.vector[0].aval == 6);
    assert(data->value->value.vector[0].aval == 1);
  }
  if (current == 4) {
    assert(vpi_remove_cb(bitCallback) == 1);
    assert(vpi_remove_cb(lateCallback) == 1);
    assert(lateCalls == 2);
    assert(vpi_release_handle(object) == 1);
    object = nullptr; // The next callback must recover its owned logical view.
  }
  --depth;
  return 0;
}

static vpiHandle findRegistration() {
  auto iterator = vpi_iterate(vpiCallback, nullptr);
  assert(iterator);
  vpiHandle result = nullptr;
  while (auto handle = vpi_scan(iterator)) {
    s_cb_data info{};
    vpi_get_cb_info(handle, &info);
    if (info.cb_rtn == changed) {
      assert(info.reason == cbValueChange && info.obj && info.time &&
             info.value);
      assert(info.time->type == vpiSimTime &&
             info.value->format == vpiObjTypeVal);
      result = handle;
    } else {
      assert(vpi_release_handle(handle) == 1);
    }
  }
  assert(result);
  return result;
}

int main() {
  talos_rt_context *context = nullptr;
  assert(talos_rt_v1_context_create_for_design(&__talos_execution_descriptor_v1,
                                               &context) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_startup(context, nullptr, 0) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_end_compile(context) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_start_simulation(context) == TALOS_RT_OK);
  object = vpi_handle_by_name(const_cast<char *>("top.value"), nullptr);
  later = vpi_handle_by_name(const_cast<char *>("top.later"), nullptr);
  assert(object && later);
  s_vpi_vecval initial{255, 255};
  s_vpi_value value{};
  value.format = vpiVectorVal;
  value.value.vector = &initial;
  vpi_put_value(object, &value, nullptr, vpiNoDelay);
  value.format = vpiIntVal;
  value.value.integer = 0;
  vpi_put_value(later, &value, nullptr, vpiNoDelay);
  s_vpi_time time{};
  time.type = vpiSimTime;
  value.format = vpiObjTypeVal;
  s_cb_data registration{};
  registration.reason = cbValueChange;
  registration.cb_rtn = changed;
  registration.obj = object;
  registration.time = &time;
  registration.value = &value;
  registration.user_data = reinterpret_cast<char *>(static_cast<uintptr_t>(17));
  auto primary = vpi_register_cb(&registration);
  assert(primary);
  auto selected = vpi_handle_by_index(object, 0);
  assert(selected);
  registration.obj = selected;
  registration.cb_rtn = bitChanged;
  value.format = vpiScalarVal;
  bitCallback = vpi_register_cb(&registration);
  assert(bitCallback);
  assert(vpi_release_handle(selected) == 1);
  assert(vpi_release_handle(object) == 1);
  assert(vpi_release_handle(primary) ==
         1); // Release does not cancel the watch.
  auto callback = findRegistration();
  auto stale = findRegistration();
  registration = {};
  time = {};
  value = {}; // Registration owns all formats and object metadata.
  talos_rt_process_spawn_plan_v1 plan{};
  plan.descriptor = &rootDescriptor;
  plan.schedule_flags = TALOS_RT_SCHEDULE_ROOT;
  plan.actor_slot = UINT32_MAX;
  assert(talos_rt_v1_process_spawn(context, &plan, nullptr));
  assert(talos_rt_v1_scheduler_run(context) == TALOS_RT_OK);
  assert(calls == 9 && bits == 3 && lateCalls == 2);
  assert(vpi_remove_cb(callback) == 1);
  assert(vpi_remove_cb(stale) == 0);
  assert(vpi_remove_cb(callback) == 0);
  time.type = vpiSuppressTime;
  value.format = vpiIntVal;
  registration.reason = cbValueChange;
  registration.cb_rtn = churn;
  registration.obj = object;
  registration.time = &time;
  registration.value = &value;
  auto cycle = [&](unsigned i) {
    churnHandle = vpi_register_cb(&registration);
    assert(churnHandle);
    value.value.integer = i & 1;
    putting = true;
    vpi_put_value(object, &value, nullptr, vpiNoDelay);
    assert(churnCalls == i);
    putting = false;
    assert(talos_rt_v1_scheduler_run(context) == TALOS_RT_OK);
    assert(churnCalls == i + 1);
    assert(vpi_remove_cb(churnHandle) == 0);
  };
  for (unsigned i = 0; i != 16; ++i)
    cycle(i);
  const uint64_t warmed = allocations;
  for (unsigned i = 16; i != 10016; ++i)
    cycle(i);
  if (allocations != warmed)
    std::fprintf(stderr, "callback churn allocations: %llu\n",
                 static_cast<unsigned long long>(allocations - warmed));
  assert(allocations == warmed);
  auto aliases = [&](unsigned i) {
    auto primary = vpi_register_cb(&registration);
    assert(primary);
    auto iterator = vpi_iterate(vpiCallback, nullptr);
    assert(iterator);
    auto alias = vpi_scan(iterator);
    assert(alias && vpi_scan(iterator) == nullptr);
    assert(vpi_compare_objects(primary, alias) == 1);
    if (i & 1) {
      assert(vpi_release_handle(primary) == 1);
      assert(vpi_remove_cb(alias) == 1);
    } else {
      // The unused alias becomes invalid and must be reclaimed by removal.
      assert(vpi_remove_cb(primary) == 1);
    }
    // Invalid handles are deliberately not released (LRM 38.38).
  };
  for (unsigned i = 0; i != 16; ++i)
    aliases(i);
  const uint64_t liveAllocations = allocations - deallocations;
  for (unsigned i = 16; i != 1016; ++i)
    aliases(i);
  assert(allocations - deallocations == liveAllocations);
  assert(vpi_release_handle(later) == 1);
  talos_rt_v1_context_destroy(context);
  std::puts("value-change: coherent stores, C6 puts, NBA order, selectors and "
            "handles");
  std::puts("warm callback churn: 10000 public registrations and deliveries, "
            "zero allocations");
  std::puts("callback iterator churn: 1000 removals reclaim every alias");
}
