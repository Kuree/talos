#include "VPIPackedCallbackValue.h"
#include "VPIStaticChangeTarget.h"
#include <cassert>
#include <cstdio>
#include <cstring>

extern "C" const talos_rt_execution_descriptor_v1
    __talos_execution_descriptor_v1;

static void equal(const s_vpi_value &expected, const s_vpi_value &actual,
                  unsigned width) {
  assert(expected.format == actual.format);
  switch (expected.format) {
  case vpiSuppressVal:
    break;
  case vpiIntVal:
    assert(expected.value.integer == actual.value.integer);
    break;
  case vpiScalarVal:
    assert(expected.value.scalar == actual.value.scalar);
    break;
  case vpiRealVal:
    assert(expected.value.real == actual.value.real);
    break;
  case vpiTimeVal:
    assert(expected.value.time->type == actual.value.time->type);
    assert(expected.value.time->high == actual.value.time->high);
    assert(expected.value.time->low == actual.value.time->low);
    break;
  case vpiVectorVal:
    for (unsigned i = 0; i != (width + 31) / 32; ++i) {
      assert(expected.value.vector[i].aval == actual.value.vector[i].aval);
      assert(expected.value.vector[i].bval == actual.value.vector[i].bval);
    }
    break;
  default:
    assert(std::strcmp(expected.value.str, actual.value.str) == 0);
    break;
  }
}

static void goldenFormats() {
  // IEEE 1800-2023 38.33/38.36.1, Tables 38-3/38-5: these expected
  // representations are independent of the existing vpi_get_value code.
  auto string = [](int format, unsigned width, bool isSigned, uint64_t value,
                   uint64_t unknown, const char *expected) {
    talos::runtime::VPIPackedCallbackValue storage;
    s_vpi_value payload{};
    payload.format = format;
    assert(storage.format(payload, width, isSigned, value, unknown));
    assert(std::strcmp(payload.value.str, expected) == 0);
  };
  string(vpiBinStrVal, 4, false, 5, 2, "01x1");
  string(vpiBinStrVal, 4, false, 7, 2, "01z1");
  string(vpiHexStrVal, 4, false, 0, 15, "x");
  string(vpiHexStrVal, 4, false, 15, 15, "z");
  string(vpiDecStrVal, 8, true, 128, 0, "-128");
  string(vpiDecStrVal, 8, false, 128, 0, "128");

  talos::runtime::VPIPackedCallbackValue storage;
  s_vpi_value payload{};
  payload.format = vpiVectorVal;
  assert(storage.format(payload, 2, false, 2, 3));
  assert(payload.value.vector[0].aval == 1);
  assert(payload.value.vector[0].bval == 3);
  payload.format = vpiScalarVal;
  assert(storage.format(payload, 1, false, 0, 1));
  assert(payload.value.scalar == vpiX);
  assert(storage.format(payload, 1, false, 1, 1));
  assert(payload.value.scalar == vpiZ);
  payload.format = vpiTimeVal;
  assert(storage.format(payload, 64, false, UINT64_C(0x89abcdef01234567), 0));
  assert(payload.value.time->high == UINT32_C(0x89abcdef));
  assert(payload.value.time->low == UINT32_C(0x01234567));
}

int main() {
  goldenFormats();
  talos_rt_context *context = nullptr;
  assert(talos_rt_v1_context_create_for_design(&__talos_execution_descriptor_v1,
                                               &context) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_startup(context, nullptr, 0) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_end_compile(context) == TALOS_RT_OK);
  assert(talos_rt_v1_vpi_start_simulation(context) == TALOS_RT_OK);
  unsigned comparisons = 0;
  for (unsigned width : {1u, 3u, 8u, 16u, 32u, 63u, 64u}) {
    for (bool isSigned : {false, true}) {
      char name[32];
      std::snprintf(name, sizeof(name), "top.%c%u", isSigned ? 's' : 'u',
                    width);
      auto object = vpi_handle_by_name(name, nullptr);
      assert(object);
      for (uint64_t value :
           {UINT64_C(0), UINT64_C(1), UINT64_MAX, UINT64_C(1) << (width - 1),
            UINT64_C(0x0123456789abcdef), UINT64_C(0xfedcba9876543210)}) {
        for (uint64_t unknown :
             {UINT64_C(0), UINT64_MAX, UINT64_C(0xaaaaaaaaaaaaaaaa)}) {
          const uint64_t aval = value ^ unknown;
          s_vpi_vecval words[2] = {
              {static_cast<PLI_UINT32>(aval), static_cast<PLI_UINT32>(unknown)},
              {static_cast<PLI_UINT32>(aval >> 32),
               static_cast<PLI_UINT32>(unknown >> 32)}};
          s_vpi_value put{};
          put.format = vpiVectorVal;
          put.value.vector = words;
          vpi_put_value(object, &put, nullptr, vpiNoDelay);
          for (int format :
               {vpiSuppressVal, vpiIntVal, vpiScalarVal, vpiVectorVal,
                vpiTimeVal, vpiRealVal, vpiStringVal, vpiDecStrVal,
                vpiBinStrVal, vpiOctStrVal, vpiHexStrVal, vpiObjTypeVal}) {
            VPIStaticChangeTarget target;
            assert(talos_rt_vpi_bind_static_change_target(
                       context, object, format, &target) == TALOS_RT_OK);
            assert(target.selectedWidth == width &&
                   target.isSigned == isSigned);
            talos::runtime::VPIPackedCallbackValue storage;
            s_vpi_value payload{};
            payload.format = target.valueFormat;
            assert(storage.format(payload, width, isSigned, value, unknown));
            s_vpi_value actual{};
            actual.format = payload.format;
            vpi_get_value(object, &actual);
            equal(payload, actual, width);
            // Re-entering the public value routines overwrites their shared
            // scratch, but cannot overwrite this invocation's payload.
            s_vpi_value nested{};
            nested.format = vpiBinStrVal;
            vpi_get_value(object, &nested);
            actual.format = payload.format;
            vpi_get_value(object, &actual);
            equal(payload, actual, width);
            ++comparisons;
          }
        }
      }
      assert(vpi_release_handle(object) == 1);
    }
  }
  talos::runtime::VPIPackedCallbackValue invalid;
  s_vpi_value out{};
  out.format = vpiVectorVal;
  assert(!invalid.format(out, 0, false, 0, 0));
  assert(!invalid.format(out, 65, false, 0, 0));
  out.format = vpiStrengthVal;
  assert(!invalid.format(out, 1, false, 0, 0));
  out.format = -1;
  assert(!invalid.format(out, 1, false, 0, 0));
  assert(comparisons == 3024);
  talos_rt_v1_context_destroy(context);
  std::puts("packed callback payloads: 3024 generated-object comparisons");
}
