//===- VCDTest.cpp - Waveform dump tests ---------------------------------===//

#include "../lib/ProcessContext.h"
#include "../lib/ProcessShared.h"
#include "../lib/RuntimeInternal.h"
#include "../lib/VCDFormat.h"
#include "TestEnvironment.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHash.h"

#include "sv_vpi_user.h"

#include "gtest/gtest.h"

#if defined(__linux__) && !defined(__EMSCRIPTEN__)
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <sys/xattr.h>
#endif

#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

void put32(std::vector<uint8_t> &bytes, size_t offset, uint32_t value) {
  for (unsigned index = 0; index != 4; ++index)
    bytes[offset + index] = static_cast<uint8_t>(value >> (index * 8));
}

void put64(std::vector<uint8_t> &bytes, size_t offset, uint64_t value) {
  for (unsigned index = 0; index != 8; ++index)
    bytes[offset + index] = static_cast<uint8_t>(value >> (index * 8));
}

uint32_t designRecordKind(uint32_t physicalKind, uint32_t vpiKind) {
  return physicalKind | (vpiKind << 16);
}

uint64_t nameHash(const std::string &name) {
  return talos_stable_hash(reinterpret_cast<const uint8_t *>(name.data()),
                           name.size());
}

uint64_t imageChecksum(const std::vector<uint8_t> &bytes) {
  uint64_t hash = talos_stable_image_checksum(bytes.data(), bytes.size(), 32);
  return hash;
}

// Canonical bit layout of the test design.
constexpr uint64_t kClkBit = 0;
constexpr uint64_t kDataBit = 8;
constexpr uint64_t kCountBit = 16;
constexpr uint64_t kRealBit = 64;
constexpr uint64_t kStructBit = 24;
constexpr uint64_t kArrayBit = 32;
constexpr uint64_t kStateBits = 128;

// A two-level design whose `bus` net and `data` variable share one canonical
// range, so they must collapse onto a single VCD identifier code.
//
//   top          clk   : logic       1 bit  @0
//                data  : logic [7:0] 8 bits @8
//                bus   : logic [7:0] 8 bits @8   (alias of data)
//   top.sub      count : logic [3:0] 4 bits @16
//   top          rv    : real        64 bits @64
//                \\x.y  : logic       1 bit  @23  (escaped name with a dot)
//                st    : packed struct of two nibbles, 8 bits  @24
//                mem   : logic [3:0] [0:2] unpacked, 12 bits   @32
struct DesignImage {
  std::vector<uint8_t> bytes;

