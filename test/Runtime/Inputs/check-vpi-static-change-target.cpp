#include "VPIStaticChangeTarget.h"
#include "sv_vpi_user.h"
#include "vpi_user.h"
#include <cassert>
#include <cstdio>

extern "C" const talos_rt_execution_descriptor_v1
    __talos_execution_descriptor_v1;

int main() {
  talos_rt_context *context = nullptr;
  assert(talos_rt_v1_context_create_for_design(&__talos_execution_descriptor_v1,
                                               &context) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_startup(context, nullptr, 0) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_end_compile(context) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_start_simulation(context) == TALOS_RT_OK);
  auto object = vpi_handle_by_name(const_cast<char *>("top.value"), nullptr);
  auto wide = vpi_handle_by_name(const_cast<char *>("top.wide"), nullptr);
  assert(object && wide);
  s_vpi_value value{};
  value.format = vpiIntVal;
  value.value.integer = 0x8421;
  vpi_put_value(object, &value, nullptr, vpiNoDelay);
  VPIStaticChangeTarget root;
  assert(talos_rt_vpi_bind_static_change_target(context, object, vpiObjTypeVal,
                                                &root) == TALOS_RT_OK);
  assert(root.rootWidth == 16 && root.selectedWidth == 16);
  assert(root.selectedOffset == root.rootStateOffset);
  assert(root.valueFormat == vpiVectorVal && root.fourState && !root.isSigned);
  for (unsigned index = 0; index != 16; ++index) {
    auto bit = vpi_handle_by_index(object, index);
    assert(bit);
    VPIStaticChangeTarget selected;
    assert(talos_rt_vpi_bind_static_change_target(context, bit, vpiObjTypeVal,
                                                  &selected) == TALOS_RT_OK);
    assert(selected.object.offset == root.object.offset);
    assert(selected.rootStateOffset == root.rootStateOffset &&
           selected.rootWidth == root.rootWidth);
    assert(selected.selectedOffset == root.rootStateOffset + index &&
           selected.selectedWidth == 1 && selected.valueFormat == vpiScalarVal);
    s_vpi_value actual{};
    actual.format = vpiIntVal;
    vpi_get_value(bit, &actual);
    assert(actual.value.integer == ((0x8421 >> index) & 1));
    assert(vpi_release_handle(bit) == 1);
  }
  VPIStaticChangeTarget unsupported = root;
  assert(talos_rt_vpi_bind_static_change_target(context, wide, vpiIntVal,
                                                &unsupported) ==
         TALOS_RT_TIER_UNAVAILABLE);
  assert(!unsupported.object.offset && !unsupported.selectedWidth);
  vpi_get_value(object, &value);
  assert(value.value.integer == 0x8421);
  assert(vpi_release_handle(wide) == 1);
  assert(vpi_release_handle(object) == 1);
  talos_rt_v1_context_destroy(context);
  std::puts(
      "static change binding: generated root and all 16 packed selectors");
}