  DesignImage() {
    constexpr uint64_t scopeOffset = 176;
    constexpr uint64_t subScopeOffset = scopeOffset + 64;
    constexpr uint64_t objectOffset = subScopeOffset + 64;
    constexpr uint64_t clkOffset = objectOffset;
    constexpr uint64_t dataOffset = objectOffset + 96;
    constexpr uint64_t busOffset = objectOffset + 192;
    constexpr uint64_t countOffset = objectOffset + 288;
    constexpr uint64_t realOffset = objectOffset + 384;
    constexpr uint64_t escapedOffset = objectOffset + 480;
    constexpr uint64_t structOffset = objectOffset + 576;
    constexpr uint64_t arrayOffset = objectOffset + 672;
    constexpr uint64_t typeOffset = objectOffset + 768;
    constexpr uint64_t scalarType = typeOffset;
    constexpr uint64_t byteType = typeOffset + 80;
    constexpr uint64_t nibbleType = typeOffset + 160;
    constexpr uint64_t realType = typeOffset + 240;
    constexpr uint64_t structType = typeOffset + 320;
    // A struct's field records must be contiguous and in ordinal order.
    constexpr uint64_t field0Type = typeOffset + 400;
    constexpr uint64_t field1Type = typeOffset + 480;
    constexpr uint64_t arrayType = typeOffset + 560;
    constexpr uint64_t stringOffset = typeOffset + 640;

    // Records carry the full hierarchical path; VCD declares the leaf.
    const std::string strings = std::string(
        "top\0top.sub\0top.clk\0top.data\0top.bus\0top.sub.count\0top.rv\0top."
        "\\x.y \0top.st\0top.mem\0logic\0real\0pair\0hi\0lo\0nibbles\0"
        "shortreal\0string\0",
        130);
    // Name offsets stored in records are absolute image offsets.
    const uint64_t topName = stringOffset + 0;
    const uint64_t subName = stringOffset + 4;
    const uint64_t clkName = stringOffset + 12;
    const uint64_t dataName = stringOffset + 20;
    const uint64_t busName = stringOffset + 29;
    const uint64_t countName = stringOffset + 37;
    const uint64_t realName = stringOffset + 51;
    const uint64_t structName = stringOffset + 68;
    const uint64_t arrayName = stringOffset + 75;
    const uint64_t pairTypeName = stringOffset + 94;
    const uint64_t hiName = stringOffset + 99;
    const uint64_t loName = stringOffset + 102;
    const uint64_t nibblesTypeName = stringOffset + 105;
    const uint64_t escapedName = stringOffset + 58;
    const uint64_t logicName = stringOffset + 83;
    const uint64_t realTypeName = stringOffset + 89;

    // The index is read with byte-wise loads, but keeping it aligned mirrors
    // what the compiler emits.
    const uint64_t indexOffset = (stringOffset + strings.size() + 7) / 8 * 8;
    struct Entry {
      std::string name;
      uint64_t nameOffset;
      uint64_t record;
    };
    std::vector<Entry> index{
        {"top", topName, scopeOffset},
        {"top.sub", subName, subScopeOffset},
        {"top.clk", clkName, clkOffset},
        {"top.data", dataName, dataOffset},
        {"top.bus", busName, busOffset},
        {"top.sub.count", countName, countOffset},
        {"top.rv", realName, realOffset},
        {"top.\\x.y ", escapedName, escapedOffset},
        {"top.st", structName, structOffset},
        {"top.mem", arrayName, arrayOffset},
    };
    std::sort(index.begin(), index.end(),
              [](const Entry &left, const Entry &right) {
                uint64_t leftHash = nameHash(left.name);
                uint64_t rightHash = nameHash(right.name);
                if (leftHash != rightHash)
                  return leftHash < rightHash;
                return left.name < right.name;
              });

    bytes.assign(static_cast<size_t>(indexOffset + index.size() * 24), 0);
    std::memcpy(bytes.data(), "OBDSGN1\0", 8);
    put32(bytes, 8, TALOS_RT_VERSION);
    put32(bytes, 16, TALOS_RT_DESIGN_PROFILE_READ);
    put32(bytes, 20, TALOS_RT_DESIGN_DATABASE_HEADER_SIZE);
    put64(bytes, 24, bytes.size());
    put64(bytes, 40, scopeOffset);
    put64(bytes, 48, scopeOffset);
    put64(bytes, 56, 2);
    put64(bytes, 64, objectOffset);
    put64(bytes, 72, 8);
    put64(bytes, 80, typeOffset);
    put64(bytes, 88, 8);
    put64(bytes, 96, stringOffset);
    put64(bytes, 104, strings.size());
    put64(bytes, 112, indexOffset);
    put64(bytes, 120, index.size());
    put64(bytes, 128, stringOffset);
    put64(bytes, 144, stringOffset);
    put64(bytes, 160, stringOffset);

    // top: children are clk, data, bus, then the sub scope.
    put32(bytes, scopeOffset, TALOS_RT_DESIGN_RECORD_SCOPE);
    put32(bytes, scopeOffset + 4, TALOS_RT_DESIGN_CAP_ITERATE);
    put64(bytes, scopeOffset + 8, 1);
    put64(bytes, scopeOffset + 24, clkOffset);
    put64(bytes, scopeOffset + 40, topName);

    put32(bytes, subScopeOffset,
          designRecordKind(TALOS_RT_DESIGN_RECORD_SCOPE, vpiModule));
    put32(bytes, subScopeOffset + 4, TALOS_RT_DESIGN_CAP_ITERATE);
    put64(bytes, subScopeOffset + 8, 2);
    put64(bytes, subScopeOffset + 16, scopeOffset);
    put64(bytes, subScopeOffset + 24, countOffset);
    put64(bytes, subScopeOffset + 32, realOffset);
    put64(bytes, subScopeOffset + 40, subName);

    auto object = [&](uint64_t offset, uint32_t kind, uint64_t stableID,
                      uint64_t parent, uint64_t next, uint64_t name,
                      uint64_t type, uint64_t width, int64_t left,
                      int64_t right, uint64_t stateBit) {
      uint32_t vpiKind = kind == TALOS_RT_DESIGN_RECORD_NET ? vpiNet : vpiReg;
      put32(bytes, offset, designRecordKind(kind, vpiKind));
      put32(bytes, offset + 4, TALOS_RT_DESIGN_CAP_READ);
      put64(bytes, offset + 8, stableID);
      put64(bytes, offset + 16, parent);
      put64(bytes, offset + 24, next);
      put64(bytes, offset + 40, name);
      put64(bytes, offset + 48, type);
      put64(bytes, offset + 56, width);
      put64(bytes, offset + 64, static_cast<uint64_t>(left));
      put64(bytes, offset + 72, static_cast<uint64_t>(right));
      put64(bytes, offset + 80, stateBit);
    };
    object(clkOffset, TALOS_RT_DESIGN_RECORD_NET, 1, scopeOffset, dataOffset,
           clkName, scalarType, 1, 0, 0, kClkBit);
    object(dataOffset, TALOS_RT_DESIGN_RECORD_STORAGE, 2, scopeOffset,
           busOffset, dataName, byteType, 8, 7, 0, kDataBit);
    object(busOffset, TALOS_RT_DESIGN_RECORD_NET, 3, scopeOffset,
           subScopeOffset, busName, byteType, 8, 7, 0, kDataBit);
    object(countOffset, TALOS_RT_DESIGN_RECORD_STORAGE, 4, subScopeOffset, 0,
           countName, nibbleType, 4, 3, 0, kCountBit);
    object(realOffset, TALOS_RT_DESIGN_RECORD_STORAGE, 5, scopeOffset,
           escapedOffset, realName, realType, 64, 63, 0, kRealBit);
    object(escapedOffset, TALOS_RT_DESIGN_RECORD_STORAGE, 6, scopeOffset,
           structOffset, escapedName, scalarType, 1, 0, 0, 23);
    object(structOffset, TALOS_RT_DESIGN_RECORD_STORAGE, 7, scopeOffset,
           arrayOffset, structName, structType, 8, 7, 0, kStructBit);
    // An unpacked array's declared range enumerates elements, so its bounds
    // deliberately disagree with its 12-bit extent.
    object(arrayOffset, TALOS_RT_DESIGN_RECORD_STORAGE, 8, scopeOffset, 0,
           arrayName, arrayType, 12, 0, 2, kArrayBit);

    auto type = [&](uint64_t offset, uint64_t width, int64_t left) {
      put32(bytes, offset, TALOS_RT_DESIGN_RECORD_TYPE);
      put32(bytes, offset + 4,
            TALOS_RT_DESIGN_TYPE_SCALAR |
                ((TALOS_RT_DESIGN_TYPE_FOUR_STATE | TALOS_RT_DESIGN_TYPE_PACKED)
                 << 8));
      put64(bytes, offset + 8, width);
      put64(bytes, offset + 16, static_cast<uint64_t>(left));
      put64(bytes, offset + 72, logicName);
    };
    type(scalarType, 1, 0);
    type(byteType, 8, 7);
    type(nibbleType, 4, 3);
    // A real is a scalar type whose only distinguishing mark is its name.
    put32(bytes, realType, TALOS_RT_DESIGN_RECORD_TYPE);
    put32(bytes, realType + 4, TALOS_RT_DESIGN_TYPE_SCALAR);
    put64(bytes, realType + 8, 64);
    put64(bytes, realType + 16, 63);
    put64(bytes, realType + 72, realTypeName);

    // A packed struct of two four-state nibbles.
    put32(bytes, structType, TALOS_RT_DESIGN_RECORD_TYPE);
    put32(bytes, structType + 4,
          TALOS_RT_DESIGN_TYPE_STRUCT |
              ((TALOS_RT_DESIGN_TYPE_FOUR_STATE | TALOS_RT_DESIGN_TYPE_PACKED)
               << 8));
    put64(bytes, structType + 8, 8);
    put64(bytes, structType + 16, 7);
    put64(bytes, structType + 40, field0Type);
    put64(bytes, structType + 48, 2);
    put64(bytes, structType + 72, pairTypeName);
    auto field = [&](uint64_t offset, uint64_t ordinal, uint64_t packedOffset,
                     uint64_t name) {
      put32(bytes, offset, TALOS_RT_DESIGN_RECORD_TYPE);
      put32(bytes, offset + 4,
            TALOS_RT_DESIGN_TYPE_FIELD |
                (TALOS_RT_DESIGN_TYPE_FOUR_STATE << 8));
      put64(bytes, offset + 8, 4);
      put64(bytes, offset + 16, 3);
      put64(bytes, offset + 32, nibbleType);
      put64(bytes, offset + 56, ordinal);
      put64(bytes, offset + 64, packedOffset);
      put64(bytes, offset + 72, name);
    };
    field(field0Type, 0, 4, hiName);
    field(field1Type, 1, 0, loName);

    // An unpacked array of three nibbles: three elements, twelve bits.
    put32(bytes, arrayType, TALOS_RT_DESIGN_RECORD_TYPE);
    put32(bytes, arrayType + 4,
          TALOS_RT_DESIGN_TYPE_ARRAY | (TALOS_RT_DESIGN_TYPE_FOUR_STATE << 8));
    put64(bytes, arrayType + 8, 12);
    put64(bytes, arrayType + 16, 0);
    put64(bytes, arrayType + 24, 2);
    put64(bytes, arrayType + 32, nibbleType);
    put64(bytes, arrayType + 72, nibblesTypeName);

    std::memcpy(bytes.data() + stringOffset, strings.data(), strings.size());
    for (size_t entry = 0; entry != index.size(); ++entry) {
      put64(bytes, indexOffset + entry * 24, nameHash(index[entry].name));
      put64(bytes, indexOffset + entry * 24 + 8, index[entry].nameOffset);
      put64(bytes, indexOffset + entry * 24 + 16, index[entry].record);
    }
    put64(bytes, 32, imageChecksum(bytes));
  }

  void makeRealObjectAString() {
    constexpr uint64_t scopeOffset = 176;
    constexpr uint64_t objectOffset = scopeOffset + 2 * 64;
    constexpr uint64_t realOffset = objectOffset + 384;
    constexpr uint64_t typeOffset = objectOffset + 768;
    constexpr uint64_t realType = typeOffset + 240;
    constexpr uint64_t stringOffset = typeOffset + 640;
    constexpr uint64_t stringTypeName = stringOffset + 123;
    put32(bytes, realOffset,
          designRecordKind(TALOS_RT_DESIGN_RECORD_STORAGE, vpiStringVar));
    put64(bytes, realType + 72, stringTypeName);
    put64(bytes, 32, imageChecksum(bytes));
  }

  void makeStructFieldNamedString() {
    constexpr uint64_t scopeOffset = 176;
    constexpr uint64_t objectOffset = scopeOffset + 2 * 64;
    constexpr uint64_t typeOffset = objectOffset + 768;
    constexpr uint64_t field0Type = typeOffset + 400;
    constexpr uint64_t stringOffset = typeOffset + 640;
    constexpr uint64_t stringName = stringOffset + 123;
    put64(bytes, field0Type + 72, stringName);
    put64(bytes, 32, imageChecksum(bytes));
  }
};

struct Fixture {
  DesignImage image;
  talos_rt_execution_descriptor_v1 execution{};
  talos_rt_context *context = nullptr;
  std::string path;
  std::filesystem::path directory;

  Fixture() {
    execution.version = TALOS_RT_VERSION;
    execution.flags = TALOS_RT_EXECUTION_HAS_DESIGN_DATABASE |
                      TALOS_RT_EXECUTION_WAVEFORM_METADATA;
    execution.design_database = image.bytes.data();
    execution.design_database_size = image.bytes.size();
    execution.state_bit_count = kStateBits;
    static std::atomic<uint64_t> sequence{0};
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    do {
      directory = std::filesystem::temp_directory_path() /
                  ("talos-vcd-" + std::to_string(stamp) + "-" +
                   std::to_string(sequence.fetch_add(1)));
    } while (!std::filesystem::create_directory(directory));
    path = (directory / "dump.vcd").string();
  }

  ~Fixture() {
    if (context)
      talos_rt_v1_context_destroy(context);
    std::remove(path.c_str());
    std::error_code error;
    std::filesystem::remove(directory, error);
  }

  talos_rt_status create() {
    return talos_rt_v1_context_create_for_design(&execution, &context);
  }

  void setBits(uint64_t bit, uint64_t width, uint64_t value, uint64_t unknown) {
    for (uint64_t index = 0; index != width; ++index) {
      uint64_t absolute = bit + index;
      uint64_t mask = uint64_t{1} << (absolute % 64);
      if ((value >> index) & 1)
        context->stateValue[absolute / 64] |= mask;
      else
        context->stateValue[absolute / 64] &= ~mask;
      if ((unknown >> index) & 1)
        context->stateUnknown[absolute / 64] |= mask;
      else
        context->stateUnknown[absolute / 64] &= ~mask;
    }
  }

  // Close the slot that is ending and move to the next one, mirroring what the
  // scheduler does around each time advance.
  void advanceTo(uint64_t time) {
    ASSERT_EQ(talos_rt_dump_slot_unlocked(context), TALOS_RT_OK);
    context->schedulerTime = time;
  }

  std::string read() {
    talos_rt_v1_dump_close(context);
    std::ifstream stream(path, std::ios::binary);
    std::ostringstream text;
    text << stream.rdbuf();
    return text.str();
  }

  talos_rt_status openDump() {
    return talos_rt_v1_dump_open(
        context, reinterpret_cast<const uint8_t *>(path.data()), path.size());
  }
};

size_t countOccurrences(const std::string &text, const std::string &needle) {
  size_t count = 0;
  for (size_t at = text.find(needle); at != std::string::npos;
       at = text.find(needle, at + needle.size()))
    ++count;
  return count;
}

std::string identifierFor(const std::string &text, const std::string &name) {
  // "$var reg 8 " <code> " data [7:0] $end"
  std::istringstream lines(text);
  std::string line;
  while (std::getline(lines, line)) {
    if (line.rfind("$var ", 0) != 0)
      continue;
    std::istringstream fields(line);
    std::string keyword, kind, width, code, variable;
    fields >> keyword >> kind >> width >> code >> variable;
    if (variable == name)
      return code;
  }
  return {};
}

// Every value record naming `code`, in order, taken from the body of the dump.
// A scalar record is "<char><code>"; a vector record is "b<bits> <code>".
std::vector<std::string> valueRecords(const std::string &text,
                                      const std::string &code) {
  std::vector<std::string> records;
  size_t body = text.find("$enddefinitions $end");
  if (body == std::string::npos)
    return records;
  std::istringstream lines(text.substr(body));
  std::string line;
  while (std::getline(lines, line)) {
    if (line.empty() || line[0] == '$' || line[0] == '#')
      continue;
    if (line[0] == 'b' || line[0] == 'r') {
      size_t space = line.rfind(' ');
      if (space != std::string::npos && line.substr(space + 1) == code)
        records.push_back(line.substr(0, space));
      continue;
    }
    if (line.substr(1) == code)
      records.push_back(line.substr(0, 1));
  }
  return records;
}

// Names declared in the header, in order, that use `code`.
std::vector<std::string> namesUsingCode(const std::string &text,
                                        const std::string &code) {
  std::vector<std::string> names;
  std::istringstream lines(text);
  std::string line;
  while (std::getline(lines, line)) {
    if (line.rfind("$var ", 0) != 0)
      continue;
    std::istringstream fields(line);
    std::string keyword, kind, width, entry, variable;
    fields >> keyword >> kind >> width >> entry >> variable;
    if (entry == code)
      names.push_back(variable);
  }
  return names;
}

TEST(VCD, HeaderDeclaresHierarchy) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_timescale(fixture.context, -9), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_NE(text.find("$timescale\n\t1ns\n$end\n"), std::string::npos);
  EXPECT_NE(text.find("$scope module top $end"), std::string::npos);
  EXPECT_NE(text.find("$scope module sub $end"), std::string::npos);
  EXPECT_EQ(countOccurrences(text, "$upscope $end"), 2u);
  EXPECT_NE(text.find("$enddefinitions $end"), std::string::npos);
  EXPECT_NE(text.find("$var wire 1 "), std::string::npos);
  EXPECT_NE(text.find("$var reg 4 "), std::string::npos);
}

// IEEE 1800-2023 21.7: a generated periodic loop ends its slots in the dump
// only once something is selected; a file alone never dumps. A loop built
// without postponed hooks keeps returning the calendar to the runtime.
TEST(VCD, PostponedSlotHookFollowsDumpSelections) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  talos_rt_context *context = fixture.context;
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  EXPECT_EQ(context->postponedSlotHooks & kDumpSlotHook, 0);
  ASSERT_EQ(talos_rt_v1_dump_vars(context, 0, nullptr, 0), TALOS_RT_OK);
  EXPECT_NE(context->postponedSlotHooks & kDumpSlotHook, 0);

  talos_rt_native_schedule_plan plan{};
  plan.flags = TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL |
               TALOS_RT_NATIVE_SCHEDULE_SHARED_PERIODIC;
  context->nativeSchedulePlan = &plan;
  {
    ContextMutexLock lock(context);
    NativeAOTContextScope aot(context);
    NativeAOTMutexScope mutex(context);
    talos_rt_native_periodic_control_v1 control{};
    EXPECT_EQ(talos_rt_v1_scheduler_postponed_slot_aot(context),
              TALOS_RT_INVALID_LIFECYCLE);
    EXPECT_EQ(talos_rt_v1_scheduler_drain_periodic_aot(context, &control),
              TALOS_RT_TIER_UNAVAILABLE);
    plan.flags |= TALOS_RT_NATIVE_SCHEDULE_POSTPONED_HOOKS;
    EXPECT_EQ(talos_rt_v1_scheduler_drain_periodic_aot(context, &control),
              TALOS_RT_OK);
    EXPECT_EQ(talos_rt_v1_scheduler_postponed_slot_aot(context), TALOS_RT_OK);
  }
  context->nativeSchedulePlan = nullptr;
  std::string text = fixture.read();
  // Closing the file disarms the hook; the drain wrote the selecting slot.
  EXPECT_EQ(context->postponedSlotHooks & kDumpSlotHook, 0);
  EXPECT_EQ(countOccurrences(text, "#0\n$dumpvars\n"), 1u);
}

TEST(VCD, TimescaleFallsBackToTheDesignDefault) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  EXPECT_NE(fixture.read().find("$timescale\n\t1ns\n$end\n"),
            std::string::npos);
}

TEST(VCD, TimescaleUsesAScaledUnitWhenThePrecisionIsNotAPowerOfAThousand) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_timescale(fixture.context, -10), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  EXPECT_NE(fixture.read().find("$timescale\n\t100ps\n$end\n"),
            std::string::npos);
}

TEST(VCD, TimescaleAcceptsThePositiveLegalExponentRange) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_timescale(fixture.context, 2), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  EXPECT_NE(fixture.read().find("$timescale\n\t100s\n$end\n"),
            std::string::npos);
}

//===----------------------------------------------------------------------===//
// Aliasing
//
// `data` and `bus` name the identical canonical four-state range, so IEEE 1364
// permits them to share one identifier code. Sharing must be complete: one
// declaration per name, but a single traced range, a single initial value, and
// a single record per change.
//===----------------------------------------------------------------------===//

TEST(VCD, AliasesShareOneIdentifierCode) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  std::string data = identifierFor(text, "data");
  std::string bus = identifierFor(text, "bus");
  std::string clk = identifierFor(text, "clk");
  std::string count = identifierFor(text, "count");
  ASSERT_FALSE(data.empty());
  EXPECT_EQ(data, bus);
  // Variables over distinct ranges must stay distinct.
  EXPECT_NE(data, clk);
  EXPECT_NE(data, count);
  EXPECT_NE(clk, count);
}

#if (defined(__unix__) || defined(__APPLE__)) && !defined(__EMSCRIPTEN__)
// Once $dumpflush returns, a reader holding that file descriptor must also see
// later samples. The prefix includes values recorded before the signals split.
TEST(VCD, CompactFlushRestoresIndependentHistories) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  for (unsigned i = 0; i < 5; ++i) {
    f.setBits(kDataBit, 8, i, 0);
    f.setBits(kStructBit, 8, i, 0);
    f.advanceTo(i + 1);
  }
  ASSERT_EQ(talos_rt_v1_dump_flush(f.context), TALOS_RT_OK);
  std::ifstream reader(f.path);
  ASSERT_TRUE(reader);
  f.setBits(kDataBit, 8, 7, 3);
  f.advanceTo(6);
  ASSERT_EQ(talos_rt_v1_dump_all(f.context), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_control(f.context, 0), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_control(f.context, 1), TALOS_RT_OK);
  auto closed = f.read();
  std::ostringstream observed;
  observed << reader.rdbuf();
  EXPECT_EQ(observed.str(), closed);
  std::string data = identifierFor(closed, "data");
  EXPECT_EQ(data, identifierFor(closed, "bus"));
  EXPECT_NE(data, identifierFor(closed, "st"));
  EXPECT_EQ(valueRecords(closed, data),
            (std::vector<std::string>{"b0", "b1", "b10", "b11", "b100", "b1zz",
                                      "b1zz", "bx", "b1zz"}));
}

TEST(VCD, CompactSplitKeepsBothPreviousValuesAndTimestamps) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.setBits(kDataBit, 8, 0, 0);
  f.setBits(kStructBit, 8, 0, 0);
  double real = 1.5;
  uint64_t bits;
  std::memcpy(&bits, &real, sizeof(bits));
  f.setBits(kRealBit, 64, bits, 0);
  f.advanceTo(130);
  f.setBits(kDataBit, 8, 2, 3);
  f.setBits(kStructBit, 8, 2, 3);
  f.advanceTo(UINT64_MAX - 1);
  f.setBits(kStructBit, 8, 3, 3);
  // The runtime can observe a second sample with the same scheduler time.
  f.advanceTo(UINT64_MAX - 1);
  f.setBits(kDataBit, 8, 4, 0);
  auto text = f.read();
  auto data = identifierFor(text, "data"), other = identifierFor(text, "st");
  EXPECT_NE(data, other);
  EXPECT_EQ(valueRecords(text, data),
            (std::vector<std::string>{"b0", "b0zx", "b100"}));
  EXPECT_EQ(valueRecords(text, other),
            (std::vector<std::string>{"b0", "b0zx", "b0zz"}));
  EXPECT_EQ(valueRecords(text, identifierFor(text, "rv")),
            (std::vector<std::string>{"r1.5"}));
  EXPECT_EQ(countOccurrences(text, "#18446744073709551614\n"), 1u);
  EXPECT_EQ(countOccurrences(text, "#130\n"), 1u);
}

TEST(VCD, LateLimitDoesNotExpandAnAlreadyPublishedCompactPrefix) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.setBits(kDataBit, 8, 1, 0);
  f.setBits(kStructBit, 8, 1, 0);
  f.advanceTo(1);
  auto size = std::filesystem::file_size(f.path);
  ASSERT_GT(size, 0u);
  ASSERT_EQ(talos_rt_v1_dump_limit(f.context, size + 2), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_flush(f.context), TALOS_RT_OK);
  EXPECT_EQ(std::filesystem::file_size(f.path), size);
  f.setBits(kDataBit, 8, 9, 0);
  f.advanceTo(200);
  auto text = f.read();
  EXPECT_EQ(text.find("$comment dump limit"), size);
  EXPECT_EQ(identifierFor(text, "st"), identifierFor(text, "data"));
}

TEST(VCD, LateLimitKeepsCompleteRecordsFromTheSplittingSample) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  for (std::string_view name : {"top.clk", "top.data", "top.st"})
    ASSERT_EQ(talos_rt_v1_dump_vars(
                  f.context, 0, reinterpret_cast<const uint8_t *>(name.data()),
                  name.size()),
              TALOS_RT_OK);
  f.setBits(kClkBit, 1, 0, 0);
  f.setBits(kDataBit, 8, 0, 0);
  f.setBits(kStructBit, 8, 0, 0);
  f.advanceTo(2);
  // Five bytes duplicate the initial vector. The timestamp and the scalar
  // use another six. The eight-bit vector in this sample cannot fit.
  auto limit = std::filesystem::file_size(f.path) + 11;
  ASSERT_EQ(talos_rt_v1_dump_limit(f.context, limit), TALOS_RT_OK);
  f.setBits(kClkBit, 1, 1, 0);
  f.setBits(kStructBit, 8, 255, 0);
  f.advanceTo(3);
  auto text = f.read();
  EXPECT_EQ(text.find("$comment dump limit"), limit);
  EXPECT_NE(text.find("#2\n1" + identifierFor(text, "clk") + "\n$comment"),
            std::string::npos);
  EXPECT_EQ(valueRecords(text, identifierFor(text, "st")),
            (std::vector<std::string>{"b0"}));
  EXPECT_NE(identifierFor(text, "data"), identifierFor(text, "st"));
}

TEST(VCD, CompactCheckpointHistorySurvivesALaterSplit) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.setBits(kArrayBit, 12, 0, 0);
  f.advanceTo(10);
  f.setBits(kArrayBit, 12, 0x555, 0);
  ASSERT_EQ(talos_rt_v1_dump_all(f.context), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_control(f.context, 0), TALOS_RT_OK);
  f.advanceTo(20);
  f.setBits(kArrayBit + 8, 4, 15, 0);
  ASSERT_EQ(talos_rt_v1_dump_control(f.context, 1), TALOS_RT_OK);
  auto text = f.read();
  auto common = identifierFor(text, "mem[0]");
  auto split = identifierFor(text, "mem[2]");
  ASSERT_FALSE(common.empty());
  ASSERT_FALSE(split.empty());
  EXPECT_EQ(common, identifierFor(text, "mem[1]"));
  EXPECT_NE(common, split);
  EXPECT_EQ(valueRecords(text, common),
            (std::vector<std::string>{"b0", "b101", "bx", "b101"}));
  EXPECT_EQ(valueRecords(text, split),
            (std::vector<std::string>{"b0", "b101", "bx", "b1111"}));
  EXPECT_EQ(countOccurrences(text, "#10\n"), 1u);
  EXPECT_EQ(countOccurrences(text, "#20\n"), 1u);
}

TEST(VCD, HardLinkedOutputPreservesBothNamesAndIndependentChanges) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  std::ofstream(f.path).close();
  auto linked = f.directory / "linked.vcd";
  std::filesystem::create_hard_link(f.path, linked);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.setBits(kDataBit, 8, 4, 0);
  f.setBits(kStructBit, 8, 4, 0);
  f.advanceTo(2);
  f.setBits(kStructBit, 8, 5, 0);
  auto text = f.read();
  EXPECT_TRUE(std::filesystem::equivalent(f.path, linked));
  EXPECT_EQ(valueRecords(text, identifierFor(text, "data")),
            (std::vector<std::string>{"b100"}));
  EXPECT_EQ(valueRecords(text, identifierFor(text, "st")),
            (std::vector<std::string>{"b100", "b101"}));
  std::filesystem::remove(linked);
}

TEST(VCD, ReplayLeavesARenamedDestinationAlone) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.advanceTo(1);
  auto original = f.directory / "original.vcd";
  std::filesystem::rename(f.path, original);
  std::ofstream(f.path) << "replacement";
  EXPECT_EQ(talos_rt_v1_dump_flush(f.context), TALOS_RT_IO_ERROR);
  EXPECT_EQ(talos_rt_v1_dump_close(f.context), TALOS_RT_IO_ERROR);
  std::string contents;
  std::ifstream replacement(f.path);
  std::getline(replacement, contents);
  EXPECT_EQ(contents, "replacement");
  EXPECT_GT(std::filesystem::file_size(original), 0u);
  std::filesystem::remove(original);
}

#if defined(__linux__)
TEST(VCD, LimitCommentWriteFailureReachesTheCaller) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  std::filesystem::create_symlink("/dev/full", f.path);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  EXPECT_EQ(talos_rt_v1_dump_limit(f.context, 0), TALOS_RT_IO_ERROR);
  EXPECT_EQ(talos_rt_v1_dump_flush(f.context), TALOS_RT_IO_ERROR);
  EXPECT_EQ(talos_rt_v1_dump_close(f.context), TALOS_RT_IO_ERROR);
  // The next $dumpfile before the first sample starts a new output session.
  ASSERT_TRUE(std::filesystem::remove(f.path));
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  EXPECT_NE(f.read().find("$comment dump limit"), std::string::npos);
}

TEST(VCD, SnapshotPreservesExistingFileAttributes) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  std::ofstream(f.path).close();
  constexpr char attribute[] = "user.talos-vcd-test";
  int result = ::setxattr(f.path.c_str(), attribute, "vcd", 3, 0);
  if (result != 0 && errno == ENOTSUP)
    GTEST_SKIP() << "filesystem does not support extended attributes";
  ASSERT_EQ(result, 0);
  char value[3];
  ASSERT_EQ(::getxattr(f.path.c_str(), attribute, value, sizeof(value)), 3);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.advanceTo(1);
  EXPECT_FALSE(f.read().empty());
  ASSERT_EQ(::getxattr(f.path.c_str(), attribute, value, sizeof(value)), 3);
  EXPECT_EQ(std::string_view(value, 3), "vcd");
}

TEST(VCD, SnapshotPreservesTheNoDumpInodeFlag) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  std::unique_ptr<std::FILE, decltype(&std::fclose)> file(
      std::fopen(f.path.c_str(), "w+b"), &std::fclose);
  ASSERT_TRUE(file);
  unsigned long flags = 0;
  if (::ioctl(fileno(file.get()), FS_IOC_GETFLAGS, &flags) != 0)
    GTEST_SKIP() << "filesystem does not expose inode flags";
  flags |= FS_NODUMP_FL;
  if (::ioctl(fileno(file.get()), FS_IOC_SETFLAGS, &flags) != 0)
    GTEST_SKIP() << "filesystem does not allow setting the nodump flag";
  file.reset();
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(f.context, 0, nullptr, 0), TALOS_RT_OK);
  f.advanceTo(1);
  EXPECT_FALSE(f.read().empty());
  file.reset(std::fopen(f.path.c_str(), "rb"));
  ASSERT_TRUE(file);
  ASSERT_EQ(::ioctl(fileno(file.get()), FS_IOC_GETFLAGS, &flags), 0);
  EXPECT_NE(flags & FS_NODUMP_FL, 0u);
}
#endif

TEST(VCD, CompactCaptureHonorsAnExistingZeroLimit) {
  Fixture f;
  ASSERT_EQ(f.create(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_limit(f.context, 0), TALOS_RT_OK);
  ASSERT_EQ(f.openDump(), TALOS_RT_OK);
  auto text = f.read();
  EXPECT_EQ(text.find("$var "), std::string::npos);
  EXPECT_NE(text.find("$comment"), std::string::npos);
}
#endif

TEST(VCD, AliasesAreEachDeclaredWithTheirOwnName) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kStructBit, 8, 1, 0);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  std::string data = identifierFor(text, "data");
  ASSERT_FALSE(data.empty());
  // Both names remain visible to a waveform viewer, with their own kinds.
  EXPECT_EQ(namesUsingCode(text, data),
            (std::vector<std::string>{"data", "bus"}));
  EXPECT_NE(text.find("$var reg 8 " + data + " data [7:0] $end"),
            std::string::npos);
  EXPECT_NE(text.find("$var wire 8 " + data + " bus [7:0] $end"),
            std::string::npos);
}

TEST(VCD, AliasedRangeIsDumpedOnlyOnceInitially) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kDataBit, 8, 0xa5, 0);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  std::string data = identifierFor(text, "data");
  EXPECT_EQ(valueRecords(text, data), (std::vector<std::string>{"b10100101"}));
}

TEST(VCD, AliasedRangeProducesOneRecordPerChange) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kDataBit, 8, 0x00, 0);
  fixture.advanceTo(10);
  fixture.setBits(kDataBit, 8, 0x03, 0);
  fixture.advanceTo(20);
  fixture.setBits(kDataBit, 8, 0x0c, 0);
  fixture.advanceTo(30);
  std::string text = fixture.read();

  std::string data = identifierFor(text, "data");
  // Three settled values, three records -- not six.
  EXPECT_EQ(valueRecords(text, data),
            (std::vector<std::string>{"b0", "b11", "b1100"}));
}

TEST(VCD, AliasedRangeIsDifferencedOnce) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  // Eight declared objects, one of which expands into three array elements:
  // ten declarations over nine distinct ranges, since `data` and `bus` share.
  ASSERT_NE(fixture.context->vcdState, nullptr);
  EXPECT_EQ(countOccurrences(text, "$var "), 10u);
  EXPECT_EQ(talos_rt_dump_traced_range_count(fixture.context), 9u);
}

// A real is stored as an IEEE-754 bit pattern in the same planes as everything
// else. Dumping it as a bit vector would be silently wrong, so it must be
// declared `$var real` and emitted as an `r` record.
TEST(VCD, RealsAreDumpedAsNumbersNotBitPatterns) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  uint64_t bits = 0;
  double value = 1.5;
  std::memcpy(&bits, &value, sizeof(bits));
  fixture.setBits(kRealBit, 64, bits, 0);
  fixture.advanceTo(10);
  value = -2.25;
  std::memcpy(&bits, &value, sizeof(bits));
  fixture.setBits(kRealBit, 64, bits, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  std::string rv = identifierFor(text, "rv");
  ASSERT_FALSE(rv.empty());
  // No bit range is declared for a real.
  EXPECT_NE(text.find("$var real 64 " + rv + " rv $end"), std::string::npos);
  EXPECT_EQ(valueRecords(text, rv),
            (std::vector<std::string>{"r1.5", "r-2.25"}));
}

TEST(VCD, ShortRealsArePromotedAndDumpedAsNumbers) {
  Fixture fixture;
  constexpr uint64_t realObject = 176 + 2 * 64 + 4 * 96;
  constexpr uint64_t realType = 176 + 2 * 64 + 8 * 96 + 3 * 80;
  constexpr uint64_t stringOffset = 176 + 2 * 64 + 8 * 96 + 8 * 80;
  put32(fixture.image.bytes, realObject,
        designRecordKind(TALOS_RT_DESIGN_RECORD_STORAGE, vpiShortRealVar));
  put64(fixture.image.bytes, realObject + 56, 32);
  put64(fixture.image.bytes, realObject + 64, 31);
  put64(fixture.image.bytes, realType + 8, 32);
  put64(fixture.image.bytes, realType + 16, 31);
  put64(fixture.image.bytes, realType + 72, stringOffset + 113);
  put64(fixture.image.bytes, 32, imageChecksum(fixture.image.bytes));

  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  float value = 1.5f;
  uint32_t bits = 0;
  std::memcpy(&bits, &value, sizeof(bits));
  fixture.setBits(kRealBit, 32, bits, 0);
  fixture.advanceTo(10);
  value = -2.25f;
  std::memcpy(&bits, &value, sizeof(bits));
  fixture.setBits(kRealBit, 32, bits, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  std::string rv = identifierFor(text, "rv");
  ASSERT_FALSE(rv.empty());
  EXPECT_NE(text.find("$var real 32 " + rv + " rv $end"), std::string::npos);
  EXPECT_EQ(valueRecords(text, rv),
            (std::vector<std::string>{"r1.5", "r-2.25"}));
}

TEST(VCD, RealsAreNotCheckpointedAsXByDumpOff) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  ASSERT_EQ(talos_rt_v1_dump_control(fixture.context, 0), TALOS_RT_OK);
  std::string text = fixture.read();

  std::string rv = identifierFor(text, "rv");
  size_t off = text.find("$dumpoff\n");
  ASSERT_NE(off, std::string::npos);
  // VCD has no unknown encoding for a real.
  EXPECT_EQ(text.find("bx " + rv, off), std::string::npos);
  EXPECT_EQ(text.find("x" + rv, off), std::string::npos);
}

// A packed struct occupies one contiguous canonical range, so it is traced and
// emitted as a single vector whose declared bounds match its bit extent.
TEST(VCD, PackedStructsAreDumpedAsOneVector) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  // hi = 1, lo = 2 across the two nibbles.
  fixture.setBits(kStructBit, 8, 0x12, 0);
  fixture.advanceTo(10);
  fixture.setBits(kStructBit, 8, 0x24, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  std::string st = identifierFor(text, "st");
  ASSERT_FALSE(st.empty());
  EXPECT_NE(text.find("$var reg 8 " + st + " st [7:0] $end"),
            std::string::npos);
  EXPECT_EQ(valueRecords(text, st),
            (std::vector<std::string>{"b10010", "b100100"}));
}

// A struct field changing must move the whole traced range exactly once, not
// once per field.
TEST(VCD, PackedStructEmitsOneRecordWhenAnyFieldChanges) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kStructBit, 8, 0x00, 0);
  fixture.advanceTo(10);
  // Only the high nibble moves.
  fixture.setBits(kStructBit + 4, 4, 0x3, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  std::string st = identifierFor(text, "st");
  EXPECT_EQ(valueRecords(text, st),
            (std::vector<std::string>{"b0", "b110000"}));
}

// An unpacked array is not a value: each element is an independent signal, so
// it is declared per element the way a waveform viewer renders an array. The
// declared range on each element describes its bits, never the element bounds.
TEST(VCD, UnpackedArraysAreExpandedPerElement) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kArrayBit + 4, 4, 1, 0);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  for (const char *element : {"mem[0]", "mem[1]", "mem[2]"}) {
    std::string code = identifierFor(text, element);
    ASSERT_FALSE(code.empty()) << element;
    EXPECT_NE(text.find("$var reg 4 " + code + " " + element + " [3:0] $end"),
              std::string::npos)
        << element;
  }
  // Neither the smashed vector nor the element bounds survive.
  EXPECT_EQ(text.find(" mem [11:0] $end"), std::string::npos);
  EXPECT_EQ(text.find(" mem [0:2] $end"), std::string::npos);
  // The first two elements have different sampled values.
  EXPECT_NE(identifierFor(text, "mem[0]"), identifierFor(text, "mem[1]"));
}

// Element ordinal zero occupies the lowest canonical bits and carries the
// leftmost declared index, so values land on the element that was written.
TEST(VCD, UnpackedArrayElementsAreDifferencedIndependently) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  // mem[0] = 0, mem[1] = 5, mem[2] = 0.
  fixture.setBits(kArrayBit, 12, 0x050, 0);
  fixture.advanceTo(10);
  // Only mem[2] moves.
  fixture.setBits(kArrayBit + 8, 4, 0x3, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  EXPECT_EQ(valueRecords(text, identifierFor(text, "mem[0]")),
            (std::vector<std::string>{"b0"}));
  EXPECT_EQ(valueRecords(text, identifierFor(text, "mem[1]")),
            (std::vector<std::string>{"b101"}));
  // The untouched elements contribute no second record.
  EXPECT_EQ(valueRecords(text, identifierFor(text, "mem[2]")),
            (std::vector<std::string>{"b0", "b11"}));
}

// VCD has no aggregate form, so an array too large to expand is left out
// entirely. Emitting it as one wide vector would be well-formed but would
// present three independent signals as a single value.
TEST(VCD, OversizedUnpackedArraysAreOmittedNotSmashed) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(setTestEnvironment("TALOS_RT_DUMP_MAX_ARRAY", "2"), 0);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(unsetTestEnvironment("TALOS_RT_DUMP_MAX_ARRAY"), 0);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  // The three-element array exceeds the limit and appears in no form.
  EXPECT_TRUE(identifierFor(text, "mem").empty());
  EXPECT_TRUE(identifierFor(text, "mem[0]").empty());
  EXPECT_EQ(text.find(" mem "), std::string::npos);
  // Everything else is still traced.
  EXPECT_FALSE(identifierFor(text, "clk").empty());
  EXPECT_FALSE(identifierFor(text, "st").empty());
  EXPECT_EQ(talos_rt_dump_traced_range_count(fixture.context), 6u);
}

// An escaped identifier may contain a dot, so the leaf name cannot be found by
// splitting the hierarchical path on its last separator.
TEST(VCD, EscapedNamesContainingDotsKeepTheirWholeLeaf) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_NE(text.find("\\x.y "), std::string::npos);
  // The trailing fragment of the escaped name must not appear on its own.
  EXPECT_EQ(text.find(" y $end"), std::string::npos);
}

TEST(VCD, SelectingOnlyOneAliasStillTracesTheSharedRange) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 1, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kDataBit, 8, 0x01, 0);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  std::string data = identifierFor(text, "data");
  ASSERT_FALSE(data.empty());
  EXPECT_EQ(identifierFor(text, "bus"), data);
  EXPECT_EQ(valueRecords(text, data), (std::vector<std::string>{"b1"}));
}

TEST(VCD, InitialValuesAreDumpedOnceAtTheSelectingSlot) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 1, 0);
  fixture.setBits(kDataBit, 8, 0xa5, 0);
  fixture.advanceTo(5);
  std::string text = fixture.read();

  size_t dumpvars = text.find("$dumpvars\n");
  ASSERT_NE(dumpvars, std::string::npos);
  EXPECT_LT(text.find("#0\n"), dumpvars);
  std::string clk = identifierFor(text, "clk");
  std::string data = identifierFor(text, "data");
  EXPECT_NE(text.find("1" + clk + "\n", dumpvars), std::string::npos);
  EXPECT_NE(text.find("b10100101 " + data + "\n", dumpvars), std::string::npos);
}

TEST(VCD, OnlyChangedVariablesAreEmittedPerSlot) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  // Uninitialized canonical state is X, so drive known values into the slot
  // that carries the initial section.
  fixture.setBits(kClkBit, 1, 0, 0);
  fixture.setBits(kDataBit, 8, 0, 0);
  fixture.setBits(kCountBit, 4, 0, 0);
  fixture.advanceTo(10);

  // Only `clk` moves in this slot.
  fixture.setBits(kClkBit, 1, 1, 0);
  fixture.advanceTo(20);
  // Nothing moves.
  fixture.advanceTo(30);
  // `count` moves to X.
  fixture.setBits(kCountBit, 4, 0, 0xf);
  fixture.advanceTo(40);
  std::string text = fixture.read();

  std::string clk = identifierFor(text, "clk");
  std::string count = identifierFor(text, "count");
  size_t body = text.find("$enddefinitions $end");
  ASSERT_NE(body, std::string::npos);

  EXPECT_NE(text.find("#10\n1" + clk, body), std::string::npos);
  // A slot with no change produces no time marker at all.
  EXPECT_EQ(text.find("#20\n"), std::string::npos);
  EXPECT_NE(text.find("#30\nbx " + count, body), std::string::npos);
  // `data` never moved, so it appears only in the initial section.
  std::string data = identifierFor(text, "data");
  EXPECT_EQ(valueRecords(text, data), (std::vector<std::string>{"b0"}));
}

TEST(VCD, VectorsDropRedundantLeadingCharacters) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  fixture.setBits(kDataBit, 8, 0x05, 0);
  fixture.advanceTo(20);
  fixture.setBits(kDataBit, 8, 0x00, 0xff);
  fixture.advanceTo(30);
  fixture.setBits(kDataBit, 8, 0x80, 0);
  fixture.advanceTo(40);
  std::string text = fixture.read();

  std::string data = identifierFor(text, "data");
  // Leading zeros are implied by the left-extension rule.
  EXPECT_NE(text.find("b101 " + data), std::string::npos);
  // A repeated leading X collapses to one character.
  EXPECT_NE(text.find("bx " + data), std::string::npos);
  // A leading one must never be dropped.
  EXPECT_NE(text.find("b10000000 " + data), std::string::npos);
}

TEST(VCD, VectorsKeepKnownZeroBeforeUnknownOrHighImpedance) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  // 0X10 must not shorten to X10: the latter left-extends with X, not zero.
  fixture.setBits(kCountBit, 4, 0x2, 0x4);
  fixture.advanceTo(10);
  // The same rule applies to Z left-extension.
  fixture.setBits(kCountBit, 4, 0x6, 0x4);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  EXPECT_EQ(valueRecords(text, identifierFor(text, "count")),
            (std::vector<std::string>{"b0x10", "b0z10"}));
}

TEST(VCD, ScopeSelectionRestrictsTheTracedSet) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  const std::string scope = "top.sub";
  ASSERT_EQ(talos_rt_v1_dump_vars(
                fixture.context, 0,
                reinterpret_cast<const uint8_t *>(scope.data()), scope.size()),
            TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_FALSE(identifierFor(text, "count").empty());
  EXPECT_TRUE(identifierFor(text, "clk").empty());
  EXPECT_TRUE(identifierFor(text, "data").empty());
  // The enclosing scope is still declared so the path stays well formed.
  EXPECT_NE(text.find("$scope module top $end"), std::string::npos);
  EXPECT_NE(text.find("$scope module sub $end"), std::string::npos);
}

TEST(VCD, ManagedStringStorageIsNotTracedAsItsGCHandleBits) {
  Fixture fixture;
  fixture.image.makeRealObjectAString();
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_TRUE(identifierFor(text, "rv").empty());
  EXPECT_FALSE(identifierFor(text, "data").empty());
}

TEST(VCD, FieldNamedStringDoesNotHideAnOrdinaryPackedStruct) {
  Fixture fixture;
  fixture.image.makeStructFieldNamedString();
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_FALSE(identifierFor(text, "st").empty());
}

TEST(VCD, VariableSelectionRestrictsTheTracedSetWithoutEnablingVPI) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  EXPECT_EQ(talos_rt_v1_vpi_startup(fixture.context, nullptr, 0),
            TALOS_RT_PERMISSION_DENIED);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  const std::string variable = "top.sub.count";
  ASSERT_EQ(
      talos_rt_v1_dump_vars(fixture.context, 0,
                            reinterpret_cast<const uint8_t *>(variable.data()),
                            variable.size()),
      TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_FALSE(identifierFor(text, "count").empty());
  EXPECT_TRUE(identifierFor(text, "clk").empty());
  EXPECT_TRUE(identifierFor(text, "data").empty());
  EXPECT_NE(text.find("$scope module top $end"), std::string::npos);
  EXPECT_NE(text.find("$scope module sub $end"), std::string::npos);
}

TEST(VCD, DepthLimitedSelectionExcludesNestedScopes) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 1, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  EXPECT_FALSE(identifierFor(text, "clk").empty());
  EXPECT_TRUE(identifierFor(text, "count").empty());
  EXPECT_EQ(text.find("$scope module sub $end"), std::string::npos);
}

TEST(VCD, DumpOffCheckpointsXAndDumpOnRepublishes) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 1, 0);
  fixture.advanceTo(10);
  ASSERT_EQ(talos_rt_v1_dump_control(fixture.context, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 0, 0);
  fixture.advanceTo(20);
  ASSERT_EQ(talos_rt_v1_dump_control(fixture.context, 1), TALOS_RT_OK);
  fixture.advanceTo(30);
  std::string text = fixture.read();

  std::string clk = identifierFor(text, "clk");
  size_t off = text.find("$dumpoff\n");
  size_t on = text.find("$dumpon\n");
  ASSERT_NE(off, std::string::npos);
  ASSERT_NE(on, std::string::npos);
  EXPECT_LT(off, on);
  EXPECT_NE(text.find("x" + clk, off), std::string::npos);
  // The change that happened while dumping was off is not recorded, but the
  // resumed value is.
  EXPECT_EQ(text.find("0" + clk, off), text.find("0" + clk, on));
  EXPECT_NE(text.find("0" + clk, on), std::string::npos);
}

TEST(VCD, DumpAllEmitsEverySelectedVariable) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 0, 0);
  fixture.advanceTo(10);
  // Nothing changed in this slot, so only $dumpall can republish the value.
  ASSERT_EQ(talos_rt_v1_dump_all(fixture.context), TALOS_RT_OK);
  std::string text = fixture.read();

  std::string clk = identifierFor(text, "clk");
  EXPECT_EQ(valueRecords(text, clk), (std::vector<std::string>{"0", "0"}));
  size_t checkpoint = text.find("$dumpall\n");
  ASSERT_NE(checkpoint, std::string::npos);
  EXPECT_NE(text.find("0" + clk + "\n", checkpoint), std::string::npos);
  EXPECT_NE(text.find("$end\n", checkpoint), std::string::npos);
}

TEST(VCD, DumpAllUpdatesTheActiveShadowWithoutDuplicateSlotRecords) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 0, 0);
  fixture.advanceTo(10);
  fixture.setBits(kClkBit, 1, 1, 0);
  ASSERT_EQ(talos_rt_v1_dump_all(fixture.context), TALOS_RT_OK);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  EXPECT_EQ(valueRecords(text, identifierFor(text, "clk")),
            (std::vector<std::string>{"0", "1"}));
  EXPECT_EQ(countOccurrences(text, "$dumpall\n"), 1u);
}

TEST(VCD, DumpAllRemainsObservableWhileOrdinaryDumpingIsOff) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 0, 0);
  fixture.advanceTo(10);
  ASSERT_EQ(talos_rt_v1_dump_control(fixture.context, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 1, 0);
  ASSERT_EQ(talos_rt_v1_dump_all(fixture.context), TALOS_RT_OK);
  fixture.advanceTo(20);
  ASSERT_EQ(talos_rt_v1_dump_control(fixture.context, 1), TALOS_RT_OK);
  std::string text = fixture.read();

  EXPECT_EQ(valueRecords(text, identifierFor(text, "clk")),
            (std::vector<std::string>{"0", "x", "1", "1"}));
  size_t off = text.find("$dumpoff\n");
  size_t all = text.find("$dumpall\n", off);
  size_t on = text.find("$dumpon\n", all);
  ASSERT_NE(off, std::string::npos);
  ASSERT_NE(all, std::string::npos);
  ASSERT_NE(on, std::string::npos);
  EXPECT_LT(off, all);
  EXPECT_LT(all, on);
}

TEST(VCD, DumpAllDoesNotConsumeThePendingEndOfSlotInitialSample) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 0, 0);
  ASSERT_EQ(talos_rt_v1_dump_all(fixture.context), TALOS_RT_OK);
  fixture.setBits(kClkBit, 1, 1, 0);
  fixture.advanceTo(10);
  std::string text = fixture.read();

  std::string clk = identifierFor(text, "clk");
  EXPECT_EQ(valueRecords(text, clk), (std::vector<std::string>{"0", "1"}));
  size_t all = text.find("$dumpall\n");
  size_t initial = text.find("$dumpvars\n", all);
  ASSERT_NE(all, std::string::npos);
  ASSERT_NE(initial, std::string::npos);
  EXPECT_LT(all, initial);
}

TEST(VCD, DumpLimitStopsWriting) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_limit(fixture.context, 64), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  fixture.setBits(kDataBit, 8, 0xff, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  size_t comment = text.find("$comment dump limit of 64 bytes reached $end");
  ASSERT_NE(comment, std::string::npos);
  EXPECT_LE(comment, 65u);
  EXPECT_EQ(text.find("$enddefinitions"), std::string::npos);
  EXPECT_FALSE(talos_rt_dump_active_unlocked(fixture.context));
}

TEST(VCD, ExactAndZeroDumpLimitsStopWithOneComment) {
  Fixture exact;
  ASSERT_EQ(exact.create(), TALOS_RT_OK);
  ASSERT_EQ(exact.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(exact.context, 0, nullptr, 0), TALOS_RT_OK);
  exact.advanceTo(10);
  ASSERT_EQ(talos_rt_v1_dump_flush(exact.context), TALOS_RT_OK);
  std::ifstream exactFile(exact.path, std::ios::binary | std::ios::ate);
  ASSERT_TRUE(exactFile.good());
  uint64_t written = static_cast<uint64_t>(exactFile.tellg());
  ASSERT_NE(written, 0u);
  ASSERT_EQ(talos_rt_v1_dump_limit(exact.context, written), TALOS_RT_OK);
  std::string exactText = exact.read();
  EXPECT_EQ(countOccurrences(exactText, "$comment dump limit of "), 1u);
  EXPECT_FALSE(talos_rt_dump_active_unlocked(exact.context));

  Fixture zero;
  ASSERT_EQ(zero.create(), TALOS_RT_OK);
  ASSERT_EQ(zero.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_limit(zero.context, 0), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(zero.context, 0, nullptr, 0), TALOS_RT_OK);
  std::string zeroText = zero.read();
  EXPECT_NE(zeroText.find("$comment dump limit of 0 bytes reached $end"),
            std::string::npos);
  EXPECT_EQ(zeroText.find("$enddefinitions"), std::string::npos);
  EXPECT_FALSE(talos_rt_dump_active_unlocked(zero.context));
}

TEST(VCD, HeaderLimitClosesImmediatelyAndDoesNotRetryPerSlot) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_limit(fixture.context, 8), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_dump_vars(fixture.context, 0, nullptr, 0), TALOS_RT_OK);
  fixture.advanceTo(10);
  fixture.setBits(kClkBit, 1, 1, 0);
  fixture.advanceTo(20);
  std::string text = fixture.read();

  EXPECT_EQ(countOccurrences(text, "$comment dump limit of 8 bytes reached"),
            1u);
  // The cut fell inside the header's `$date` line, so the comment starts a
  // line of its own; a cut at a line end adds no blank line.
  EXPECT_EQ(text, "$date\n\t\n$comment dump limit of 8 bytes reached $end\n");
  EXPECT_FALSE(talos_rt_dump_active_unlocked(fixture.context));
}

TEST(VCD, SelectingAMissingScopeIsRejected) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.openDump(), TALOS_RT_OK);
  const std::string scope = "top.absent";
  ASSERT_EQ(talos_rt_v1_dump_vars(
                fixture.context, 0,
                reinterpret_cast<const uint8_t *>(scope.data()), scope.size()),
            TALOS_RT_OK);
  EXPECT_EQ(talos_rt_dump_slot_unlocked(fixture.context),
            TALOS_RT_INVALID_HANDLE);
  // The failure is reported once; later slots neither retry nor write.
  EXPECT_EQ(talos_rt_dump_slot_unlocked(fixture.context), TALOS_RT_OK);
  EXPECT_FALSE(talos_rt_dump_active_unlocked(fixture.context));
}

TEST(VCD, DumpingWithoutAnOpenFileIsInert) {
  Fixture fixture;
  ASSERT_EQ(fixture.create(), TALOS_RT_OK);
  ASSERT_EQ(fixture.context->vcdState, nullptr);
  EXPECT_EQ(talos_rt_dump_slot_unlocked(fixture.context), TALOS_RT_OK);
  EXPECT_EQ(talos_rt_v1_dump_all(fixture.context), TALOS_RT_OK);
  EXPECT_FALSE(talos_rt_dump_active_unlocked(fixture.context));
  EXPECT_EQ(fixture.context->vcdState, nullptr);
}

// The word-at-a-time vector formatter against a bit-at-a-time reference:
// every width up to five words, every bit alignment, planes that end right
// after the value (loads near the end take the bounded path) or run on with
// unrelated bits above it, and values made
// of long runs, which exercise the leading-character rule across word
// boundaries (21.7.2.2, Table 21-9).
TEST(VCDFormat, VectorDigitsMatchABitwiseReference) {
  uint64_t seed = 0x9e3779b97f4a7c15ull;
  auto next = [&] {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return seed;
  };
  auto reference = [](const std::vector<uint8_t> &value,
                      const std::vector<uint8_t> *unknown, uint64_t low,
                      uint64_t width) {
    std::string digits;
    for (uint64_t index = width; index-- != 0;) {
      uint64_t bit = low + index;
      bool v = (value[bit / 8] >> (bit % 8)) & 1;
      bool u = unknown && (((*unknown)[bit / 8] >> (bit % 8)) & 1);
      digits.push_back(u ? (v ? 'z' : 'x') : (v ? '1' : '0'));
    }
    size_t first = 0;
    char lead = digits[0];
    if (lead != '1') {
      while (first + 1 < width && digits[first + 1] == lead)
        ++first;
      if (lead == '0' && first + 1 < width && digits[first + 1] == '1')
        ++first;
    }
    return std::make_pair(digits, first);
  };
  // A run-structured bit stream: each run is one of 0, 1, x, z or random.
  auto fill = [&](std::vector<uint8_t> &value, std::vector<uint8_t> &unknown) {
    size_t bits = value.size() * 8;
    for (size_t bit = 0; bit < bits;) {
      size_t run = 1 + next() % 90;
      unsigned kind = next() % 5;
      for (size_t end = std::min(bits, bit + run); bit != end; ++bit) {
        bool v = kind == 1 || kind == 3 || (kind == 4 && (next() & 1));
        bool u = kind == 2 || kind == 3 || (kind == 4 && next() % 4 == 0);
        value[bit / 8] = static_cast<uint8_t>(value[bit / 8] | (v << (bit % 8)));
        unknown[bit / 8] =
            static_cast<uint8_t>(unknown[bit / 8] | (u << (bit % 8)));
      }
    }
  };
  unsigned cases = 0;
  for (uint64_t width = 1; width <= 320; ++width)
    for (uint64_t low = 0; low < 72; low += (width % 7) + 1)
      for (unsigned round = 0; round != 3; ++round) {
        // Some planes end right after the value (bounded loads); others run
        // on, so the top chunk's word loads see garbage above the value.
        size_t planeBytes =
            static_cast<size_t>((low + width + 7) / 8) + next() % 12;
        std::vector<uint8_t> value(planeBytes), unknown(planeBytes);
        fill(value, unknown);
        for (bool twoState : {false, true}) {
          auto [expected, drop] =
              reference(value, twoState ? nullptr : &unknown, low, width);
          std::string actual(static_cast<size_t>(width) + 8, '?');
          char *end = talos::runtime::vcd::formatVectorDigits(
              value.data(), twoState ? nullptr : unknown.data(), planeBytes,
              low, width, actual.data());
          ASSERT_EQ(end - actual.data(), static_cast<ptrdiff_t>(width));
          actual.resize(static_cast<size_t>(width));
          ASSERT_EQ(actual, expected) << "width " << width << " low " << low;
          ASSERT_EQ(talos::runtime::vcd::compactVectorWidth(
                        value.data(), twoState ? nullptr : unknown.data(),
                        planeBytes, low, width),
                    width - drop)
              << expected;
          ++cases;
        }
      }
  EXPECT_GT(cases, 10000u);
}

} // namespace
