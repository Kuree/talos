//===- DesignBytecodeImage.cpp - Bytecode image parsing and validation --===//

#include "DesignBytecodeImage.h"
#include "DesignBytecodeLogic.h"
#include "RuntimeInternal.h"
#include "talos/Runtime/StableHash.h"

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <iterator>
#include <limits>
#include <new>
#include <numeric>
#include <optional>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace talos::designbytecode {

using BytecodeHeader = talos_rt_design_bytecode_header_v1;

constexpr char kMagic[] = TALOS_RT_DESIGN_BYTECODE_MAGIC;
static_assert(sizeof(kMagic) == sizeof(BytecodeHeader::magic));
constexpr uint64_t kFunctionSize = 96;
constexpr uint64_t kOperandSize = 8;
constexpr uint64_t kContinuationSize = 24;
constexpr uint64_t kIntrinsicSize = 16;
constexpr uint64_t kConnectivitySize = 32;

static bool validationDiagnosticsEnabled() {
  static const bool enabled =
      std::getenv("TALOS_RT_BYTECODE_VALIDATION_DIAGNOSTICS") != nullptr;
  return enabled;
}

static bool rejectImage(unsigned line, const char *reason,
                        uint64_t functionIndex = UINT64_MAX,
                        uint64_t pc = UINT64_MAX,
                        uint32_t opcode = UINT32_MAX) {
  if (!validationDiagnosticsEnabled())
    return false;
  if (functionIndex == UINT64_MAX) {
    std::fprintf(stderr,
                 "talos-bytecode-validation: rejected image: %s "
                 "(DesignBytecodeImage.cpp:%u)\n",
                 reason, line);
  } else if (pc == UINT64_MAX) {
    std::fprintf(stderr,
                 "talos-bytecode-validation: rejected image: %s; "
                 "function=%llu (DesignBytecodeImage.cpp:%u)\n",
                 reason, static_cast<unsigned long long>(functionIndex), line);
  } else {
    std::fprintf(stderr,
                 "talos-bytecode-validation: rejected image: %s; "
                 "function=%llu pc=%llu opcode=%u "
                 "(DesignBytecodeImage.cpp:%u)\n",
                 reason, static_cast<unsigned long long>(functionIndex),
                 static_cast<unsigned long long>(pc), opcode, line);
  }
  return false;
}

bool validRange(uint64_t offset, uint64_t count, uint64_t stride,
                uint64_t size) {
  return (count == 0 ||
          stride <= std::numeric_limits<uint64_t>::max() / count) &&
         offset <= size && count * stride <= size - offset;
}

uint64_t imageChecksum(const uint8_t *data, uint64_t size) {
  return talos_stable_image_checksum(data, static_cast<size_t>(size), 32);
}

uint32_t functionHomeRegion(const Function &function) {
  return static_cast<uint32_t>(
      (function.flags & TALOS_RT_DESIGN_FUNCTION_HOME_MASK) >>
      TALOS_RT_DESIGN_FUNCTION_HOME_SHIFT);
}

bool validProcessFunctionFlags(const Function &function) {
  if ((function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0)
    return function.flags == 0;
  uint32_t homeRegion = functionHomeRegion(function);
  return talos_rt_is_process_home_region(homeRegion) &&
         ((function.flags & TALOS_RT_DESIGN_FUNCTION_FINAL) == 0 ||
          homeRegion == TALOS_RT_REGION_ACTIVE);
}

bool decodeImageHeader(const talos_rt_design_bytecode_entry_v1 &entry,
                       Image &image, bool inventoryOnly) {
  const auto *execution = entry.execution;
  if (!execution || entry.reserved != 0 ||
      execution->version != TALOS_RT_VERSION ||
      (execution->flags & TALOS_RT_EXECUTION_HAS_BYTECODE) == 0 ||
      !execution->bytecode ||
      execution->bytecode_size < TALOS_RT_DESIGN_BYTECODE_HEADER_SIZE)
    return rejectImage(__LINE__, "invalid execution bytecode descriptor");
  const uint8_t *data = execution->bytecode;
  image = {data,
           execution->bytecode_size,
           read64(data + offsetof(BytecodeHeader, function_offset)),
           read64(data + offsetof(BytecodeHeader, function_count)),
           read64(data + offsetof(BytecodeHeader, layout_offset)),
           read64(data + offsetof(BytecodeHeader, layout_count)),
           read64(data + offsetof(BytecodeHeader, code_offset)),
           read64(data + offsetof(BytecodeHeader, instruction_count)),
           read64(data + offsetof(BytecodeHeader, operand_offset)),
           read64(data + offsetof(BytecodeHeader, operand_count)),
           read64(data + offsetof(BytecodeHeader, constant_offset)),
           read64(data + offsetof(BytecodeHeader, constant_size)),
           read64(data + offsetof(BytecodeHeader, continuation_offset)),
           read64(data + offsetof(BytecodeHeader, continuation_count)),
           read64(data + offsetof(BytecodeHeader, intrinsic_offset)),
           read64(data + offsetof(BytecodeHeader, intrinsic_count)),
           read64(data + offsetof(BytecodeHeader, site_offset)),
           read64(data + offsetof(BytecodeHeader, site_count)),
           read64(data + offsetof(BytecodeHeader, state_offset)),
           read64(data + offsetof(BytecodeHeader, state_count)),
           read64(data + offsetof(BytecodeHeader, connectivity_offset)),
           read64(data + offsetof(BytecodeHeader, connectivity_count)),
           read64(data + offsetof(BytecodeHeader, shape_offset)),
           read64(data + offsetof(BytecodeHeader, shape_count)),
           execution->state_bit_count};
  if (image.functionCount > UINT32_MAX ||
      (!inventoryOnly && entry.function >= image.functionCount) ||
      (image.functionCount == 0 &&
       (execution->flags & TALOS_RT_EXECUTION_REQUIRE_BYTECODE)))
    return rejectImage(__LINE__, "bytecode function index is out of range");
  return true;
}

bool parseImage(const talos_rt_design_bytecode_entry_v1 &entry, Image &image,
                bool inventoryOnly) {
  if (!decodeImageHeader(entry, image, inventoryOnly))
    return false;
  const auto *execution = entry.execution;
  const uint8_t *data = execution->bytecode;
  if (std::memcmp(data + offsetof(BytecodeHeader, magic), kMagic,
                  sizeof(kMagic)) != 0 ||
      read32(data + offsetof(BytecodeHeader, version)) != TALOS_RT_VERSION ||
      read32(data + offsetof(BytecodeHeader, reserved)) != 0 ||
      read32(data + offsetof(BytecodeHeader, header_size)) !=
          TALOS_RT_DESIGN_BYTECODE_HEADER_SIZE ||
      read64(data + offsetof(BytecodeHeader, image_size)) !=
          execution->bytecode_size ||
      read64(data + offsetof(BytecodeHeader, checksum)) == 0 ||
      read64(data + offsetof(BytecodeHeader, checksum)) !=
          execution->checksum ||
      read64(data + offsetof(BytecodeHeader, checksum)) !=
          imageChecksum(data, execution->bytecode_size))
    return rejectImage(__LINE__,
                       "invalid bytecode header identity, size, or checksum");
  uint32_t headerFlags = read32(data + offsetof(BytecodeHeader, flags));
  image.compactCode =
      (headerFlags & TALOS_RT_DESIGN_BYTECODE_COMPACT_CODE) != 0;
  image.codeSize = image.compactCode
                       ? read64(data + offsetof(BytecodeHeader, code_size))
                       : image.instructionCount * kInstructionSize;
  if ((headerFlags & ~TALOS_RT_DESIGN_BYTECODE_COMPACT_CODE) != 0 ||
      (!image.compactCode &&
       read64(data + offsetof(BytecodeHeader, code_size)) != 0) ||
      (!image.compactCode &&
       image.instructionCount > UINT64_MAX / kInstructionSize) ||
      (image.compactCode &&
       (image.instructionCount > UINT32_MAX ||
        image.codeSize < image.instructionCount * 4 ||
        image.codeSize - image.instructionCount * 4 > UINT32_MAX)) ||
      !validRange(image.functions, image.functionCount, kFunctionSize,
                  image.size) ||
      !validRange(image.layouts, image.layoutCount, kLayoutSize, image.size) ||
      !validRange(image.shapes, image.shapeCount, kShapeSize, image.size) ||
      !validRange(image.code, image.codeSize, 1, image.size) ||
      !validRange(image.operands, image.operandCount, kOperandSize,
                  image.size) ||
      !validRange(image.constants, image.constantSize, 1, image.size) ||
      !validRange(image.continuations, image.continuationCount,
                  kContinuationSize, image.size) ||
      !validRange(image.intrinsics, image.intrinsicCount, kIntrinsicSize,
                  image.size) ||
      !validRange(image.sites, image.siteCount, kIntrinsicSize, image.size) ||
      !validRange(image.stateDescriptors, image.stateDescriptorCount, 32,
                  image.size) ||
      !validRange(image.connectivity, image.connectivityCount,
                  kConnectivitySize, image.size))
    return rejectImage(
        __LINE__, "invalid bytecode header flags, ranges, or reserved data");
  // Compact code is canonical: the first instruction starts its byte area
  // (no unused bytes before it), and an empty table has no bytes.
  if (image.compactCode &&
      (image.instructionCount == 0 ? image.codeSize != 0
                                   : read32(data + image.code) != 0))
    return rejectImage(__LINE__, "noncanonical compact code table");
  uint64_t cursor = TALOS_RT_DESIGN_BYTECODE_HEADER_SIZE;
  auto canonicalTable = [&](uint64_t offset, uint64_t count, uint64_t stride) {
    if (cursor > UINT64_MAX - 7)
      return false;
    uint64_t aligned = (cursor + 7) & ~uint64_t{7};
    if (offset != aligned)
      return false;
    for (uint64_t padding = cursor; padding != aligned; ++padding)
      if (data[padding] != 0)
        return false;
    cursor = offset + count * stride;
    return true;
  };
  if (!canonicalTable(image.functions, image.functionCount, kFunctionSize) ||
      !canonicalTable(image.layouts, image.layoutCount, kLayoutSize) ||
      !canonicalTable(image.shapes, image.shapeCount, kShapeSize) ||
      !canonicalTable(image.code, image.codeSize, 1) ||
      !canonicalTable(image.operands, image.operandCount, kOperandSize) ||
      !canonicalTable(image.constants, image.constantSize, 1) ||
      !canonicalTable(image.continuations, image.continuationCount,
                      kContinuationSize) ||
      !canonicalTable(image.intrinsics, image.intrinsicCount, kIntrinsicSize) ||
      !canonicalTable(image.sites, image.siteCount, kIntrinsicSize) ||
      !canonicalTable(image.stateDescriptors, image.stateDescriptorCount, 32) ||
      !canonicalTable(image.connectivity, image.connectivityCount,
                      kConnectivitySize) ||
      cursor != image.size)
    return rejectImage(__LINE__, "noncanonical bytecode table layout");
  return true;
}

Instruction compactInstructionAt(const Image &image, uint64_t index) {
  constexpr Instruction invalid{UINT16_MAX, 0, 0, 0, 0, 0, 0, 0};
  if (index >= image.instructionCount)
    return invalid;
  const uint8_t *offsets = image.data + image.code;
  const uint8_t *bytes = offsets + image.instructionCount * 4;
  uint64_t byteCount = image.codeSize - image.instructionCount * 4;
  uint64_t begin = read32(offsets + index * 4);
  uint64_t end = index + 1 == image.instructionCount
                     ? byteCount
                     : read32(offsets + (index + 1) * 4);
  if (begin >= end || end > byteCount || end - begin < 2)
    return invalid;
  const uint8_t *cursor = bytes + begin;
  const uint8_t *limit = bytes + end;
  Instruction instruction;
  instruction.opcode = *cursor++;
  uint8_t mask = *cursor++;
  if (mask & 0x80)
    return invalid;
  // A present field is nonzero and minimally encoded.
  auto field = [&](uint64_t maximum, uint64_t &value) {
    value = 0;
    for (unsigned shift = 0;; shift += 7) {
      if (cursor == limit || shift > 63)
        return false;
      uint8_t byte = *cursor++;
      if (shift == 63 && (byte & 0x7e))
        return false;
      value |= uint64_t{byte & 0x7fu} << shift;
      if ((byte & 0x80) == 0)
        return (byte != 0 || shift == 0) && value != 0 && value <= maximum;
    }
  };
  uint64_t values[7] = {};
  const uint64_t maxima[7] = {UINT16_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX,
                              UINT32_MAX, UINT32_MAX, UINT64_MAX};
  for (unsigned bit = 0; bit != 7; ++bit)
    if ((mask & (1u << bit)) && !field(maxima[bit], values[bit]))
      return invalid;
  if (cursor != limit)
    return invalid;
  instruction.flags = static_cast<uint16_t>(values[0]);
  instruction.destination = static_cast<uint32_t>(values[1]);
  instruction.source0 = static_cast<uint32_t>(values[2]);
  instruction.source1 = static_cast<uint32_t>(values[3]);
  instruction.source2 = static_cast<uint32_t>(values[4]);
  instruction.auxiliary = static_cast<uint32_t>(values[5]);
  instruction.immediate = values[6];
  return instruction;
}

Function functionAt(const Image &image, uint32_t index) {
  const uint8_t *data =
      image.data + image.functions + uint64_t{index} * kFunctionSize;
  return {read64(data),      read64(data + 8),  read64(data + 16),
          read64(data + 24), read64(data + 32), read64(data + 40),
          read32(data + 48), read32(data + 52), read64(data + 56),
          read64(data + 64), read64(data + 72), read64(data + 80),
          read64(data + 88)};
}

Continuation continuationAt(const Image &image, uint64_t index) {
  const uint8_t *data =
      image.data + image.continuations + index * kContinuationSize;
  return {read32(data), read32(data + 4), read64(data + 8), read32(data + 16),
          read32(data + 20)};
}

IntrinsicSignature intrinsicAt(const Image &image, uint32_t index) {
  const uint8_t *data = image.data + image.intrinsics + uint64_t{index} * 16;
  return {read32(data), read32(data + 4), read32(data + 8), read32(data + 12)};
}

IntrinsicSite siteAt(const Image &image, uint32_t index) {
  const uint8_t *data = image.data + image.sites + uint64_t{index} * 16;
  return {read32(data), read32(data + 4), read32(data + 8), read32(data + 12)};
}

CaptureRecord captureAt(const Image &image, uint64_t index) {
  const uint8_t *data = image.data + image.stateDescriptors + index * 32;
  return {read32(data), read32(data + 4), read64(data + 8), read64(data + 16),
          read64(data + 24)};
}

ConnectivityRecord connectivityAt(const Image &image, uint64_t index) {
  const uint8_t *data =
      image.data + image.connectivity + index * kConnectivitySize;
  return {read64(data), read64(data + 8), read64(data + 16), data[24],
          data[25],     data[26],         data[27],          read32(data + 28)};
}

std::pair<uint32_t, uint32_t> operandAt(const Image &image, uint64_t index) {
  const uint8_t *data = image.data + image.operands + index * kOperandSize;
  return {read32(data), read32(data + 4)};
}

uint64_t layoutSize(uint8_t kind, uint32_t width) {
  uint64_t limbs = limbCount(width);
  switch (kind) {
  case TALOS_RT_DBREG_BITS:
    return limbs * 8;
  case TALOS_RT_DBREG_LOGIC:
    return limbs * 16;
  case TALOS_RT_DBREG_HANDLE:
    return 32;
  case TALOS_RT_DBREG_STATUS:
  case TALOS_RT_DBREG_RESOURCE:
    return 8;
  case TALOS_RT_DBREG_BYTES:
    return 16;
  case TALOS_RT_DBREG_MANAGED:
  case TALOS_RT_DBREG_STRING:
  case TALOS_RT_DBREG_REAL64:
    return 8;
  case TALOS_RT_DBREG_REAL32:
    return 4;
  case TALOS_RT_DBREG_MANAGED_REF:
    return 16;
  case TALOS_RT_DBREG_ARGUMENT_REF:
    return 24;
  default:
    return 0;
  }
}

bool compatible(const Layout &left, const Layout &right) {
  return left.kind == right.kind && left.flags == right.flags &&
         left.width == right.width && left.size == right.size &&
         left.auxiliary == right.auxiliary;
}

bool bitcastCompatible(const Layout &left, const Layout &right) {
  // A builtin base view preserves the class object's managed word. Only
  // the forward class-to-builtin conversion is implicit; the interpreter
  // checks the allocated class's builtin ancestry before changing its view.
  if (left.kind == TALOS_RT_DBREG_MANAGED &&
      right.kind == TALOS_RT_DBREG_MANAGED)
    return right.flags == TALOS_RT_DBREG_CLASS_HANDLE &&
           (left.flags == TALOS_RT_DBREG_MAILBOX ||
            left.flags == TALOS_RT_DBREG_SEMAPHORE) &&
           left.width == 64 && right.width == 64 && left.size == 8 &&
           right.size == 8 && left.auxiliary == 0 && right.auxiliary == 0;
  auto floatingWidth = [](const Layout &layout) -> uint32_t {
    if (layout.kind == TALOS_RT_DBREG_REAL32)
      return 32;
    if (layout.kind == TALOS_RT_DBREG_REAL64)
      return 64;
    return 0;
  };
  if (left.kind == TALOS_RT_DBREG_BITS)
    return left.width == floatingWidth(right);
  if (right.kind == TALOS_RT_DBREG_BITS)
    return right.width == floatingWidth(left);
  return false;
}

bool validRegister(const Function &function, uint32_t index) {
  return index < function.layoutCount;
}

bool validMap(const Image &image, const Function &source,
              const Function &destination, uint64_t first, uint64_t count) {
  if (first > image.operandCount || count > image.operandCount - first)
    return false;
  for (uint64_t index = 0; index != count; ++index) {
    auto [destinationRegister, sourceRegister] =
        operandAt(image, first + index);
    if (!validRegister(source, sourceRegister) ||
        !validRegister(destination, destinationRegister) ||
        !compatible(layoutAt(image, source, sourceRegister),
                    layoutAt(image, destination, destinationRegister)))
      return false;
  }
  return true;
}

bool validIntrinsic(const Image &image, const Function &function,
                    uint32_t siteIndex) {
  if (siteIndex >= image.siteCount)
    return false;
  IntrinsicSite site = siteAt(image, siteIndex);
  if (site.intrinsic >= image.intrinsicCount ||
      site.firstOperand > image.operandCount ||
      uint64_t{site.inputCount} + site.outputCount >
          image.operandCount - site.firstOperand)
    return false;
  IntrinsicSignature signature = intrinsicAt(image, site.intrinsic);
  if (signature.inputCount != site.inputCount ||
      signature.outputCount != site.outputCount)
    return false;
  if (signature.id != TALOS_RT_INTRINSIC_V1_SPAWN &&
      signature.id != TALOS_RT_INTRINSIC_V1_EVENT_TRIGGER &&
      signature.id != TALOS_RT_INTRINSIC_V1_IMPORT &&
      signature.id != TALOS_RT_INTRINSIC_V1_CONTROL_ENTER &&
      signature.id != TALOS_RT_INTRINSIC_V1_CONTROL_BOUNDARY &&
      signature.id != TALOS_RT_INTRINSIC_V1_CONTROL_DISABLE &&
      signature.id != TALOS_RT_INTRINSIC_V1_STATIC_ONCE &&
      signature.id != TALOS_RT_INTRINSIC_V1_ASSERTION_CONTROL &&
      signature.id != TALOS_RT_INTRINSIC_V1_MONITOR_CONTROL &&
      signature.id != TALOS_RT_INTRINSIC_V1_DUMP_CONTROL &&
      signature.id != TALOS_RT_INTRINSIC_V1_DUMP_PORTS_CONTROL &&
      signature.id != TALOS_RT_INTRINSIC_V1_REAL_FROM_INTEGER &&
      signature.id != TALOS_RT_INTRINSIC_V1_REAL_TO_INTEGER &&
      signature.id != TALOS_RT_INTRINSIC_V1_REAL_COMPARE &&
      signature.id != TALOS_RT_INTRINSIC_V1_STRING_TO_PACKED &&
      signature.id != TALOS_RT_INTRINSIC_V1_CONTAINER_EXPORT_BITSTREAM &&
      signature.id != TALOS_RT_INTRINSIC_V1_CLOCK_OCCURRENCE_CONSUME &&
      signature.id != TALOS_RT_INTRINSIC_V1_CLOCKING_OUTPUT_TRACK &&
      signature.id != TALOS_RT_INTRINSIC_V1_CLOCKING_OUTPUT_CURRENT &&
      signature.id != TALOS_RT_INTRINSIC_V1_NOCHANGE_UPDATE &&
      signature.id != TALOS_RT_INTRINSIC_V1_PASS_SWITCH_CONTROL &&
      signature.id != TALOS_RT_INTRINSIC_V1_PASS_SWITCH_CONTROL_DELAYED &&
      signature.id != TALOS_RT_INTRINSIC_V1_MOS_DRIVE_DELAYED &&
      signature.flags != 0)
    return false;
  auto input = [&](uint32_t index) -> std::optional<Layout> {
    if (index >= site.inputCount)
      return std::nullopt;
    uint32_t reg = operandAt(image, site.firstOperand + index).second;
    if (!validRegister(function, reg))
      return std::nullopt;
    return layoutAt(image, function, reg);
  };
  auto output = [&](uint32_t index) -> std::optional<Layout> {
    if (index >= site.outputCount)
      return std::nullopt;
    uint32_t reg =
        operandAt(image, site.firstOperand + site.inputCount + index).first;
    if (!validRegister(function, reg))
      return std::nullopt;
    return layoutAt(image, function, reg);
  };
  auto numeric = [](const std::optional<Layout> &layout) {
    return layout && (layout->kind == TALOS_RT_DBREG_BITS ||
                      layout->kind == TALOS_RT_DBREG_LOGIC);
  };
  auto floating = [](const std::optional<Layout> &layout) {
    return layout && (layout->kind == TALOS_RT_DBREG_REAL32 ||
                      layout->kind == TALOS_RT_DBREG_REAL64);
  };
  auto bits = [&](const std::optional<Layout> &layout, uint32_t width) {
    return numeric(layout) && layout->width == width;
  };
  auto twoStateBits = [](const std::optional<Layout> &layout,
                         std::optional<uint32_t> width = std::nullopt) {
    return layout && layout->kind == TALOS_RT_DBREG_BITS &&
           (!width || layout->width == *width);
  };
  auto vpiIdentity = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_BITS &&
           layout->flags == 0 && layout->width == 64 && layout->size == 8;
  };
  auto bytes = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_BYTES;
  };
  auto handle = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_HANDLE;
  };
  auto event = [&](const std::optional<Layout> &layout) {
    return handle(layout) && layout->width == 256 && layout->size == 32 &&
           layout->flags == TALOS_RT_DBREG_EVENT;
  };
  auto status = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_STATUS;
  };
  auto managed = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_MANAGED;
  };
  auto string = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_STRING;
  };
  auto managedRef = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_MANAGED_REF;
  };
  auto argumentRef = [](const std::optional<Layout> &layout) {
    return layout && layout->kind == TALOS_RT_DBREG_ARGUMENT_REF;
  };
  auto managedValue = [&](const std::optional<Layout> &layout) {
    return numeric(layout) || floating(layout) || managed(layout) ||
           string(layout) || handle(layout);
  };
  auto assocKey = [&](const std::optional<Layout> &layout) {
    return string(layout) || managed(layout) || event(layout) ||
           (numeric(layout) && layout->width >= 1);
  };
  auto cursor = [&](const std::optional<Layout> &layout) {
    return bits(layout, 64);
  };
  switch (signature.id) {
  case TALOS_RT_INTRINSIC_V1_SPAWN: {
    uint32_t calleeIndex =
        signature.flags & TALOS_RT_INTRINSIC_SPAWN_FUNCTION_MASK;
    if (calleeIndex >= image.functionCount || site.outputCount != 1 ||
        (!twoStateBits(output(0), 64) && !handle(output(0))))
      return false;
    Function callee = functionAt(image, calleeIndex);
    bool program = (signature.flags & TALOS_RT_INTRINSIC_SPAWN_PROGRAM) != 0;
    if ((callee.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
        site.inputCount != callee.argumentCount + (program ? 1u : 0u))
      return false;
    for (uint32_t index = 0; index != callee.argumentCount; ++index)
      if (!input(index) ||
          !compatible(*input(index), layoutAt(image, callee, index)))
        return false;
    if (program && !twoStateBits(input(callee.argumentCount), 64))
      return false;
    return true;
  }
  case TALOS_RT_INTRINSIC_V1_POWER_CANCEL_NBA:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && handle(input(0)) && bits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_POWER_NBA:
    return signature.flags == 0 &&
           (site.inputCount == 8 || site.inputCount == 9) &&
           site.outputCount == 0 && numeric(input(0)) && handle(input(1)) &&
           handle(input(2)) && handle(input(3)) && twoStateBits(input(4), 64) &&
           handle(input(5)) && twoStateBits(input(6), 64) &&
           twoStateBits(input(7), 64) &&
           (site.inputCount == 8 || twoStateBits(input(8), 64));
  case TALOS_RT_INTRINSIC_V1_POWER_NBA_VIEW:
    return signature.flags == 0 &&
           (site.inputCount == 12 || site.inputCount == 13) &&
           site.outputCount == 0 && numeric(input(0)) && handle(input(1)) &&
           twoStateBits(input(2), 64) && twoStateBits(input(3), 64) &&
           twoStateBits(input(4), 64) && twoStateBits(input(5), 1) &&
           handle(input(6)) && twoStateBits(input(7), 64) && handle(input(8)) &&
           twoStateBits(input(9), 64) && twoStateBits(input(10), 64) &&
           twoStateBits(input(11), 64) &&
           (site.inputCount == 12 || twoStateBits(input(12), 64));
  case TALOS_RT_INTRINSIC_V1_NBA:
    return signature.flags == 0 &&
           (site.inputCount == 2 || site.inputCount == 3) &&
           site.outputCount == 0 &&
           (numeric(input(0)) || floating(input(0)) || string(input(0)) ||
            managed(input(0))) &&
           handle(input(1)) && (site.inputCount == 2 || bits(input(2), 64));
  case TALOS_RT_INTRINSIC_V1_CLOCKING_NBA:
    return signature.flags == 0 &&
           (site.inputCount == 3 || site.inputCount == 4) &&
           site.outputCount == 0 && (numeric(input(0)) || floating(input(0))) &&
           handle(input(1)) && (site.inputCount == 3 || bits(input(2), 64)) &&
           bits(input(site.inputCount - 1), 64);
  case TALOS_RT_INTRINSIC_V1_STATIC_NBA:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 &&
           (numeric(input(0)) || floating(input(0)) || string(input(0)) ||
            managed(input(0))) &&
           handle(input(1)) && bits(input(2), 64);
  case TALOS_RT_INTRINSIC_V1_INERTIAL_DRIVER:
    return signature.flags == 0 && site.inputCount == 8 &&
           site.outputCount == 0 && (numeric(input(0)) || floating(input(0))) &&
           handle(input(1)) && bits(input(2), 64) && bits(input(3), 64) &&
           bits(input(4), 64) && bits(input(5), 64) && bits(input(6), 64) &&
           bits(input(7), 64);
  case TALOS_RT_INTRINSIC_V1_INERTIAL_DRIVER_STRENGTH_PAIR: {
    auto low = input(0);
    auto high = input(2);
    auto transition = input(4);
    return signature.flags == 0 && site.inputCount == 10 &&
           site.outputCount == 0 && numeric(low) && handle(input(1)) &&
           numeric(high) && handle(input(3)) && numeric(transition) &&
           compatible(*low, *high) && compatible(*low, *transition) &&
           bits(input(5), 64) && bits(input(6), 64) && bits(input(7), 64) &&
           bits(input(8), 64) && bits(input(9), 64);
  }
  case TALOS_RT_INTRINSIC_V1_INERTIAL_PATH_STRENGTH_PAIR: {
    auto low = input(0);
    auto high = input(2);
    auto transition = input(4);
    if (signature.flags != 0 ||
        (site.inputCount != 16 && site.inputCount != 20) ||
        site.outputCount != 0 || !numeric(low) || !handle(input(1)) ||
        !numeric(high) || !handle(input(3)) || !numeric(transition) ||
        !compatible(*low, *high) || !compatible(*low, *transition))
      return false;
    for (unsigned index = 5; index != 9; ++index) {
      auto mask = input(index);
      if (!mask || mask->kind != TALOS_RT_DBREG_BITS ||
          mask->width != low->width)
        return false;
    }
    unsigned scalarEnd = site.inputCount == 16 ? 16 : 19;
    for (unsigned index = 9; index != scalarEnd; ++index)
      if (!bits(input(index), 64))
        return false;
    if (site.inputCount == 16)
      return true;
    auto pulseTransitions = input(19);
    return low->width <= UINT32_MAX / 12 && pulseTransitions &&
           pulseTransitions->kind == TALOS_RT_DBREG_BITS &&
           pulseTransitions->width == low->width * 12;
  }
  case TALOS_RT_INTRINSIC_V1_LOGIC_CASE_DIFFERENCE_MASK: {
    auto lhs = input(0);
    auto rhs = input(1);
    auto result = output(0);
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && numeric(lhs) && numeric(rhs) &&
           compatible(*lhs, *rhs) && result &&
           result->kind == TALOS_RT_DBREG_BITS && result->width == lhs->width;
  }
  case TALOS_RT_INTRINSIC_V1_INERTIAL_PATH_DRIVER: {
    auto value = input(0);
    if (signature.flags != 0 ||
        (site.inputCount != 14 && site.inputCount != 17) ||
        site.outputCount != 0 || !numeric(value) || !handle(input(1)))
      return false;
    for (unsigned index = 2; index != 6; ++index) {
      auto mask = input(index);
      if (!mask || mask->kind != TALOS_RT_DBREG_BITS ||
          mask->width != value->width)
        return false;
    }
    unsigned scalarEnd = site.inputCount == 14 ? 14 : 16;
    for (unsigned index = 6; index != scalarEnd; ++index)
      if (!bits(input(index), 64))
        return false;
    if (site.inputCount == 14)
      return true;
    auto transitions = input(16);
    return transitions && transitions->kind == TALOS_RT_DBREG_BITS &&
           transitions->width == value->width * 12;
  }
  case TALOS_RT_INTRINSIC_V1_INERTIAL_PATH_STORAGE: {
    auto value = input(0);
    if (signature.flags != 0 ||
        (site.inputCount != 15 && site.inputCount != 19) ||
        site.outputCount != 0 || !numeric(value) || !handle(input(1)))
      return false;
    for (unsigned index = 2; index != 7; ++index) {
      auto mask = input(index);
      if (!mask || mask->kind != TALOS_RT_DBREG_BITS ||
          mask->width != value->width)
        return false;
    }
    unsigned scalarEnd = site.inputCount == 15 ? 15 : 18;
    for (unsigned index = 7; index != scalarEnd; ++index)
      if (!bits(input(index), 64))
        return false;
    if (site.inputCount == 15)
      return true;
    auto transitions = input(18);
    return transitions && transitions->kind == TALOS_RT_DBREG_BITS &&
           transitions->width == value->width * 12;
  }
  case TALOS_RT_INTRINSIC_V1_EVENT_TRIGGER:
    return signature.flags <= 1 &&
           (site.inputCount == 1 || site.inputCount == 2) &&
           site.outputCount == 0 && handle(input(0)) &&
           (site.inputCount == 1 ||
            (signature.flags == 1 && bits(input(1), 64)));
  case TALOS_RT_INTRINSIC_V1_EVENT_REPLACE_AFTER:
    return signature.flags == 0 &&
           (site.inputCount == 1 || site.inputCount == 2) &&
           site.outputCount == 0 && handle(input(0)) &&
           (site.inputCount == 1 || bits(input(1), 64));
  case TALOS_RT_INTRINSIC_V1_EVENT_TRIGGERED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && handle(input(0)) && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_WAIT_ORDER_FAILED:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_CLOCK_OCCURRENCE_CONSUME:
    return signature.flags != 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_CLOCKING_OUTPUT_TRACK:
    return signature.flags <= 2 && site.inputCount == 2 &&
           site.outputCount == 0 && handle(input(0)) && bits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_CLOCKING_OUTPUT_CURRENT:
    return signature.flags <= 2 && site.inputCount == 2 &&
           site.outputCount == 1 && handle(input(0)) && bits(input(1), 64) &&
           bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_NOCHANGE_UPDATE:
    return signature.flags != 0 && site.inputCount == 3 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(input(1), 64) &&
           bits(input(2), 64) && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_NET_COUNT_DRIVERS:
    if (signature.flags != 0 || site.inputCount != 1 || site.outputCount != 5 ||
        !handle(input(0)))
      return false;
    for (uint32_t index = 0; index != 5; ++index)
      if (!twoStateBits(output(index), 32))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_PASS_SWITCH_CONTROL:
    return site.inputCount == 1 && site.outputCount == 0 && bits(input(0), 1);
  case TALOS_RT_INTRINSIC_V1_PASS_SWITCH_CONTROL_DELAYED:
    return site.inputCount == 4 && site.outputCount == 0 && bits(input(0), 1) &&
           bits(input(1), 64) && bits(input(2), 64) && bits(input(3), 64);
  case TALOS_RT_INTRINSIC_V1_MOS_DRIVE_DELAYED:
    return site.inputCount == 4 && site.outputCount == 0 && bits(input(0), 1) &&
           bits(input(1), 64) && bits(input(2), 64) && bits(input(3), 64);
  case TALOS_RT_INTRINSIC_V1_STATE_ALLOC:
    if (signature.flags != 0 || site.inputCount == 0 || site.outputCount != 1 ||
        (!numeric(input(0)) && !floating(input(0)) && !managed(input(0)) &&
         !string(input(0)) && !event(input(0))) ||
        !handle(output(0)) ||
        ((managed(input(0)) || string(input(0)) || event(input(0))) &&
         site.inputCount != 1))
      return false;
    for (uint32_t index = 1; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_STATE_ALLOC_TYPED:
    if (signature.flags != 0 || site.inputCount < 4 ||
        ((site.inputCount - 1) % 3) != 0 || site.outputCount != 1 ||
        (!numeric(input(0)) && !floating(input(0)) && !string(input(0))) ||
        !handle(output(0)))
      return false;
    for (uint32_t index = 1; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_DISABLE_CHILDREN:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_CONTROL_ENTER:
    return signature.flags != 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_CONTROL_BOUNDARY:
    return signature.flags != 0 && site.inputCount == 1 &&
           site.outputCount == 0 && bits(input(0), 64);
  case TALOS_RT_INTRINSIC_V1_CONTROL_LEAVE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && bits(input(0), 64);
  case TALOS_RT_INTRINSIC_V1_CONTROL_DISABLE:
    return (signature.flags & ~(UINT32_C(1) << 31)) != 0 &&
           site.inputCount <= 1 && site.outputCount == 0 &&
           (site.inputCount == 0 || bits(input(0), 64)) &&
           ((signature.flags >> 31) == 0 || site.inputCount == 0);
  case TALOS_RT_INTRINSIC_V1_CONTROL_DISABLE_SELECTED:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(output(0), 64) && input(0)->flags == 0 &&
           input(1)->flags == 0 && input(2)->flags == 0 &&
           output(0)->flags == 0 && input(0)->size == 8 &&
           input(1)->size == 8 && input(2)->size == 8 && output(0)->size == 8;
  case TALOS_RT_INTRINSIC_V1_CONTROL_ESCAPE_PENDING:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_STATIC_ONCE:
    return signature.flags != 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_DEFERRED_ONCE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_SAMPLED_READ:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && handle(input(0)) &&
           (numeric(output(0)) || floating(output(0)));
  case TALOS_RT_INTRINSIC_V1_SAMPLED_HISTORY:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(input(1), 64) &&
           bits(input(2), 1) && numeric(input(3)) && numeric(output(0)) &&
           input(3)->kind == output(0)->kind &&
           input(3)->width == output(0)->width;
  case TALOS_RT_INTRINSIC_V1_CLOCKED_SAMPLE_UPDATE:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 0 && bits(input(0), 64) && bits(input(1), 64) &&
           bits(input(2), 1) && numeric(input(3));
  case TALOS_RT_INTRINSIC_V1_CLOCKED_SAMPLE_READ:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(input(1), 64) &&
           bits(input(2), 64) && numeric(output(0));
  case TALOS_RT_INTRINSIC_V1_DEFERRED_ENQUEUE:
    return signature.flags == 0 &&
           (site.inputCount == 1 || site.inputCount == 2) &&
           site.outputCount == 1 && bits(input(0), 64) &&
           (site.inputCount == 1 || bits(input(1), 64)) && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_DEFERRED_MATURE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_ASSERTION_CONTROL:
    // IEEE 1800-2023 20.11: an integer expression can select the control type,
    // which generated code range checks. It is then an input ahead of the
    // target.
    if (signature.flags == 0)
      return site.inputCount == 2 && site.outputCount == 0 &&
             bits(input(0), 32) && bits(input(1), 64);
    return signature.flags >= 1 && signature.flags <= 11 &&
           site.inputCount == 1 && site.outputCount == 0 && bits(input(0), 64);
  case TALOS_RT_INTRINSIC_V1_ASSERTION_ENABLED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_ASSERTION_ACTION_STATE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_ASSERTION_KILL_EPOCH:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_DUMP_OPEN:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && bytes(input(0));
  case TALOS_RT_INTRINSIC_V1_DUMP_OPEN_STRING:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && string(input(0));
  case TALOS_RT_INTRINSIC_V1_DUMP_TIMESCALE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && numeric(input(0));
  case TALOS_RT_INTRINSIC_V1_DUMP_VARS:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && numeric(input(0)) && bytes(input(1));
  case TALOS_RT_INTRINSIC_V1_DUMP_LIMIT:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && numeric(input(0));
  case TALOS_RT_INTRINSIC_V1_DUMP_ALL:
  case TALOS_RT_INTRINSIC_V1_DUMP_FLUSH:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_DUMP_CONTROL:
    return signature.flags <= 1 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_DUMP_PORTS:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && string(input(0)) && string(input(1)) &&
           twoStateBits(input(2), 32);
  case TALOS_RT_INTRINSIC_V1_DUMP_PORTS_CONTROL:
    return signature.flags <= 4 && site.inputCount == 2 &&
           site.outputCount == 0 && string(input(0)) &&
           twoStateBits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_MONITOR_REGISTER:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 &&
           (twoStateBits(input(0), 64) || handle(input(0)));
  case TALOS_RT_INTRINSIC_V1_PROCESS_CURRENT:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_PROCESS_STATUS:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_EVENT_SNAPSHOT_MASK:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_EVENT_SNAPSHOT_FLUSH:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_PROCESS_EVENT_PENDING:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_PROCESS_RANDOM_GET:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 2 && twoStateBits(input(0), 64) &&
           twoStateBits(output(0), 64) && twoStateBits(output(1), 64);
  case TALOS_RT_INTRINSIC_V1_PROCESS_RANDOM_SET:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64);
  case TALOS_RT_INTRINSIC_V1_MONITOR_CONTROL:
    return signature.flags <= 1 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_MONITOR_CURRENT:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_IMPORT:
    if (signature.flags == 0)
      return false;
    for (uint32_t index = 0; index != site.inputCount; ++index)
      if (!input(index) || (input(index)->kind != TALOS_RT_DBREG_BITS &&
                            input(index)->kind != TALOS_RT_DBREG_LOGIC &&
                            input(index)->kind != TALOS_RT_DBREG_HANDLE &&
                            input(index)->kind != TALOS_RT_DBREG_STATUS))
        return false;
    for (uint32_t index = 0; index != site.outputCount; ++index)
      if (!output(index) || (output(index)->kind != TALOS_RT_DBREG_BITS &&
                             output(index)->kind != TALOS_RT_DBREG_LOGIC &&
                             output(index)->kind != TALOS_RT_DBREG_HANDLE &&
                             output(index)->kind != TALOS_RT_DBREG_STATUS))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_DPI_IMPORT:
    if (signature.flags != 0 || site.inputCount == 0 || site.outputCount == 0 ||
        !bytes(input(0)) || !status(output(site.outputCount - 1)))
      return false;
    for (uint32_t index = 1; index != site.inputCount; ++index)
      if (!input(index) || (input(index)->kind != TALOS_RT_DBREG_BITS &&
                            input(index)->kind != TALOS_RT_DBREG_LOGIC &&
                            input(index)->kind != TALOS_RT_DBREG_STRING &&
                            input(index)->kind != TALOS_RT_DBREG_REAL32 &&
                            input(index)->kind != TALOS_RT_DBREG_REAL64 &&
                            input(index)->kind != TALOS_RT_DBREG_MANAGED))
        return false;
    for (uint32_t index = 0; index + 1 != site.outputCount; ++index)
      if (!output(index) || (output(index)->kind != TALOS_RT_DBREG_BITS &&
                             output(index)->kind != TALOS_RT_DBREG_LOGIC &&
                             output(index)->kind != TALOS_RT_DBREG_STRING &&
                             output(index)->kind != TALOS_RT_DBREG_REAL32 &&
                             output(index)->kind != TALOS_RT_DBREG_REAL64 &&
                             output(index)->kind != TALOS_RT_DBREG_MANAGED))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_CLASS_ALLOC:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           managed(output(0));
  case TALOS_RT_INTRINSIC_V1_CLASS_COPY:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_CLASS_IS_INSTANCE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_CLASS_ID:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_CLASS_CAST:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_CLASS_FIELD_REF:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managedRef(output(0));
  case TALOS_RT_INTRINSIC_V1_MANAGED_WATCH:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 &&
           (managedRef(input(0)) || managed(input(0))) &&
           twoStateBits(input(1), 64) && twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_MANAGED_LOAD:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managedRef(input(0)) &&
           twoStateBits(input(1), 64) && managedValue(output(0));
  case TALOS_RT_INTRINSIC_V1_MANAGED_STORE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && managedRef(input(0)) &&
           managedValue(input(1)) && twoStateBits(input(2), 64);
  case TALOS_RT_INTRINSIC_V1_MANAGED_OVERRIDE:
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 0 && managedRef(input(0)) &&
           managedValue(input(1)) && twoStateBits(input(2), 64) &&
           twoStateBits(input(3), 64) && twoStateBits(input(4), 64);
  case TALOS_RT_INTRINSIC_V1_MANAGED_RELEASE_OVERRIDE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && managedRef(input(0)) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64);
  case TALOS_RT_INTRINSIC_V1_MANAGED_NBA:
    return signature.flags == 0 &&
           (site.inputCount == 3 || site.inputCount == 4) &&
           site.outputCount == 0 &&
           (managedRef(input(0)) || managed(input(0))) &&
           managedValue(input(1)) && twoStateBits(input(2), 64) &&
           (site.inputCount == 3 || twoStateBits(input(3), 64));
  case TALOS_RT_INTRINSIC_V1_MANAGED_NBA_MASKED:
    // Destination, positioned value, plane size, positioned mask, delay.
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 0 &&
           (managedRef(input(0)) || managed(input(0))) && numeric(input(1)) &&
           twoStateBits(input(2), 64) && numeric(input(3)) &&
           input(3)->width == input(1)->width && twoStateBits(input(4), 64);
  case TALOS_RT_INTRINSIC_V1_ARGUMENT_REF_FROM_REF:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && handle(input(0)) && argumentRef(output(0));
  case TALOS_RT_INTRINSIC_V1_ARGUMENT_REF_FROM_MANAGED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managedRef(input(0)) &&
           argumentRef(output(0));
  case TALOS_RT_INTRINSIC_V1_REFERENCE_PATH_INDEX:
    return signature.flags == 0 &&
           (site.inputCount == 2 || site.inputCount == 3) &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) &&
           (site.inputCount == 2 || argumentRef(input(2))) &&
           managed(output(0));
  case TALOS_RT_INTRINSIC_V1_REFERENCE_PATH_STRING_CHARACTER:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && string(input(0)) &&
           twoStateBits(input(1), 64) && argumentRef(input(2)) &&
           managed(output(0));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_OPTION_REFERENCE:
    if (signature.flags != 0 || site.inputCount != 6 || site.outputCount != 1 ||
        !managed(output(0)))
      return false;
    for (uint32_t index = 0; index != 6; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_TYPE_OPTION_REFERENCE:
    if (signature.flags != 0 || site.inputCount != 7 || site.outputCount != 1 ||
        !argumentRef(input(0)) || !managed(output(0)))
      return false;
    for (uint32_t index = 1; index != 7; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_REFERENCE_PATH_AGGREGATE_ELEMENT:
    if (signature.flags != 0 || site.inputCount != 15 ||
        site.outputCount != 1 || !argumentRef(input(0)) ||
        !twoStateBits(input(1), 64) || !managed(output(0)))
      return false;
    for (uint32_t index = 2; index != 14; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return input(14) && input(14)->kind == TALOS_RT_DBREG_BYTES;
  case TALOS_RT_INTRINSIC_V1_CONTAINER_SIZE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_CONTAINER_CREATE_LIKE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && managed(input(0)) && managed(input(1)) &&
           twoStateBits(input(2), 64) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_CONTAINER_READ:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managedValue(output(0));
  case TALOS_RT_INTRINSIC_V1_CONTAINER_WRITE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managedValue(input(2));
  case TALOS_RT_INTRINSIC_V1_CONTAINER_CREATE:
    if (signature.flags != 0 ||
        (site.inputCount != 10 && site.inputCount != 11) ||
        site.outputCount != 1 || !managed(output(0)))
      return false;
    for (uint32_t index = 0; index != 7; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    if (!bytes(input(7)) || (site.inputCount == 11 && !bytes(input(8))))
      return false;
    return twoStateBits(input(site.inputCount - 2), 64) &&
           twoStateBits(input(site.inputCount - 1), 64);
  case TALOS_RT_INTRINSIC_V1_CONTAINER_CLONE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managed(input(0)) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_CONTAINER_IMPORT_FIXED:
    if (signature.flags != 0 || site.inputCount != 7 || site.outputCount != 0 ||
        !managed(input(0)) || !managedValue(input(1)))
      return false;
    for (uint32_t index = 2; index != 7; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_CONTAINER_EXPORT_FIXED:
    if (signature.flags != 0 || site.inputCount != 6 || site.outputCount != 1 ||
        !managed(input(0)) || !managedValue(output(0)))
      return false;
    for (uint32_t index = 1; index != 6; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_CONTAINER_EXPORT_BITSTREAM:
    if (signature.flags == 1 || signature.flags == 2)
      return site.inputCount == 2 && site.outputCount == 3 &&
             (numeric(input(0)) || managed(input(0)) || string(input(0))) &&
             bytes(input(1)) && numeric(output(0)) &&
             twoStateBits(output(1), 1) && twoStateBits(output(2), 64);
    if (signature.flags == 3 || signature.flags == 4)
      return site.inputCount == 1 && site.outputCount == 3 &&
             (numeric(input(0)) || managed(input(0)) || string(input(0))) &&
             numeric(output(0)) && twoStateBits(output(1), 1) &&
             twoStateBits(output(2), 64);
    if (signature.flags != 0 || site.inputCount != 8 || site.outputCount != 1 ||
        !managed(input(0)) || !numeric(output(0)))
      return false;
    for (uint32_t index = 1; index != 8; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_AGGREGATE_EXPORT_BITSTREAM:
  case TALOS_RT_INTRINSIC_V1_AGGREGATE_IMPORT_BITSTREAM:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && numeric(input(0)) && bytes(input(1)) &&
           numeric(output(0));
  case TALOS_RT_INTRINSIC_V1_CONTAINER_SWAP:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && managed(input(0)) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64);
  case TALOS_RT_INTRINSIC_V1_CONTAINER_DELETE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && managed(input(0));
  case TALOS_RT_INTRINSIC_V1_QUEUE_DELETE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && managed(input(0)) &&
           twoStateBits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_QUEUE_INSERT:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managedValue(input(2));
  case TALOS_RT_INTRINSIC_V1_MAILBOX_CREATE:
    if (signature.flags != 0 || site.inputCount != 8 || site.outputCount != 1 ||
        !managed(output(0)))
      return false;
    for (uint32_t index = 0; index != 6; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return bytes(input(6)) && twoStateBits(input(7), 64);
  case TALOS_RT_INTRINSIC_V1_MAILBOX_NUM:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_VPI_FRAME_BIND:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           input(0)->flags == 0 && input(0)->size == 8 && handle(input(1)) &&
           input(1)->flags == 0 && input(1)->width == 256 &&
           input(1)->size == 32;
  case TALOS_RT_INTRINSIC_V1_BOX_BIND_TYPE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && managed(input(0)) &&
           twoStateBits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_BOX_IS_TYPE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_MAILBOX_TRY_PUT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           managedValue(input(1)) && twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_MAILBOX_TRY_PEEK:
  case TALOS_RT_INTRINSIC_V1_MAILBOX_TRY_GET:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 2 && managed(input(0)) &&
           twoStateBits(output(0), 1) && managedValue(output(1));
  case TALOS_RT_INTRINSIC_V1_SEMAPHORE_CREATE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 32) &&
           managed(output(0));
  case TALOS_RT_INTRINSIC_V1_SEMAPHORE_PUT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && managed(input(0)) &&
           twoStateBits(input(1), 32);
  case TALOS_RT_INTRINSIC_V1_SEMAPHORE_TRY_GET:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 32) && twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_EVENT_CREATE:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && handle(output(0));
  case TALOS_RT_INTRINSIC_V1_RANDOM_BOUNDED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_DISTRIBUTION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 2 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 32) && twoStateBits(input(2), 32) &&
           twoStateBits(input(3), 32) && twoStateBits(output(0), 32) &&
           twoStateBits(output(1), 32);
  case TALOS_RT_INTRINSIC_V1_RANDOM_CYCLE_NEXT:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 2 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(output(0), 64) && twoStateBits(output(1), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_NEXT:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_INITIALIZATION_ENTER:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_INITIALIZATION_LEAVE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && twoStateBits(input(0), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_LEGACY:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_RANDOM_SEED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && twoStateBits(input(0), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_GET_STATE:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 2 && twoStateBits(output(0), 64) &&
           twoStateBits(output(1), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_SET_STATE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_RANDOM_SOLVE:
    if (signature.flags != 0 || site.inputCount < 5 || site.outputCount != 2 ||
        !bytes(input(0)) || !twoStateBits(output(0), 64) ||
        !twoStateBits(output(1), 1))
      return false;
    for (uint32_t index = 1; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_RANDOM_SOLVE_STATE:
    if (signature.flags != 0 || site.inputCount < 7 || site.outputCount != 3 ||
        !bytes(input(0)) || !twoStateBits(output(0), 64) ||
        !twoStateBits(output(1), 1) || !twoStateBits(output(2), 64))
      return false;
    for (uint32_t index = 1; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_RANDOM_SOLVE_WIDE_STATE:
    if (signature.flags != 0 || site.inputCount < 7 || site.outputCount != 3 ||
        !bytes(input(0)) || !twoStateBits(input(1)) ||
        !twoStateBits(input(2), input(1)->width) ||
        !twoStateBits(output(0), input(1)->width) ||
        !twoStateBits(output(1), 1) || !twoStateBits(output(2), 64))
      return false;
    for (uint32_t index = 3; index != 7; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    for (uint32_t index = 7; index != site.inputCount; ++index)
      if (!twoStateBits(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_RANDOM_CYCLE_SAMPLE:
    if (signature.flags != 0 || site.inputCount < 11 || site.outputCount != 6 ||
        !bytes(input(0)) || !twoStateBits(input(1)) ||
        !twoStateBits(input(2), input(1)->width) || !string(input(8)) ||
        !twoStateBits(input(9), 32) || !twoStateBits(input(10), 32) ||
        !twoStateBits(output(0), input(1)->width) ||
        !twoStateBits(output(1), 1) || !string(output(5)))
      return false;
    for (uint32_t index = 3; index != 8; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    for (uint32_t index = 2; index != 5; ++index)
      if (!twoStateBits(output(index), 64))
        return false;
    for (uint32_t index = 11; index != site.inputCount; ++index)
      if (!twoStateBits(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERAGE_POINT_HIT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 1);
  case TALOS_RT_INTRINSIC_V1_RANDOM_REAL_TO_RANK:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 2 && floating(input(0)) &&
           twoStateBits(output(0), input(0)->kind == TALOS_RT_DBREG_REAL32
                                       ? TALOS_RT_REAL32_RANK_BITS
                                       : TALOS_RT_REAL64_RANK_BITS) &&
           twoStateBits(output(1), 1);
  case TALOS_RT_INTRINSIC_V1_RANDOM_REAL_FROM_RANK:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && floating(output(0)) &&
           twoStateBits(input(0), output(0)->kind == TALOS_RT_DBREG_REAL32
                                      ? TALOS_RT_REAL32_RANK_BITS
                                      : TALOS_RT_REAL64_RANK_BITS);
  case TALOS_RT_INTRINSIC_V1_COVERAGE_CONTROL_DEFINITION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 1 && twoStateBits(input(0), 32) &&
           twoStateBits(input(1), 32) && twoStateBits(input(2), 32) &&
           string(input(3)) && twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_COVERAGE_CONTROL_INSTANCE:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 1 && twoStateBits(input(0), 32) &&
           twoStateBits(input(1), 32) && twoStateBits(input(2), 32) &&
           twoStateBits(input(3), 64) && twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_COVERAGE_QUERY_DEFINITION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 1 && twoStateBits(input(0), 32) &&
           twoStateBits(input(1), 32) && string(input(2)) &&
           twoStateBits(input(3), 64) && twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_COVERAGE_QUERY_INSTANCE:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 1 && twoStateBits(input(0), 32) &&
           twoStateBits(input(1), 32) && twoStateBits(input(2), 64) &&
           twoStateBits(input(3), 64) && twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_COVERAGE_DATABASE_SAVE:
  case TALOS_RT_INTRINSIC_V1_COVERAGE_DATABASE_MERGE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && twoStateBits(input(0), 32) &&
           string(input(1)) && twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FUNCTIONAL_COVERAGE_GET:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && output(0) &&
           output(0)->kind == TALOS_RT_DBREG_REAL64;
  case TALOS_RT_INTRINSIC_V1_FUNCTIONAL_COVERAGE_SET_DB_NAME:
  case TALOS_RT_INTRINSIC_V1_FUNCTIONAL_COVERAGE_LOAD_DB:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && string(input(0));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_PREPARE:
    if (signature.flags != 0 || site.inputCount < 2 || site.outputCount != 1 ||
        !twoStateBits(output(0), 64) || !twoStateBits(input(0), 64) ||
        !twoStateBits(input(1), 64))
      return false;
    for (uint32_t index = 2; index != site.inputCount; ++index)
      if (!numeric(input(index)) && !floating(input(index)) &&
          !string(input(index)) && !managed(input(index)) &&
          !event(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_CANDIDATES:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && managed(input(2)) &&
           twoStateBits(input(3), 64);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_BIND_WITH:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && managed(input(2));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_RELEASE_PREPARATION:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && twoStateBits(input(0), 64);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_CREATE:
    if (signature.flags != 0 || site.inputCount < 3 || site.outputCount != 1 ||
        !twoStateBits(output(0), 64) || !twoStateBits(input(0), 64) ||
        !twoStateBits(input(1), 64) || !twoStateBits(input(2), 64))
      return false;
    for (uint32_t index = 3; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64) && !numeric(input(index)) &&
          !floating(input(index)) && !argumentRef(input(index)) &&
          !string(input(index)) && !managed(input(index)) &&
          !event(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_CLOCK_EVENT_REGISTER:
  case TALOS_RT_INTRINSIC_V1_EVENT_SNAPSHOT_REGISTER:
    if (signature.flags != 0 || site.inputCount < 5 || site.outputCount != 0)
      return false;
    for (uint32_t index = 0; index != 5; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    for (uint32_t index = 5; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64) && !numeric(input(index)) &&
          !handle(input(index)) && !managed(input(index)) &&
          !argumentRef(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_BLOCK_EVENT_REGISTER:
    if (signature.flags != 0 || site.inputCount < 5 || site.outputCount != 0 ||
        !twoStateBits(input(0), 64) ||
        (!managed(input(1)) && !twoStateBits(input(1), 64)))
      return false;
    for (uint32_t index = 2; index != 5; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    for (uint32_t index = 5; index != site.inputCount; ++index)
      if (!twoStateBits(input(index), 64) && !numeric(input(index)) &&
          !handle(input(index)) && !managed(input(index)) &&
          !argumentRef(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_BLOCK_EVENT_FIRE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) &&
           (managed(input(2)) || twoStateBits(input(2), 64));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SET_ENABLED:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SET_NAME:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           string(input(1));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SET_INTEGER_OPTION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(input(3), 64);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_GET_INTEGER_OPTION:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_GET_STRING_OPTION:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           string(output(0));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SET_STRING_OPTION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           string(input(3));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SET_TYPE_INTEGER_OPTION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(input(3), 64);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SET_TYPE_STRING_OPTION:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 0 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           string(input(3));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SAMPLE_ENABLED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_FORMAL_READ:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) &&
           (numeric(output(0)) || string(output(0)) || argumentRef(output(0)) ||
            event(output(0)) ||
            (managed(output(0)) && output(0)->width == 64 &&
             output(0)->size == 8) ||
            floating(output(0)));
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_SAMPLE:
    if (signature.flags != 0 || site.inputCount < 2 || site.outputCount != 0 ||
        !twoStateBits(input(0), 64) || !twoStateBits(input(1), 64))
      return false;
    for (uint32_t index = 2; index != site.inputCount; ++index)
      if (!numeric(input(index)) && !floating(input(index)) &&
          !string(input(index)) && !managed(input(index)) &&
          !event(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_INSTANCE_QUERY:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 3 && twoStateBits(input(0), 64) && output(0) &&
           twoStateBits(input(1), 64) &&
           output(0)->kind == TALOS_RT_DBREG_REAL64 &&
           twoStateBits(output(1), 32) && twoStateBits(output(2), 32);
  case TALOS_RT_INTRINSIC_V1_COVERGROUP_TYPE_QUERY:
    if (signature.flags != 0 || site.inputCount != 2 || site.outputCount != 3 ||
        !output(0) || output(0)->kind != TALOS_RT_DBREG_REAL64 ||
        !twoStateBits(output(1), 32) || !twoStateBits(output(2), 32))
      return false;
    return twoStateBits(input(0), 64) && twoStateBits(input(1), 64);
  case TALOS_RT_INTRINSIC_V1_ASSOC_CREATE:
    // An element-keyed array also carries its key's element descriptor, trace
    // and equality plan.
    if (signature.flags != 0 ||
        (site.inputCount != 9 && site.inputCount != 17) ||
        site.outputCount != 1 || !managed(output(0)))
      return false;
    for (uint32_t index = 0; index != 6; ++index)
      if (!twoStateBits(input(index), 64))
        return false;
    if (site.inputCount == 17) {
      for (uint32_t index = 9; index != 15; ++index)
        if (!twoStateBits(input(index), 64))
          return false;
      if (!bytes(input(15)) || !bytes(input(16)))
        return false;
    }
    return bytes(input(6)) && twoStateBits(input(7), 64) &&
           twoStateBits(input(8), 64);
  case TALOS_RT_INTRINSIC_V1_ASSOC_READ:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) && assocKey(input(1)) &&
           managedValue(output(0));
  case TALOS_RT_INTRINSIC_V1_ASSOC_WRITE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 0 && managed(input(0)) && assocKey(input(1)) &&
           managedValue(input(2));
  case TALOS_RT_INTRINSIC_V1_ASSOC_EXISTS:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) && assocKey(input(1)) &&
           twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_ASSOC_DELETE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && managed(input(0)) && assocKey(input(1));
  case TALOS_RT_INTRINSIC_V1_ASSOC_DEFAULT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 0 && managed(input(0)) && managedValue(input(1));
  case TALOS_RT_INTRINSIC_V1_ASSOC_TRAVERSE:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 2 && managed(input(0)) && assocKey(input(1)) &&
           twoStateBits(input(2), 64) && twoStateBits(input(3), 64) &&
           input(1) && output(0) && compatible(*input(1), *output(0)) &&
           twoStateBits(output(1), 1);
  case TALOS_RT_INTRINSIC_V1_REFERENCE_PATH_ASSOC:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && managed(input(0)) && assocKey(input(1)) &&
           argumentRef(input(2)) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_ARGUMENT_REF_FROM_PATH:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managed(input(0)) && argumentRef(output(0));
  case TALOS_RT_INTRINSIC_V1_ARGUMENT_REF_LOAD:
    return signature.flags == 0 && site.inputCount == 4 &&
           site.outputCount == 1 && argumentRef(input(0)) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(input(3), 64) && managedValue(output(0));
  case TALOS_RT_INTRINSIC_V1_ARGUMENT_REF_STORE:
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 0 && argumentRef(input(0)) &&
           managedValue(input(1)) && twoStateBits(input(2), 64) &&
           twoStateBits(input(3), 64) && twoStateBits(input(4), 64);
  case TALOS_RT_INTRINSIC_V1_MANAGED_ROOT_EXTRACT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && numeric(input(0)) &&
           twoStateBits(input(1), 64) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_MANAGED_CANDIDATE_ROOT:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && numeric(input(0)) &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           managed(output(0));
  case TALOS_RT_INTRINSIC_V1_WEAK_CREATE:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && managed(input(0)) &&
           twoStateBits(input(1), 64) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_WEAK_GET:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && managed(input(0)) && managed(output(0));
  case TALOS_RT_INTRINSIC_V1_WEAK_CLEAR:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && managed(input(0));
  case TALOS_RT_INTRINSIC_V1_GC_SAFEPOINT:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_STRING_LITERAL:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && bytes(input(0)) && string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_FROM_PACKED:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && numeric(input(0)) && string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_TO_PACKED:
    return site.inputCount == 1 && string(input(0)) && numeric(output(0)) &&
           ((signature.flags == 0 && site.outputCount == 1) ||
            (signature.flags == 1 && site.outputCount == 2 &&
             twoStateBits(output(1), 1) && output(0)->width != 0 &&
             (output(0)->width % 8) == 0));
  case TALOS_RT_INTRINSIC_V1_STRING_CONCAT:
    if (signature.flags != 0 || site.outputCount != 1 || !string(output(0)))
      return false;
    for (uint32_t index = 0; index != site.inputCount; ++index)
      if (!string(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_STRING_REPEAT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_LENGTH:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && string(input(0)) && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_STRING_GETC:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           bits(output(0), 8);
  case TALOS_RT_INTRINSIC_V1_STRING_PUTC:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           bits(input(2), 8) && string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_SUBSTR:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           bits(input(2), 64) && string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_COMPARE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && string(input(0)) && string(input(1)) &&
           bits(input(2), 64) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_STRING_CASE_CONVERT:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_PARSE_INTEGER:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_STRING_PARSE_LOGIC:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           output(0) && output(0)->kind == TALOS_RT_DBREG_LOGIC &&
           output(0)->width == 64;
  case TALOS_RT_INTRINSIC_V1_STRING_PARSE_REAL:
  case TALOS_RT_INTRINSIC_V1_STRING_PARSE_REAL_CONSTANT:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && string(input(0)) && output(0) &&
           output(0)->kind == TALOS_RT_DBREG_REAL64;
  case TALOS_RT_INTRINSIC_V1_STRING_FORMAT_INTEGER:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && bits(input(0), 64) && bits(input(1), 64) &&
           bits(input(2), 64) && string(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_FORMAT_REAL:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && input(0) &&
           input(0)->kind == TALOS_RT_DBREG_REAL64 && string(output(0));
  case TALOS_RT_INTRINSIC_V1_FORMAT:
    if (site.inputCount < 1 || site.outputCount != 1 || !bytes(input(0)) ||
        !string(output(0)))
      return false;
    for (uint32_t index = 1; index < site.inputCount; ++index)
      if (!bytes(input(index)) && !numeric(input(index)) &&
          !floating(input(index)) && !string(input(index)) &&
          !managed(input(index)) && !handle(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_DISPLAY:
    if (site.inputCount < 2 || site.outputCount != 0 || !bytes(input(0)) ||
        !bits(input(1), 32))
      return false;
    for (uint32_t index = 2; index < site.inputCount; ++index)
      if (!bytes(input(index)) && !numeric(input(index)) &&
          !floating(input(index)) && !string(input(index)) &&
          !managed(input(index)) && !handle(input(index)))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_FINISH:
  case TALOS_RT_INTRINSIC_V1_STOP:
  case TALOS_RT_INTRINSIC_V1_FATAL:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && bits(input(0), 32);
  case TALOS_RT_INTRINSIC_V1_ERROR:
  case TALOS_RT_INTRINSIC_V1_PROGRAM_EXIT:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 0;
  case TALOS_RT_INTRINSIC_V1_TERMINATION_REQUESTED:
  case TALOS_RT_INTRINSIC_V1_PROGRAM_OWNED:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && bits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_TIME_NOW:
  case TALOS_RT_INTRINSIC_V1_SCHEDULER_COHORT:
    return signature.flags == 0 && site.inputCount == 0 &&
           site.outputCount == 1 && twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_TIME_TO_REAL:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && twoStateBits(input(0), 64) &&
           twoStateBits(input(1), 64) && output(0) &&
           output(0)->kind == TALOS_RT_DBREG_REAL64;
  case TALOS_RT_INTRINSIC_V1_TIME_FROM_REAL:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && input(0) &&
           input(0)->kind == TALOS_RT_DBREG_REAL64 &&
           twoStateBits(input(1), 64) && twoStateBits(input(2), 64) &&
           twoStateBits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_REAL_FROM_INTEGER:
    return signature.flags <= 1 && site.inputCount == 1 &&
           site.outputCount == 1 && twoStateBits(input(0)) &&
           floating(output(0));
  case TALOS_RT_INTRINSIC_V1_REAL_TO_INTEGER:
    return signature.flags <= 1 && site.inputCount == 1 &&
           site.outputCount == 1 && input(0) &&
           input(0)->kind == TALOS_RT_DBREG_REAL64 && twoStateBits(output(0));
  case TALOS_RT_INTRINSIC_V1_REAL_COMPARE:
    return signature.flags <= 5 && site.inputCount == 2 &&
           site.outputCount == 1 && input(0) && input(1) &&
           input(0)->kind == TALOS_RT_DBREG_REAL64 &&
           input(1)->kind == TALOS_RT_DBREG_REAL64 &&
           twoStateBits(output(0), 1);
  case TALOS_RT_INTRINSIC_V1_COUNT_BITS:
    if (signature.flags != 0 || site.inputCount < 2 || site.outputCount != 1 ||
        !numeric(input(0)) || !twoStateBits(output(0), 32))
      return false;
    for (uint32_t index = 1; index != site.inputCount; ++index)
      if (!bits(input(index), 1))
        return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_CLOG2:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && numeric(input(0)) &&
           twoStateBits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_OPEN_MCD:
    return site.inputCount == 1 && site.outputCount == 1 && bytes(input(0)) &&
           bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_OPEN:
    return site.inputCount == 2 && site.outputCount == 1 && bytes(input(0)) &&
           bytes(input(1)) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_OPEN_STRING_MCD:
    return site.inputCount == 1 && site.outputCount == 1 && string(input(0)) &&
           bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_OPEN_STRING:
    return site.inputCount == 2 && site.outputCount == 1 && string(input(0)) &&
           string(input(1)) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_TIME_FORMAT:
    return site.inputCount == 4 && site.outputCount == 0 &&
           bits(input(0), 32) && bits(input(1), 32) && bytes(input(2)) &&
           bits(input(3), 32);
  case TALOS_RT_INTRINSIC_V1_TIME_SCAN_SCALE:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && floating(input(0)) && bits(input(1), 64) &&
           bits(input(2), 64) && floating(output(0));
  case TALOS_RT_INTRINSIC_V1_STRING_SCAN_FIELD:
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 3 && string(input(0)) && bits(input(1), 32) &&
           bytes(input(2)) && bits(input(3), 64) && bits(input(4), 64) &&
           string(output(0)) && bits(output(1), 32) && bits(output(2), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_SCAN_FIELD:
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 3 && bits(input(0), 32) && bits(input(1), 32) &&
           bytes(input(2)) && bits(input(3), 64) && bits(input(4), 64) &&
           string(output(0)) && bits(output(1), 32) && bits(output(2), 32);
  case TALOS_RT_INTRINSIC_V1_SCAN_DYNAMIC_VALIDATE:
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 32) &&
           bits(input(2), 64) && bits(input(3), 64) && bits(input(4), 64) &&
           bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_STRING_SCAN_DYNAMIC:
    return signature.flags == 0 && site.inputCount == 9 &&
           site.outputCount == 5 && string(input(0)) && bits(input(1), 32) &&
           string(input(2)) && bits(input(3), 32) && bits(input(4), 32) &&
           bits(input(5), 64) && bits(input(6), 64) && bits(input(7), 64) &&
           bits(input(8), 64) && string(output(0)) && bits(output(1), 32) &&
           bits(output(2), 32) && bits(output(3), 32) && bits(output(4), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_SCAN_DYNAMIC:
    return signature.flags == 0 && site.inputCount == 8 &&
           site.outputCount == 5 && bits(input(0), 32) && string(input(1)) &&
           bits(input(2), 32) && bits(input(3), 32) && bits(input(4), 64) &&
           bits(input(5), 64) && bits(input(6), 64) && bits(input(7), 64) &&
           string(output(0)) && bits(output(1), 32) && bits(output(2), 32) &&
           bits(output(3), 32) && bits(output(4), 32);
  case TALOS_RT_INTRINSIC_V1_STRING_SCAN_RAW:
    if (signature.flags != 0 || site.inputCount != 7 || !string(input(0)) ||
        !bits(input(1), 32) || !bytes(input(2)) || !bits(input(3), 64) ||
        !bits(input(4), 64) || !bits(input(5), 64) || !bits(input(6), 64))
      return false;
    return (site.outputCount == 3 && output(0) &&
            output(0)->kind == TALOS_RT_DBREG_LOGIC && output(0)->width != 0 &&
            bits(output(1), 32) && bits(output(2), 32)) ||
           (site.outputCount == 2 && bits(output(0), 32) &&
            bits(output(1), 32));
  case TALOS_RT_INTRINSIC_V1_FILE_SCAN_RAW:
    if (signature.flags != 0 || site.inputCount != 7 || !bits(input(0), 32) ||
        !bits(input(1), 32) || !bytes(input(2)) || !bits(input(3), 64) ||
        !bits(input(4), 64) || !bits(input(5), 64) || !bits(input(6), 64))
      return false;
    return (site.outputCount == 3 && output(0) &&
            output(0)->kind == TALOS_RT_DBREG_LOGIC && output(0)->width != 0 &&
            bits(output(1), 32) && bits(output(2), 32)) ||
           (site.outputCount == 2 && bits(output(0), 32) &&
            bits(output(1), 32));
  case TALOS_RT_INTRINSIC_V1_FILE_READMEM_TOKEN:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 3 && bits(input(0), 32) && bits(input(1), 64) &&
           output(0) && output(0)->kind == TALOS_RT_DBREG_LOGIC &&
           output(0)->width != 0 && bits(output(1), 32) && bits(output(2), 64);
  case TALOS_RT_INTRINSIC_V1_STOCHASTIC_QUEUE:
    return signature.flags == 0 && site.inputCount == 5 &&
           site.outputCount == 3 && bits(input(0), 64) && bits(input(1), 32) &&
           bits(input(2), 32) && bits(input(3), 32) && bits(input(4), 64) &&
           output(0) && output(0)->kind == TALOS_RT_DBREG_LOGIC &&
           output(0)->width == 64 && output(1) &&
           output(1)->kind == TALOS_RT_DBREG_LOGIC && output(1)->width == 64 &&
           bits(output(2), 32);
  case TALOS_RT_INTRINSIC_V1_PLUSARG_TEST:
    return site.inputCount == 1 && site.outputCount == 1 && string(input(0)) &&
           bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_PLUSARG_VALUE:
    return site.inputCount == 1 && site.outputCount == 2 && string(input(0)) &&
           string(output(0)) && bits(output(1), 32);
  case TALOS_RT_INTRINSIC_V1_PLUSARG_SCAN:
    return site.inputCount == 1 && site.outputCount == 3 && string(input(0)) &&
           string(output(0)) && bits(output(1), 32) && bits(output(2), 32);
  case TALOS_RT_INTRINSIC_V1_PLUSARG_PARSE_LOGIC:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && string(input(0)) && bits(input(1), 64) &&
           output(0) && output(0)->kind == TALOS_RT_DBREG_LOGIC &&
           output(0)->width != 0;
  case TALOS_RT_INTRINSIC_V1_PLUSARG_PARSE_REAL:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && string(input(0)) && output(0) &&
           output(0)->kind == TALOS_RT_DBREG_REAL64;
  case TALOS_RT_INTRINSIC_V1_SYSTEM:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && string(input(0)) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_GETLINE_STRING:
  case TALOS_RT_INTRINSIC_V1_FILE_ERROR_STRING:
    return site.inputCount == 1 && site.outputCount == 2 &&
           bits(input(0), 32) && string(output(0)) && bits(output(1), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_CLOSE:
  case TALOS_RT_INTRINSIC_V1_FILE_FLUSH:
    return site.inputCount == 1 && site.outputCount == 0 && bits(input(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_GETC:
  case TALOS_RT_INTRINSIC_V1_FILE_EOF:
  case TALOS_RT_INTRINSIC_V1_FILE_REWIND:
    return site.inputCount == 1 && site.outputCount == 1 &&
           bits(input(0), 32) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_UNGETC:
    return site.inputCount == 2 && site.outputCount == 1 &&
           bits(input(0), 32) && bits(input(1), 32) && bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_GETLINE:
  case TALOS_RT_INTRINSIC_V1_FILE_READ_PACKED:
    return site.inputCount == 1 && site.outputCount == 2 &&
           bits(input(0), 32) && numeric(output(0)) && bits(output(1), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_SEEK:
    return site.inputCount == 3 && site.outputCount == 1 &&
           bits(input(0), 32) && bits(input(1), 64) && bits(input(2), 32) &&
           bits(output(0), 32);
  case TALOS_RT_INTRINSIC_V1_FILE_TELL:
    return site.inputCount == 1 && site.outputCount == 1 &&
           bits(input(0), 32) && bits(output(0), 64);
  case TALOS_RT_INTRINSIC_V1_VPI_RESOLUTION_PREPARE:
  case TALOS_RT_INTRINSIC_V1_VPI_CALL_PREPARE:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 1 && vpiIdentity(input(0)) &&
           vpiIdentity(output(0));
  case TALOS_RT_INTRINSIC_V1_VPI_FRAME_ENTER_PREPARED:
    return signature.flags == 0 && site.inputCount == 2 &&
           site.outputCount == 1 && vpiIdentity(input(0)) &&
           vpiIdentity(input(1)) && vpiIdentity(output(0));
  case TALOS_RT_INTRINSIC_V1_VPI_FRAME_ENTER:
    return signature.flags == 0 && site.inputCount == 3 &&
           site.outputCount == 1 && vpiIdentity(input(0)) &&
           vpiIdentity(input(1)) && vpiIdentity(input(2)) &&
           vpiIdentity(output(0));
  case TALOS_RT_INTRINSIC_V1_VPI_FRAME_CHECKPOINT:
  case TALOS_RT_INTRINSIC_V1_VPI_FRAME_LEAVE:
  case TALOS_RT_INTRINSIC_V1_VPI_CALL_FINISH:
    return signature.flags == 0 && site.inputCount == 1 &&
           site.outputCount == 0 && vpiIdentity(input(0));
  case TALOS_RT_INTRINSIC_V1_VPI_ROOT:
    return site.inputCount == 0 && site.outputCount == 2 && cursor(output(0)) &&
           status(output(1));
  case TALOS_RT_INTRINSIC_V1_VPI_CHILD:
  case TALOS_RT_INTRINSIC_V1_VPI_SIBLING:
    return site.inputCount == 1 && site.outputCount == 2 && cursor(input(0)) &&
           cursor(output(0)) && status(output(1));
  case TALOS_RT_INTRINSIC_V1_VPI_CHILD_AT:
  case TALOS_RT_INTRINSIC_V1_VPI_TYPE_CHILD:
    return site.inputCount == 2 && site.outputCount == 2 && cursor(input(0)) &&
           bits(input(1), 64) && cursor(output(0)) && status(output(1));
  case TALOS_RT_INTRINSIC_V1_VPI_LOOKUP:
    return site.inputCount == 1 && site.outputCount == 2 && bytes(input(0)) &&
           cursor(output(0)) && status(output(1));
  case TALOS_RT_INTRINSIC_V1_VPI_INFO:
    if (site.inputCount != 1 || site.outputCount != 8 || !cursor(input(0)) ||
        !bits(output(0), 32) || !bits(output(1), 32) || !bits(output(2), 64) ||
        !cursor(output(3)) || !bits(output(4), 64) || !bits(output(5), 64) ||
        !bits(output(6), 64) || !status(output(7)))
      return false;
    return true;
  case TALOS_RT_INTRINSIC_V1_VPI_NAME:
    return site.inputCount == 1 && site.outputCount == 3 && cursor(input(0)) &&
           bits(output(0), 64) && bits(output(1), 64) && status(output(2));
  case TALOS_RT_INTRINSIC_V1_VPI_TYPE_INFO:
    if (site.inputCount != 1 || site.outputCount != 12 || !cursor(input(0)) ||
        !bits(output(0), 32) || !bits(output(1), 32))
      return false;
    for (uint32_t index = 2; index != 11; ++index)
      if (!bits(output(index), 64))
        return false;
    return status(output(11));
  case TALOS_RT_INTRINSIC_V1_VPI_READ:
    return site.inputCount == 1 && site.outputCount == 2 && cursor(input(0)) &&
           numeric(output(0)) && status(output(1));
  case TALOS_RT_INTRINSIC_V1_VPI_WRITE:
    return site.inputCount == 2 && site.outputCount == 1 && cursor(input(0)) &&
           numeric(input(1)) && status(output(0));
  default:
    return false;
  }
}

static bool validNativeMethodSite(const Image &image, const Function &function,
                                  const Instruction &instruction) {
  uint64_t offset = instruction.auxiliary;
  if (offset > image.constantSize || image.constantSize - offset < 24)
    return false;
  NativeMethodCallSite site =
      nativeMethodCallSite(image, instruction.auxiliary);
  const uint8_t *header = image.data + image.constants + offset;
  uint64_t count = uint64_t{site.argumentPlanes} + site.resultPlanes;
  if (read32(header + 12) || site.resultSize > UINT32_MAX ||
      count > (image.constantSize - offset - 24) / 16 ||
      instruction.source2 < (isStaticMethodCall(instruction) ? 1u : 2u) ||
      instruction.source1 > image.operandCount ||
      instruction.source2 > image.operandCount - instruction.source1 ||
      site.outputMap > image.operandCount ||
      instruction.flags > image.operandCount - site.outputMap)
    return false;
  uint64_t cursor = 0, previousEnd = 0;
  auto check = [&](uint32_t reg, bool result) {
    if (!validRegister(function, reg))
      return false;
    Layout layout = layoutAt(image, function, reg);
    switch (layout.kind) {
    case TALOS_RT_DBREG_BITS:
    case TALOS_RT_DBREG_LOGIC:
    case TALOS_RT_DBREG_REAL32:
    case TALOS_RT_DBREG_REAL64:
    case TALOS_RT_DBREG_MANAGED:
    case TALOS_RT_DBREG_STRING:
    case TALOS_RT_DBREG_MANAGED_REF:
    case TALOS_RT_DBREG_ARGUMENT_REF:
      break;
    default:
      return false;
    }
    uint32_t planes = layout.kind == TALOS_RT_DBREG_LOGIC ||
                              layout.kind == TALOS_RT_DBREG_MANAGED_REF
                          ? 2
                          : 1;
    uint64_t stride = layout.size / planes;
    uint64_t nativeSize = layout.kind == TALOS_RT_DBREG_MANAGED_REF
                              ? 8
                              : (uint64_t{layout.width} + 7) / 8;
    for (uint32_t plane = 0; plane != planes; ++plane, ++cursor) {
      if (cursor >= (result ? count : site.argumentPlanes))
        return false;
      const uint8_t *record = site.planes + cursor * 16;
      uint64_t nativeOffset = read32(record + 12);
      if (read32(record) != reg || read32(record + 4) != plane * stride ||
          read32(record + 8) != nativeSize || nativeSize > stride ||
          (!result && nativeOffset != 0) ||
          (result &&
           (nativeOffset < previousEnd || nativeOffset > site.resultSize ||
            nativeSize > site.resultSize - nativeOffset)))
        return false;
      if (result)
        previousEnd = nativeOffset + nativeSize;
    }
    return true;
  };
  for (uint32_t index = isStaticMethodCall(instruction) ? 1 : 2;
       index != instruction.source2; ++index)
    if (!check(operandAt(image, instruction.source1 + index).second, false))
      return false;
  if (cursor != site.argumentPlanes)
    return false;
  for (uint32_t index = 0; index != instruction.flags; ++index)
    if (!check(operandAt(image, site.outputMap + index).first, true))
      return false;
  return cursor == count && (site.resultPlanes != 0 || site.resultSize == 0);
}

bool validateInitialization(const Image &image, const Function &function,
                            uint32_t functionIndex) {
  const uint64_t begin = function.firstInstruction;
  const uint64_t count = function.instructionCount;
  const uint64_t registerCount = function.layoutCount;
  const uint64_t stateWordCount =
      registerCount / 64 + (registerCount % 64 != 0);
  if (stateWordCount > std::numeric_limits<size_t>::max())
    return false;
  const size_t stateWords = static_cast<size_t>(stateWordCount);
  using State = std::vector<uint64_t>;
  auto setInitialized = [&](State &state, uint32_t reg) {
    if (reg >= registerCount)
      return false;
    state[reg / 64] |= uint64_t{1} << (reg % 64);
    return true;
  };
  std::vector<std::optional<State>> incoming(static_cast<size_t>(count));
  std::deque<uint64_t> worklist;
  auto merge = [&](uint64_t pc, const State &state) {
    if (pc < begin || pc >= begin + count)
      return false;
    std::optional<State> &target = incoming[static_cast<size_t>(pc - begin)];
    bool changed = false;
    if (!target) {
      target = state;
      changed = true;
    } else {
      for (size_t word = 0; word != stateWords; ++word) {
        uint64_t next = (*target)[word] & state[word];
        changed |= next != (*target)[word];
        (*target)[word] = next;
      }
    }
    if (changed)
      worklist.push_back(pc);
    return true;
  };
  State seed(stateWords);
  bool process = (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0;
  if (!process)
    for (uint32_t argument = 0; argument != function.argumentCount; ++argument)
      if (!setInitialized(seed, argument))
        return false;
  for (uint64_t index = 0; index != function.continuationCount; ++index) {
    // Callable continuations are internal synchronous branch targets, not
    // independent scheduler entries. Their incoming state is propagated from
    // process.control below. Process continuations are true resumptions and
    // begin with only the registers reconstructed by their entry shim.
    if (!process && index != 0)
      continue;
    Continuation entry =
        continuationAt(image, function.firstContinuation + index);
    State entryState = seed;
    if (process)
      std::fill(entryState.begin(), entryState.end(), uint64_t{0});
    if (!merge(entry.instruction, entryState))
      return false;
  }
  auto defineMap = [&](State &state, uint64_t first, uint64_t mapCount) {
    for (uint64_t index = 0; index != mapCount; ++index) {
      uint32_t destination = operandAt(image, first + index).first;
      if (!setInitialized(state, destination))
        return false;
    }
    return true;
  };
  while (!worklist.empty()) {
    uint64_t pc = worklist.front();
    worklist.pop_front();
    State state = *incoming[static_cast<size_t>(pc - begin)];
    Instruction instruction = instructionAt(image, pc);
    auto defineDestination = [&] {
      return setInitialized(state, instruction.destination);
    };
    bool fallthrough = true;
    switch (instruction.opcode) {
    case TALOS_RT_DB_CONSTANT:
    case TALOS_RT_DB_MOVE:
    case TALOS_RT_DB_BITCAST:
    case TALOS_RT_DB_NOT:
    case TALOS_RT_DB_AND:
    case TALOS_RT_DB_OR:
    case TALOS_RT_DB_XOR:
    case TALOS_RT_DB_ADD:
    case TALOS_RT_DB_SUB:
    case TALOS_RT_DB_MUL:
    case TALOS_RT_DB_POWER:
    case TALOS_RT_DB_REPLICATE:
    case TALOS_RT_DB_POPCOUNT:
    case TALOS_RT_DB_UDIV:
    case TALOS_RT_DB_SDIV:
    case TALOS_RT_DB_UREM:
    case TALOS_RT_DB_SREM:
    case TALOS_RT_DB_SHL:
    case TALOS_RT_DB_LSHR:
    case TALOS_RT_DB_ASHR:
    case TALOS_RT_DB_COMPARE:
    case TALOS_RT_DB_SELECT:
    case TALOS_RT_DB_REDUCE:
    case TALOS_RT_DB_CONCAT:
    case TALOS_RT_DB_EXTRACT:
    case TALOS_RT_DB_INSERT:
    case TALOS_RT_DB_LOAD_FRAME:
    case TALOS_RT_DB_MAKE_HANDLE:
    case TALOS_RT_DB_MAKE_LOCAL_HANDLE:
    case TALOS_RT_DB_HANDLE_OFFSET:
    case TALOS_RT_DB_HANDLE_ID:
    case TALOS_RT_DB_LOAD_STATE:
    case TALOS_RT_DB_FADD:
    case TALOS_RT_DB_FSUB:
    case TALOS_RT_DB_FMUL:
    case TALOS_RT_DB_FDIV:
    case TALOS_RT_DB_FNEG:
    case TALOS_RT_DB_FCOMPARE:
    case TALOS_RT_DB_FEXT:
    case TALOS_RT_DB_FTRUNC:
    case TALOS_RT_DB_FPOW:
      if (!defineDestination())
        return false;
      break;
    case TALOS_RT_DB_STORE_STATE:
      if ((instruction.flags & TALOS_RT_DB_STORE_STATE_CHANGED) != 0 &&
          !defineDestination())
        return false;
      break;
    case TALOS_RT_DB_JUMP:
      if (!defineMap(state, instruction.source0, instruction.source1) ||
          !merge(instruction.immediate, state))
        return false;
      fallthrough = false;
      break;
    case TALOS_RT_DB_BRANCH: {
      State taken = state;
      if (!defineMap(taken, instruction.source0, instruction.source1) ||
          !merge(instruction.immediate, taken))
        return false;
      break;
    }
    case TALOS_RT_DB_CALL:
      if (!defineMap(state, instruction.auxiliary, instruction.immediate))
        return false;
      break;
    case TALOS_RT_DB_VIRTUAL_CALL:
    case TALOS_RT_DB_INTERFACE_CALL:
    case TALOS_RT_DB_NATIVE_VIRTUAL_CALL:
    case TALOS_RT_DB_NATIVE_INTERFACE_CALL:
    case TALOS_RT_DB_NATIVE_DIRECT_CALL:
      if (!defineMap(state, methodCallOutputMap(image, instruction),
                     instruction.flags))
        return false;
      break;
    case TALOS_RT_DB_CLEAR_FRAME_ROOT:
    case TALOS_RT_DB_FRAME_ROOT:
      break;
    case TALOS_RT_DB_INTRINSIC: {
      IntrinsicSite site =
          siteAt(image, static_cast<uint32_t>(instruction.immediate));
      for (uint32_t index = 0; index != site.outputCount; ++index) {
        uint32_t destination =
            operandAt(image, site.firstOperand + site.inputCount + index).first;
        if (!setInitialized(state, destination))
          return false;
      }
      break;
    }
    case TALOS_RT_DB_RETURN:
    case TALOS_RT_DB_CONTINUE:
    case TALOS_RT_DB_SUSPEND:
    case TALOS_RT_DB_TERMINATE:
    case TALOS_RT_DB_TASK_CALL:
    case TALOS_RT_DB_VIRTUAL_TASK_CALL:
    case TALOS_RT_DB_INTERFACE_TASK_CALL:
      fallthrough = false;
      break;
    case TALOS_RT_DB_PROCESS_CONTROL:
      // The immediate is the continuation's ordinal among the function's
      // records (the code checks bound it), as the interpreter resolves it.
      if (!process && (instruction.immediate >= function.continuationCount ||
                       !merge(continuationAt(image, function.firstContinuation +
                                                        instruction.immediate)
                                  .instruction,
                              state)))
        return false;
      fallthrough = false;
      break;
    default:
      break;
    }
    if (fallthrough) {
      if (pc + 1 >= begin + count || !merge(pc + 1, state))
        return false;
    }
  }
  auto initialized = [&](const State &state, uint32_t reg) {
    return reg < registerCount &&
           ((state[reg / 64] >> (reg % 64)) & uint64_t{1}) != 0;
  };
  uint32_t uninitializedRegister = kInvalidRegister;
  auto requireInitialized = [&](const State &state, uint32_t reg) {
    if (initialized(state, reg))
      return true;
    uninitializedRegister = reg;
    return false;
  };
  auto mapSourcesInitialized = [&](const State &state, uint64_t first,
                                   uint64_t mapCount) {
    for (uint64_t index = 0; index != mapCount; ++index)
      if (!requireInitialized(state, operandAt(image, first + index).second))
        return false;
    return true;
  };
  for (uint64_t offset = 0; offset != count; ++offset) {
    if (!incoming[static_cast<size_t>(offset)])
      continue;
    const State &state = *incoming[static_cast<size_t>(offset)];
    Instruction instruction = instructionAt(image, begin + offset);
    uninitializedRegister = kInvalidRegister;
    auto sources = [&](std::initializer_list<uint32_t> registers) {
      for (uint32_t reg : registers)
        if (!requireInitialized(state, reg))
          return false;
      return true;
    };
    bool valid = true;
    switch (instruction.opcode) {
    case TALOS_RT_DB_MOVE:
    case TALOS_RT_DB_BITCAST:
    case TALOS_RT_DB_NOT:
    case TALOS_RT_DB_POPCOUNT:
    case TALOS_RT_DB_REDUCE:
    case TALOS_RT_DB_STORE_FRAME:
    case TALOS_RT_DB_MAKE_LOCAL_HANDLE:
    case TALOS_RT_DB_HANDLE_ID:
    case TALOS_RT_DB_LOAD_STATE:
    case TALOS_RT_DB_FAIL:
    case TALOS_RT_DB_RELEASE_STATE:
    case TALOS_RT_DB_FNEG:
    case TALOS_RT_DB_FEXT:
    case TALOS_RT_DB_FTRUNC:
      valid = sources({instruction.source0});
      break;
    case TALOS_RT_DB_AND:
    case TALOS_RT_DB_OR:
    case TALOS_RT_DB_XOR:
    case TALOS_RT_DB_ADD:
    case TALOS_RT_DB_SUB:
    case TALOS_RT_DB_MUL:
    case TALOS_RT_DB_POWER:
    case TALOS_RT_DB_REPLICATE:
    case TALOS_RT_DB_UDIV:
    case TALOS_RT_DB_SDIV:
    case TALOS_RT_DB_UREM:
    case TALOS_RT_DB_SREM:
    case TALOS_RT_DB_SHL:
    case TALOS_RT_DB_LSHR:
    case TALOS_RT_DB_ASHR:
    case TALOS_RT_DB_COMPARE:
    case TALOS_RT_DB_CONCAT:
    case TALOS_RT_DB_STORE_STATE:
    case TALOS_RT_DB_OVERRIDE_STATE:
    case TALOS_RT_DB_FADD:
    case TALOS_RT_DB_FSUB:
    case TALOS_RT_DB_FMUL:
    case TALOS_RT_DB_FDIV:
    case TALOS_RT_DB_FCOMPARE:
    case TALOS_RT_DB_FPOW:
      valid = sources({instruction.source0, instruction.source1});
      break;
    case TALOS_RT_DB_INSERT:
      valid = sources({instruction.source0, instruction.source1}) &&
              ((instruction.flags & TALOS_RT_DB_INSERT_DYNAMIC) == 0 ||
               sources({instruction.source2}));
      break;
    case TALOS_RT_DB_SELECT:
      valid = sources(
          {instruction.source0, instruction.source1, instruction.source2});
      break;
    case TALOS_RT_DB_EXTRACT:
    case TALOS_RT_DB_HANDLE_OFFSET:
      valid = sources({instruction.source0}) &&
              (instruction.source1 == kInvalidRegister ||
               sources({instruction.source1}));
      break;
    case TALOS_RT_DB_JUMP:
      valid = mapSourcesInitialized(state, instruction.source0,
                                    instruction.source1);
      break;
    case TALOS_RT_DB_BRANCH:
      valid = requireInitialized(state, instruction.destination) &&
              mapSourcesInitialized(state, instruction.source0,
                                    instruction.source1);
      break;
    case TALOS_RT_DB_CALL:
    case TALOS_RT_DB_TASK_CALL:
      valid = mapSourcesInitialized(state, instruction.source1,
                                    instruction.source2);
      break;
    case TALOS_RT_DB_VIRTUAL_CALL:
    case TALOS_RT_DB_VIRTUAL_TASK_CALL:
    case TALOS_RT_DB_INTERFACE_CALL:
    case TALOS_RT_DB_INTERFACE_TASK_CALL:
    case TALOS_RT_DB_NATIVE_VIRTUAL_CALL:
    case TALOS_RT_DB_NATIVE_INTERFACE_CALL:
    case TALOS_RT_DB_NATIVE_DIRECT_CALL:
      valid = (isStaticMethodCall(instruction) ||
               requireInitialized(state, instruction.source0)) &&
              mapSourcesInitialized(state, instruction.source1,
                                    instruction.source2);
      break;
    case TALOS_RT_DB_RETURN:
      valid = mapSourcesInitialized(state, instruction.source0,
                                    instruction.source1);
      break;
    case TALOS_RT_DB_SUSPEND:
      valid = instruction.source0 == kInvalidRegister ||
              requireInitialized(state, instruction.source0);
      break;
    case TALOS_RT_DB_PROCESS_CONTROL:
      valid = requireInitialized(state, instruction.source0);
      break;
    case TALOS_RT_DB_INTRINSIC: {
      IntrinsicSite site =
          siteAt(image, static_cast<uint32_t>(instruction.immediate));
      for (uint32_t index = 0; index != site.inputCount; ++index)
        valid &= requireInitialized(
            state, operandAt(image, site.firstOperand + index).second);
      break;
    }
    default:
      break;
    }
    if (!valid) {
      if (validationDiagnosticsEnabled())
        std::fprintf(stderr,
                     "talos-bytecode-validation: rejected image: "
                     "instruction reads uninitialized register %u; "
                     "function=%u pc=%llu opcode=%u "
                     "(DesignBytecodeImage.cpp:%u)\n",
                     uninitializedRegister, functionIndex,
                     static_cast<unsigned long long>(begin + offset),
                     instruction.opcode, __LINE__);
      return false;
    }
  }
  return true;
}

// Validates one function's instructions and its forward initialization
// against the function's layouts, continuations and the image tables, which
// validateImage has already checked. Contexts run it on a function's first
// execution (fastPlan in DesignBytecode.cpp); standalone entries
// validate every function up front.
bool validateFunctionCode(const Image &image, uint32_t functionIndex) {
  auto reject = [](unsigned line, const char *reason,
                   uint64_t functionIndex = UINT64_MAX,
                   uint64_t pc = UINT64_MAX, uint32_t opcode = UINT32_MAX) {
    return rejectImage(line, reason, functionIndex, pc, opcode);
  };
  if (functionIndex >= image.functionCount)
    return reject(__LINE__, "bytecode function index is out of range");
  Function function = functionAt(image, functionIndex);
  uint64_t codeEnd = function.firstInstruction + function.instructionCount;
  // Instructions name a continuation by its ordinal among the function's
  // records (two-tier B4: position-independent bodies); the record holds the
  // cross-tier id.
  auto hasContinuation = [&](uint64_t ordinal) {
    return ordinal < function.continuationCount;
  };
  for (uint64_t pc = function.firstInstruction; pc != codeEnd; ++pc) {
    Instruction instruction = instructionAt(image, pc);
    auto reg = [&](uint32_t index) { return validRegister(function, index); };
    auto numeric = [&](uint32_t index) {
      if (!reg(index))
        return false;
      uint8_t kind = layoutAt(image, function, index).kind;
      return kind == TALOS_RT_DBREG_BITS || kind == TALOS_RT_DBREG_LOGIC;
    };
    auto floating = [&](uint32_t index) {
      if (!reg(index))
        return false;
      uint8_t kind = layoutAt(image, function, index).kind;
      return kind == TALOS_RT_DBREG_REAL32 || kind == TALOS_RT_DBREG_REAL64;
    };
    auto binary = [&] {
      return reg(instruction.destination) && reg(instruction.source0) &&
             reg(instruction.source1) &&
             compatible(layoutAt(image, function, instruction.destination),
                        layoutAt(image, function, instruction.source0)) &&
             compatible(layoutAt(image, function, instruction.destination),
                        layoutAt(image, function, instruction.source1));
    };
    switch (instruction.opcode) {
    case TALOS_RT_DB_NOP:
      if (instruction.flags || instruction.destination || instruction.source0 ||
          instruction.source1 || instruction.source2 || instruction.auxiliary ||
          instruction.immediate)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_CONSTANT: {
      if (!reg(instruction.destination) || instruction.flags ||
          instruction.source0 || instruction.source1 || instruction.source2 ||
          instruction.auxiliary)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Layout layout = layoutAt(image, function, instruction.destination);
      if (instruction.immediate > image.constantSize ||
          layout.size > image.constantSize - instruction.immediate)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_MOVE:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          !compatible(layoutAt(image, function, instruction.destination),
                      layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_BITCAST:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          !bitcastCompatible(layoutAt(image, function, instruction.destination),
                             layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_NOT:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          !compatible(layoutAt(image, function, instruction.destination),
                      layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_POPCOUNT: {
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Layout destination = layoutAt(image, function, instruction.destination);
      Layout source = layoutAt(image, function, instruction.source0);
      if (destination.kind != TALOS_RT_DBREG_BITS ||
          source.kind != TALOS_RT_DBREG_BITS ||
          destination.width != source.width)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_POWER:
      if (instruction.flags || instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !numeric(instruction.destination) ||
          !numeric(instruction.source0) || !numeric(instruction.source1) ||
          !compatible(layoutAt(image, function, instruction.destination),
                      layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_REPLICATE: {
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate == 0 ||
          !numeric(instruction.destination) || !numeric(instruction.source0))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Layout destination = layoutAt(image, function, instruction.destination);
      Layout source = layoutAt(image, function, instruction.source0);
      if (destination.kind != source.kind || source.width == 0 ||
          instruction.immediate > UINT32_MAX / source.width ||
          uint64_t{source.width} * instruction.immediate != destination.width)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_REDUCE:
      if (instruction.source1 || instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !numeric(instruction.destination) ||
          !numeric(instruction.source0) ||
          instruction.flags > TALOS_RT_DB_REDUCE_LOGICAL_VALUE ||
          layoutAt(image, function, instruction.destination).width != 1)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_EXTRACT:
      if (instruction.source2 || instruction.auxiliary ||
          (instruction.source1 != kInvalidRegister &&
           !numeric(instruction.source1)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      if (instruction.flags == TALOS_RT_DB_AGGREGATE_MANAGED) {
        if (!reg(instruction.destination) || !reg(instruction.source0))
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
        Layout destination = layoutAt(image, function, instruction.destination);
        Layout source = layoutAt(image, function, instruction.source0);
        bool extractHandle = (destination.kind == TALOS_RT_DBREG_MANAGED ||
                              destination.kind == TALOS_RT_DBREG_STRING) &&
                             destination.width == 64 &&
                             numeric(instruction.source0);
        bool insertHandle =
            numeric(instruction.destination) &&
            (source.kind == TALOS_RT_DBREG_MANAGED ||
             source.kind == TALOS_RT_DBREG_STRING) &&
            source.width == 64 && instruction.source1 == kInvalidRegister &&
            instruction.immediate == 0 && destination.width >= 64;
        if (extractHandle && instruction.source1 == kInvalidRegister &&
            ((instruction.immediate & 63) != 0 ||
             instruction.immediate > source.width ||
             uint64_t{64} > source.width - instruction.immediate))
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
        if (!extractHandle && !insertHandle)
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      } else if (instruction.flags > TALOS_RT_DB_EXTRACT_SIGN_EXTEND ||
                 !numeric(instruction.destination) ||
                 !numeric(instruction.source0)) {
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      }
      break;
    case TALOS_RT_DB_AND:
    case TALOS_RT_DB_OR:
    case TALOS_RT_DB_XOR:
    case TALOS_RT_DB_ADD:
    case TALOS_RT_DB_SUB:
    case TALOS_RT_DB_MUL:
    case TALOS_RT_DB_UDIV:
    case TALOS_RT_DB_SDIV:
    case TALOS_RT_DB_UREM:
    case TALOS_RT_DB_SREM:
      if (instruction.flags || instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !binary())
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_FADD:
    case TALOS_RT_DB_FSUB:
    case TALOS_RT_DB_FMUL:
    case TALOS_RT_DB_FDIV:
    case TALOS_RT_DB_FPOW:
      if (instruction.flags || instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !binary() ||
          !floating(instruction.destination))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_FNEG:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          !floating(instruction.destination) ||
          !compatible(layoutAt(image, function, instruction.destination),
                      layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_FCOMPARE: {
      if (instruction.flags > TALOS_RT_DB_FCMP_GE || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !numeric(instruction.destination) ||
          layoutAt(image, function, instruction.destination).kind !=
              TALOS_RT_DBREG_BITS ||
          layoutAt(image, function, instruction.destination).width != 1 ||
          !floating(instruction.source0) || !floating(instruction.source1) ||
          !compatible(layoutAt(image, function, instruction.source0),
                      layoutAt(image, function, instruction.source1)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_FEXT:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          layoutAt(image, function, instruction.destination).kind !=
              TALOS_RT_DBREG_REAL64 ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_REAL32)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_FTRUNC:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          layoutAt(image, function, instruction.destination).kind !=
              TALOS_RT_DBREG_REAL32 ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_REAL64)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_SHL:
    case TALOS_RT_DB_LSHR:
    case TALOS_RT_DB_ASHR:
      if (instruction.flags || instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.destination) ||
          !reg(instruction.source0) || !numeric(instruction.source1) ||
          !compatible(layoutAt(image, function, instruction.destination),
                      layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_COMPARE: {
      bool deterministic = instruction.flags == TALOS_RT_DB_CMP_CASE_EQ ||
                           instruction.flags == TALOS_RT_DB_CMP_CASE_NE ||
                           instruction.flags == TALOS_RT_DB_CMP_CASEZ_EQ ||
                           instruction.flags == TALOS_RT_DB_CMP_CASEXZ_EQ;
      if (instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.destination) ||
          !reg(instruction.source0) || !reg(instruction.source1) ||
          instruction.flags > TALOS_RT_DB_CMP_CASEXZ_EQ ||
          !compatible(layoutAt(image, function, instruction.source0),
                      layoutAt(image, function, instruction.source1)) ||
          !numeric(instruction.destination) ||
          layoutAt(image, function, instruction.destination).width != 1 ||
          (deterministic &&
           layoutAt(image, function, instruction.destination).kind !=
               TALOS_RT_DBREG_BITS))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_SELECT:
      // A bitwise condition matches the destination's width; the others
      // are one bit.
      if (instruction.flags > TALOS_RT_DB_SELECT_BITWISE ||
          instruction.auxiliary || instruction.immediate || !binary() ||
          !numeric(instruction.source2) ||
          layoutAt(image, function, instruction.source2).width !=
              (instruction.flags == TALOS_RT_DB_SELECT_BITWISE
                   ? layoutAt(image, function, instruction.destination).width
                   : 1) ||
          (instruction.flags == TALOS_RT_DB_SELECT_FOUR_STATE &&
           (layoutAt(image, function, instruction.destination).kind !=
                TALOS_RT_DBREG_LOGIC ||
            layoutAt(image, function, instruction.source0).kind !=
                TALOS_RT_DBREG_LOGIC ||
            layoutAt(image, function, instruction.source1).kind !=
                TALOS_RT_DBREG_LOGIC ||
            layoutAt(image, function, instruction.source2).kind !=
                TALOS_RT_DBREG_LOGIC)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_CONCAT: {
      if (instruction.flags || instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.destination) ||
          !reg(instruction.source0) || !reg(instruction.source1))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Layout destination = layoutAt(image, function, instruction.destination);
      Layout left = layoutAt(image, function, instruction.source0);
      Layout right = layoutAt(image, function, instruction.source1);
      if (destination.kind != left.kind || left.kind != right.kind ||
          uint64_t{left.width} + right.width != destination.width)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_INSERT: {
      if (instruction.auxiliary || !numeric(instruction.destination) ||
          !numeric(instruction.source0) ||
          !compatible(layoutAt(image, function, instruction.destination),
                      layoutAt(image, function, instruction.source0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Layout destination = layoutAt(image, function, instruction.destination);
      Layout inserted = layoutAt(image, function, instruction.source1);
      bool dynamic = (instruction.flags & TALOS_RT_DB_INSERT_DYNAMIC) != 0;
      bool managedWord =
          (instruction.flags & TALOS_RT_DB_AGGREGATE_MANAGED) != 0;
      if (instruction.flags &
          ~uint16_t(TALOS_RT_DB_INSERT_DYNAMIC | TALOS_RT_DB_AGGREGATE_MANAGED))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      if (dynamic &&
          (instruction.immediate != 0 || !numeric(instruction.source2)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      if (managedWord) {
        // A managed word carries a handle, not a numeric value. Its lane is
        // 64 bits wide and 64-bit aligned; a dynamic offset is a multiple of
        // the element span, which the compiler keeps aligned, so only the
        // static form can check the position here.
        if ((inserted.kind != TALOS_RT_DBREG_MANAGED &&
             inserted.kind != TALOS_RT_DBREG_STRING) ||
            inserted.width != 64 ||
            (!dynamic && (instruction.immediate & 63) != 0))
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      } else if (!numeric(instruction.source1)) {
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      }
      if (!dynamic &&
          (instruction.immediate > destination.width ||
           inserted.width > destination.width - instruction.immediate))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_LOAD_FRAME:
    case TALOS_RT_DB_STORE_FRAME: {
      if (instruction.source2 || (instruction.opcode == TALOS_RT_DB_LOAD_FRAME
                                      ? instruction.source0 != 0
                                      : instruction.destination != 0))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      uint32_t valueRegister = instruction.opcode == TALOS_RT_DB_LOAD_FRAME
                                   ? instruction.destination
                                   : instruction.source0;
      if (!reg(valueRegister))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Layout value = layoutAt(image, function, valueRegister);
      if (value.kind == TALOS_RT_DBREG_HANDLE) {
        if (instruction.flags < TALOS_RT_DESCRIPTOR_STORAGE ||
            instruction.flags > TALOS_RT_DESCRIPTOR_PROCESS ||
            (instruction.flags <= TALOS_RT_DESCRIPTOR_DRIVER
                 ? instruction.auxiliary == 0
                 : instruction.auxiliary != 0))
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      } else if (instruction.flags != 0 || instruction.auxiliary > value.size) {
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      } else if (value.kind == TALOS_RT_DBREG_LOGIC &&
                 (instruction.auxiliary % 2 != 0 ||
                  (instruction.source1 != 0 &&
                   instruction.source1 < instruction.auxiliary / 2))) {
        // A four-state transfer always names both canonical frame planes,
        // so its size is the value plane size doubled. An odd size cannot
        // describe one, and would truncate the unknown plane.
        return reject(__LINE__, "four-state frame transfer is not a plane pair",
                      functionIndex, pc, instruction.opcode);
      } else if (value.kind != TALOS_RT_DBREG_LOGIC &&
                 instruction.source1 != 0) {
        return reject(__LINE__, "secondary frame offset on two-state value",
                      functionIndex, pc, instruction.opcode);
      }
      break;
    }
    case TALOS_RT_DB_CLEAR_FRAME_ROOT:
    case TALOS_RT_DB_FRAME_ROOT: {
      uint64_t canonicalSize =
          (function.flags & TALOS_RT_DESIGN_FUNCTION_FRAME_SIZE_MASK) >> 1;
      bool candidate = instruction.flags == 1;
      if (instruction.flags > 1 ||
          (candidate ? instruction.destination == 0 ||
                           (instruction.destination &
                            ~TALOS_RT_MANAGED_ROOT_KIND_ALL) != 0
                     : instruction.destination != 0) ||
          instruction.source0 || instruction.source1 || instruction.source2 ||
          instruction.auxiliary ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
          instruction.immediate > canonicalSize ||
          sizeof(talos_rt_managed_word_v1) >
              canonicalSize - instruction.immediate)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_MAKE_HANDLE:
      if (instruction.flags || !reg(instruction.destination) ||
          layoutAt(image, function, instruction.destination).kind !=
              TALOS_RT_DBREG_HANDLE ||
          instruction.source0 < TALOS_RT_DESCRIPTOR_STORAGE ||
          instruction.source0 > TALOS_RT_DESCRIPTOR_EVENT ||
          instruction.source2 || instruction.auxiliary)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_MAKE_LOCAL_HANDLE:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !reg(instruction.destination) ||
          layoutAt(image, function, instruction.destination).kind !=
              TALOS_RT_DBREG_HANDLE ||
          (!numeric(instruction.source0) && !floating(instruction.source0)) ||
          instruction.source0 > UINT16_MAX)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_HANDLE_OFFSET:
      if (instruction.flags || instruction.source2 ||
          !reg(instruction.destination) || !reg(instruction.source0) ||
          layoutAt(image, function, instruction.destination).kind !=
              TALOS_RT_DBREG_HANDLE ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_HANDLE ||
          instruction.auxiliary == 0 ||
          (instruction.source1 != kInvalidRegister &&
           !numeric(instruction.source1)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_HANDLE_ID:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          !numeric(instruction.destination) ||
          layoutAt(image, function, instruction.destination).width != 64 ||
          !reg(instruction.source0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_HANDLE)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_LOAD_STATE:
      if (instruction.flags || instruction.source1 || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          (!numeric(instruction.destination) &&
           !floating(instruction.destination) &&
           (!reg(instruction.destination) ||
            (layoutAt(image, function, instruction.destination).kind !=
                 TALOS_RT_DBREG_MANAGED &&
             layoutAt(image, function, instruction.destination).kind !=
                 TALOS_RT_DBREG_STRING &&
             layoutAt(image, function, instruction.destination).kind !=
                 TALOS_RT_DBREG_HANDLE))) ||
          !reg(instruction.source0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_HANDLE)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_STORE_STATE:
      if ((instruction.flags &
           ~(TALOS_RT_DB_STORE_STATE_CHANGED |
             TALOS_RT_DB_STORE_STATE_CONTINUOUS |
             TALOS_RT_DB_STORE_STATE_DEFER_NET_RESOLUTION)) != 0 ||
          ((instruction.flags & TALOS_RT_DB_STORE_STATE_CHANGED) != 0
               ? (!reg(instruction.destination) ||
                  layoutAt(image, function, instruction.destination).width != 1)
               : instruction.destination != 0) ||
          ((instruction.flags & TALOS_RT_DB_STORE_STATE_CONTINUOUS) != 0 &&
           !numeric(instruction.source1) && !floating(instruction.source1) &&
           (!reg(instruction.source1) ||
            layoutAt(image, function, instruction.source1).kind !=
                TALOS_RT_DBREG_STRING)) ||
          instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.source0) ||
          (!numeric(instruction.source1) && !floating(instruction.source1) &&
           (!reg(instruction.source1) ||
            (layoutAt(image, function, instruction.source1).kind !=
                 TALOS_RT_DBREG_MANAGED &&
             layoutAt(image, function, instruction.source1).kind !=
                 TALOS_RT_DBREG_STRING &&
             layoutAt(image, function, instruction.source1).kind !=
                 TALOS_RT_DBREG_HANDLE))) ||
          (reg(instruction.source1) &&
           layoutAt(image, function, instruction.source1).kind ==
               TALOS_RT_DBREG_HANDLE &&
           instruction.flags != 0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_HANDLE)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_OVERRIDE_STATE:
      if ((instruction.flags & ~TALOS_RT_DB_OVERRIDE_FLAG_MASK) != 0 ||
          ((instruction.flags & TALOS_RT_DB_OVERRIDE_CLAIM) != 0 &&
           (instruction.flags & TALOS_RT_DB_OVERRIDE_DYNAMIC) == 0) ||
          instruction.destination || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.source0) ||
          (!numeric(instruction.source1) && !floating(instruction.source1) &&
           layoutAt(image, function, instruction.source1).kind !=
               TALOS_RT_DBREG_MANAGED &&
           layoutAt(image, function, instruction.source1).kind !=
               TALOS_RT_DBREG_STRING) ||
          ((instruction.flags & TALOS_RT_DB_OVERRIDE_DYNAMIC) != 0
               ? (!reg(instruction.source2) ||
                  layoutAt(image, function, instruction.source2).kind !=
                      TALOS_RT_DBREG_BITS ||
                  layoutAt(image, function, instruction.source2).width != 64)
               : instruction.source2 != 0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_HANDLE)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_RELEASE_STATE:
      if (instruction.flags > TALOS_RT_DB_OVERRIDE_ASSIGN ||
          instruction.destination || instruction.source1 ||
          instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.source0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_HANDLE)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_JUMP:
    case TALOS_RT_DB_BRANCH:
      if (instruction.flags || instruction.source2 || instruction.auxiliary ||
          (instruction.opcode == TALOS_RT_DB_JUMP ? instruction.destination != 0
                                                  : false) ||
          instruction.immediate < function.firstInstruction ||
          instruction.immediate >= codeEnd ||
          (instruction.opcode == TALOS_RT_DB_BRANCH &&
           (!numeric(instruction.destination) ||
            layoutAt(image, function, instruction.destination).width != 1)) ||
          !validMap(image, function, function, instruction.source0,
                    instruction.source1))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_CALL: {
      if (instruction.flags || instruction.destination ||
          instruction.source0 >= image.functionCount)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Function callee = functionAt(image, instruction.source0);
      if ((callee.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0 ||
          instruction.source2 != callee.argumentCount ||
          instruction.immediate != callee.resultCount ||
          !validMap(image, function, callee, instruction.source1,
                    instruction.source2) ||
          !validMap(image, callee, function, instruction.auxiliary,
                    instruction.immediate))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      for (uint32_t index = 0; index != callee.argumentCount; ++index)
        if (operandAt(image, instruction.source1 + index).first != index)
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      for (uint32_t index = 0; index != callee.resultCount; ++index)
        if (operandAt(image, instruction.auxiliary + index).second !=
            callee.argumentCount + index)
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_TASK_CALL: {
      if (instruction.flags || instruction.destination ||
          instruction.source0 >= image.functionCount || instruction.auxiliary ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
          !hasContinuation(instruction.immediate))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      Function callee = functionAt(image, instruction.source0);
      if ((callee.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
          callee.resultCount != 0 ||
          instruction.source2 != callee.argumentCount ||
          !validMap(image, function, callee, instruction.source1,
                    instruction.source2))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      for (uint32_t index = 0; index != callee.argumentCount; ++index)
        if (operandAt(image, instruction.source1 + index).first != index)
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_VIRTUAL_CALL:
    case TALOS_RT_DB_INTERFACE_CALL:
    case TALOS_RT_DB_NATIVE_VIRTUAL_CALL:
    case TALOS_RT_DB_NATIVE_INTERFACE_CALL:
    case TALOS_RT_DB_NATIVE_DIRECT_CALL: {
      if (isNativeMethodCall(instruction) &&
          !validNativeMethodSite(image, function, instruction))
        return reject(__LINE__, "invalid native method marshal plan",
                      functionIndex, pc, instruction.opcode);
      uint32_t outputs = methodCallOutputMap(image, instruction);
      bool interfaceDispatch =
          instruction.opcode == TALOS_RT_DB_INTERFACE_CALL ||
          instruction.opcode == TALOS_RT_DB_NATIVE_INTERFACE_CALL;
      bool directDispatch =
          instruction.opcode == TALOS_RT_DB_NATIVE_DIRECT_CALL;
      bool staticMethod = isStaticMethodCall(instruction);
      if (instruction.flags > function.layoutCount ||
          instruction.immediate == 0 ||
          instruction.source2 < (staticMethod ? 1u : 2u) ||
          (!staticMethod &&
           (!reg(instruction.source0) ||
            layoutAt(image, function, instruction.source0).kind !=
                TALOS_RT_DBREG_MANAGED)) ||
          instruction.source1 > image.operandCount ||
          instruction.source2 > image.operandCount - instruction.source1 ||
          outputs > image.operandCount ||
          instruction.flags > image.operandCount - outputs ||
          (interfaceDispatch &&
           (instruction.destination >= image.operandCount ||
            operandAt(image, instruction.destination).first == 0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      for (uint32_t index = 0; index != instruction.source2; ++index) {
        auto [destination, source] =
            operandAt(image, instruction.source1 + index);
        if (destination != index || !reg(source) ||
            (!staticMethod && index == 1 && source != instruction.source0))
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      }
      for (uint32_t index = 0; index != instruction.flags; ++index) {
        auto [destination, source] = operandAt(image, outputs + index);
        if (!reg(destination) || source != instruction.source2 + index)
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      }
      if (directDispatch) {
        if (instruction.destination >= image.functionCount)
          return reject(__LINE__, "unknown exact native method", functionIndex,
                        pc, instruction.opcode);
        Function callee = functionAt(image, instruction.destination);
        if ((callee.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0 ||
            callee.argumentCount != instruction.source2 ||
            callee.resultCount != instruction.flags ||
            !validMap(image, function, callee, instruction.source1,
                      instruction.source2) ||
            !validMap(image, callee, function, outputs, instruction.flags))
          return reject(__LINE__, "incompatible exact native method",
                        functionIndex, pc, instruction.opcode);
      }
      break;
    }
    case TALOS_RT_DB_VIRTUAL_TASK_CALL:
    case TALOS_RT_DB_INTERFACE_TASK_CALL: {
      bool interfaceDispatch =
          instruction.opcode == TALOS_RT_DB_INTERFACE_TASK_CALL;
      if (instruction.flags || instruction.immediate == 0 ||
          instruction.source2 < 2 ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
          !hasContinuation(instruction.auxiliary) ||
          !reg(instruction.source0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_MANAGED ||
          instruction.source1 > image.operandCount ||
          instruction.source2 > image.operandCount - instruction.source1 ||
          (interfaceDispatch &&
           (instruction.destination >= image.operandCount ||
            operandAt(image, instruction.destination).first == 0)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      for (uint32_t index = 0; index != instruction.source2; ++index) {
        auto [destination, source] =
            operandAt(image, instruction.source1 + index);
        if (destination != index || !reg(source) ||
            (index == 1 && source != instruction.source0))
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      }
      break;
    }
    case TALOS_RT_DB_RETURN:
      if (instruction.flags || instruction.destination || instruction.source2 ||
          instruction.auxiliary || instruction.immediate ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0 ||
          instruction.source1 != function.resultCount ||
          !validMap(image, function, function, instruction.source0,
                    instruction.source1))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      for (uint32_t index = 0; index != function.resultCount; ++index)
        if (operandAt(image, instruction.source0 + index).first !=
            function.argumentCount + index)
          return reject(__LINE__, "invalid instruction encoding or operands",
                        functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_CONTINUE:
      if (instruction.flags || instruction.destination || instruction.source0 ||
          instruction.source1 || instruction.source2 || instruction.auxiliary ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
          !hasContinuation(instruction.immediate))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_PROCESS_CONTROL:
      if (instruction.flags > TALOS_RT_PROCESS_CONTROL_RESUME ||
          instruction.destination || instruction.source1 ||
          instruction.source2 || instruction.auxiliary ||
          ((function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 &&
           instruction.flags == TALOS_RT_PROCESS_CONTROL_SUSPEND) ||
          !hasContinuation(instruction.immediate) ||
          !reg(instruction.source0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_BITS ||
          layoutAt(image, function, instruction.source0).width != 64)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_SUSPEND: {
      if (instruction.flags < TALOS_RT_SUSPEND_DELAY ||
          instruction.flags > TALOS_RT_SUSPEND_EVENT_ORDER ||
          instruction.destination || instruction.source1 ||
          instruction.source2 ||
          (instruction.auxiliary & ~kResumeActionFlags) != 0 ||
          !talos_rt_valid_resume_action_flags(instruction.auxiliary) ||
          !numeric(instruction.source0) ||
          layoutAt(image, function, instruction.source0).width != 64 ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
          !hasContinuation(instruction.immediate))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    }
    case TALOS_RT_DB_TERMINATE:
      if (instruction.flags || instruction.destination || instruction.source0 ||
          instruction.source1 || instruction.source2 || instruction.auxiliary ||
          (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_FAIL:
      if (instruction.flags || instruction.destination || instruction.source1 ||
          instruction.source2 || instruction.auxiliary ||
          instruction.immediate || !reg(instruction.source0) ||
          layoutAt(image, function, instruction.source0).kind !=
              TALOS_RT_DBREG_STATUS)
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    case TALOS_RT_DB_INTRINSIC:
      if (instruction.flags || instruction.destination || instruction.source0 ||
          instruction.source1 || instruction.source2 || instruction.auxiliary ||
          instruction.immediate > UINT32_MAX ||
          !validIntrinsic(image, function,
                          static_cast<uint32_t>(instruction.immediate)))
        return reject(__LINE__, "invalid instruction encoding or operands",
                      functionIndex, pc, instruction.opcode);
      break;
    default:
      if (image.compactCode && instruction.opcode == UINT16_MAX)
        return reject(__LINE__, "malformed compact instruction encoding",
                      functionIndex, pc);
      return reject(__LINE__, "unknown bytecode opcode", functionIndex, pc,
                    instruction.opcode);
    }
  }
  // Bound the forward initialization analysis. Large generated eval
  // coordinators can have irreducible CFGs beyond this model; instruction
  // encodings and operands are still validated above.
  if (function.instructionCount <= 2000 &&
      !validateInitialization(image, function, functionIndex))
    return false;
  return true;
}

bool validateImage(const Image &image, bool validateCode) {
  auto reject = [](unsigned line, const char *reason,
                   uint64_t functionIndex = UINT64_MAX,
                   uint64_t pc = UINT64_MAX, uint32_t opcode = UINT32_MAX) {
    return rejectImage(line, reason, functionIndex, pc, opcode);
  };

  // Every layout record names a valid shape, so layoutAt is safe below.
  for (uint64_t shapeIndex = 0; shapeIndex != image.shapeCount; ++shapeIndex) {
    const uint8_t *shape = image.data + image.shapes + shapeIndex * kShapeSize;
    Layout layout{shape[0], shape[1],          read32(shape + 4),
                  0,        read64(shape + 8), read64(shape + 16)};
    uint64_t expected = layoutSize(layout.kind, layout.width);
    constexpr uint8_t opaqueMask =
        TALOS_RT_DBREG_CHANDLE | TALOS_RT_DBREG_COVERGROUP |
        TALOS_RT_DBREG_PROCESS | TALOS_RT_DBREG_VIRTUAL_INTERFACE;
    uint8_t opaqueFlags = layout.flags & opaqueMask;
    uint8_t allowedFlags =
        layout.kind == TALOS_RT_DBREG_MANAGED && layout.width == 64
            ? TALOS_RT_DBREG_CLASS_HANDLE | TALOS_RT_DBREG_SEMAPHORE |
                  TALOS_RT_DBREG_MAILBOX
        : layout.kind == TALOS_RT_DBREG_BITS
            ? TALOS_RT_DBREG_SIGNED | (layout.width == 64 ? opaqueMask : 0)
        : layout.kind == TALOS_RT_DBREG_HANDLE && layout.width == 256
            ? TALOS_RT_DBREG_EVENT
        : layout.kind == TALOS_RT_DBREG_LOGIC ? TALOS_RT_DBREG_SIGNED
                                              : 0;
    if (layout.width == 0 || expected == 0 || layout.size != expected ||
        (layout.kind == TALOS_RT_DBREG_REAL32 && layout.width != 32) ||
        (layout.kind == TALOS_RT_DBREG_REAL64 && layout.width != 64) ||
        (layout.kind == TALOS_RT_DBREG_STRING && layout.width != 64) ||
        read16(shape + 2) != 0 || (layout.flags & ~allowedFlags) != 0 ||
        (layout.kind == TALOS_RT_DBREG_MANAGED && layout.flags &&
         (layout.flags & (layout.flags - 1))) ||
        (opaqueFlags && (layout.flags & TALOS_RT_DBREG_SIGNED)) ||
        (opaqueFlags && (opaqueFlags & (opaqueFlags - 1))))
      return reject(__LINE__, "invalid register shape");
  }
  for (uint64_t index = 0; index != image.layoutCount; ++index)
    if (read32(image.data + image.layouts + index * kLayoutSize) >=
        image.shapeCount)
      return reject(__LINE__, "register layout names no shape");
  // State capture validation indexes argument layouts. Prove those ranges
  // before following any function-owned offsets from an untrusted image.
  for (uint32_t functionIndex = 0; functionIndex != image.functionCount;
       ++functionIndex) {
    Function function = functionAt(image, functionIndex);
    bool process = (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0;
    if (!validProcessFunctionFlags(function) ||
        (process && function.resultCount != 0) ||
        function.firstLayout > image.layoutCount ||
        function.layoutCount > image.layoutCount - function.firstLayout ||
        function.argumentCount > function.layoutCount ||
        function.resultCount > function.layoutCount - function.argumentCount)
      return reject(__LINE__, "invalid function flags or layout range",
                    functionIndex);
  }
  uint64_t captureIndex = 0;
  for (uint32_t functionIndex = 0; functionIndex != image.functionCount;
       ++functionIndex) {
    Function function = functionAt(image, functionIndex);
    bool process = (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0;
    if (!validProcessFunctionFlags(function) ||
        (process && function.resultCount != 0))
      return reject(__LINE__, "invalid process function flags or result count",
                    functionIndex);
    uint64_t canonicalSize =
        (function.flags & TALOS_RT_DESIGN_FUNCTION_FRAME_SIZE_MASK) >> 1;
    if (!process)
      continue;
    for (uint32_t argument = 0; argument != function.argumentCount;
         ++argument) {
      if (captureIndex >= image.stateDescriptorCount)
        return reject(__LINE__, "missing process argument capture record",
                      functionIndex);
      CaptureRecord capture = captureAt(image, captureIndex++);
      if (capture.function != functionIndex || capture.argument != argument)
        return reject(__LINE__, "misordered process argument capture record",
                      functionIndex);
      Layout layout = layoutAt(image, function, argument);
      if (capture.valueOffset == UINT64_MAX) {
        if (capture.unknownOffset != UINT64_MAX || capture.planeSize != 0 ||
            layout.kind != TALOS_RT_DBREG_HANDLE)
          return reject(__LINE__, "invalid uncaptured handle record",
                        functionIndex);
        continue;
      }
      if (capture.planeSize == 0 || capture.valueOffset > canonicalSize ||
          capture.planeSize > canonicalSize - capture.valueOffset)
        return reject(__LINE__,
                      "process argument capture exceeds the canonical frame",
                      functionIndex);
      if (layout.kind == TALOS_RT_DBREG_LOGIC) {
        // Bytecode registers round each logic plane up to whole 64-bit limbs,
        // while the canonical process frame uses the target ABI allocation
        // size (for example, one byte per plane for logic<1>). Accept that
        // narrower representation as long as it contains every semantic bit.
        uint64_t registerPlane = layout.size / 2;
        uint64_t requiredPlane = (uint64_t{layout.width} + 7) / 8;
        if ((layout.size & 1) != 0 || capture.planeSize < requiredPlane ||
            capture.planeSize > registerPlane ||
            capture.unknownOffset < capture.valueOffset + capture.planeSize ||
            capture.unknownOffset > canonicalSize ||
            capture.planeSize > canonicalSize - capture.unknownOffset)
          return reject(__LINE__, "invalid four-state capture plane layout",
                        functionIndex);
      } else if (layout.kind == TALOS_RT_DBREG_MANAGED_REF) {
        if (capture.planeSize * 2 != layout.size ||
            capture.unknownOffset != capture.valueOffset + capture.planeSize ||
            capture.unknownOffset > canonicalSize ||
            capture.planeSize > canonicalSize - capture.unknownOffset)
          return reject(__LINE__, "invalid managed-reference capture layout",
                        functionIndex);
      } else if (capture.unknownOffset != UINT64_MAX ||
                 ((layout.kind == TALOS_RT_DBREG_HANDLE)
                      ? capture.planeSize != 8
                      : capture.planeSize > layout.size)) {
        return reject(__LINE__, "invalid process argument capture layout",
                      functionIndex);
      }
    }
  }
  uint64_t previousNetEnd = 0;
  std::vector<CaptureRecord> netRecords;
  for (; captureIndex != image.stateDescriptorCount; ++captureIndex) {
    CaptureRecord net = captureAt(image, captureIndex);
    if (net.function != kNetStateDescriptor)
      break;
    bool delayed = (net.argument & (uint32_t{1} << 3)) != 0;
    bool bitwiseDelay = (net.argument & (uint32_t{1} << 4)) != 0;
    uint32_t chargeStrength = (net.argument >> 7) & 3;
    uint64_t delayBytes = 24;
    if (bitwiseDelay && (net.planeSize > UINT64_MAX / 24 ||
                         (delayBytes = net.planeSize * 24) == 0))
      return reject(__LINE__, "invalid bitwise net-delay size");
    // Bits 16 to 24 hold a `default_trireg_strength plus one, on a trireg.
    uint32_t capacity = (net.argument >> 16) & 0x1ff;
    if ((net.argument & ~(uint32_t{511} | (uint32_t{0x1ff} << 16))) != 0 ||
        capacity > 251 || (capacity != 0 && decodeNetResolution(net.argument) != 9) ||
        decodeNetResolution(net.argument) > 9 || net.planeSize == 0 ||
        (decodeNetResolution(net.argument) == 9 && (net.argument & 1) == 0) ||
        (decodeNetResolution(net.argument) != 9 && chargeStrength != 0) ||
        net.valueOffset < previousNetEnd || (bitwiseDelay && !delayed) ||
        delayed != (net.unknownOffset != UINT64_MAX) ||
        (delayed && ((net.unknownOffset & 7) != 0 ||
                     net.unknownOffset > image.constantSize ||
                     delayBytes > image.constantSize - net.unknownOffset)) ||
        net.valueOffset > image.stateBitCount ||
        net.planeSize > image.stateBitCount - net.valueOffset)
      return reject(__LINE__, "invalid or misordered net state record");
    if (delayed) {
      uint64_t tripleCount = bitwiseDelay ? net.planeSize : 1;
      for (uint64_t bit = 0; bit != tripleCount; ++bit) {
        const uint8_t *triple =
            image.data + image.constants + net.unknownOffset + bit * 24;
        bool riseAbsent = read64(triple) == UINT64_MAX;
        bool fallAbsent = read64(triple + 8) == UINT64_MAX;
        bool thirdAbsent = read64(triple + 16) == UINT64_MAX;
        bool absentBit = riseAbsent && fallAbsent && thirdAbsent;
        if ((absentBit && !bitwiseDelay) || riseAbsent != fallAbsent ||
            (riseAbsent && !thirdAbsent))
          return reject(__LINE__, "invalid net-delay sentinel pattern");
      }
    }
    netRecords.push_back(net);
    previousNetEnd = net.valueOffset + net.planeSize;
  }
  // Net records are sorted by offset and disjoint (checked above), so the
  // only net that can hold `bit` is the last one starting at or below it.
  auto containingNet = [&](uint64_t bit, uint64_t width,
                           bool reversed) -> const CaptureRecord * {
    auto after = std::upper_bound(netRecords.begin(), netRecords.end(), bit,
                                  [](uint64_t value, const CaptureRecord &net) {
                                    return value < net.valueOffset;
                                  });
    if (after == netRecords.begin())
      return nullptr;
    const CaptureRecord &net = *std::prev(after);
    if (bit >= net.valueOffset + net.planeSize)
      return nullptr;
    if (reversed)
      return width <= bit - net.valueOffset + 1 ? &net : nullptr;
    return width <= net.valueOffset + net.planeSize - bit ? &net : nullptr;
  };
  uint64_t previousDriverEnd = 0;
  std::vector<CaptureRecord> driverRecords;
  for (; captureIndex != image.stateDescriptorCount; ++captureIndex) {
    CaptureRecord driver = captureAt(image, captureIndex);
    const CaptureRecord *target =
        containingNet(driver.unknownOffset, driver.planeSize, false);
    uint32_t strength0 = (driver.argument >> 3) & 0xf;
    uint32_t strength1 = (driver.argument >> 7) & 0xf;
    bool highStrengthBank = (driver.argument & (uint32_t{1} << 11)) != 0;
    bool mirrorsNet = (driver.argument & TALOS_RT_DB_DRIVER_MIRRORS_NET) != 0;
    if (driver.function != kDriverStateDescriptor ||
        (driver.argument & ~uint32_t{0xffff}) != 0 ||
        (driver.argument & 1) == 0 ||
        decodeDriverResolution(driver.argument) > 9 || strength0 > 8 ||
        strength1 > 8 || driver.planeSize == 0 ||
        driver.valueOffset < previousDriverEnd ||
        driver.valueOffset > image.stateBitCount ||
        driver.planeSize > image.stateBitCount - driver.valueOffset ||
        driver.unknownOffset > image.stateBitCount ||
        driver.planeSize > image.stateBitCount - driver.unknownOffset ||
        !target ||
        decodeDriverResolution(driver.argument) !=
            decodeNetResolution(target->argument))
      return reject(__LINE__, "invalid or misordered driver state record");
    // A mirror is a strong/strong wire contribution (IEEE 1800-2023 6.6.1),
    // never one polarity bank of a conditional gate.
    if (mirrorsNet && (highStrengthBank || (strength0 != 0 && strength0 != 7) ||
                       (strength1 != 0 && strength1 != 7) ||
                       decodeDriverResolution(driver.argument) > 1))
      return reject(__LINE__, "invalid mirror driver state record");
    if (highStrengthBank) {
      if (driverRecords.empty())
        return reject(__LINE__, "orphaned high-polarity driver bank");
      const CaptureRecord &low = driverRecords.back();
      uint32_t lowStrength1 = (low.argument >> 7) & 0xf;
      if ((low.argument & (uint32_t{1} << 11)) != 0 || lowStrength1 != 1 ||
          strength0 != 1 || low.unknownOffset != driver.unknownOffset ||
          low.planeSize != driver.planeSize ||
          decodeDriverResolution(low.argument) !=
              decodeDriverResolution(driver.argument))
        return reject(__LINE__, "invalid complementary driver strength banks");
    }
    // Driver ranges are resolved bitwise and may legally overlap. In
    // particular, a driver for a packed aggregate and a driver for its
    // low-order member have the same target start but different widths. The
    // containing-net check above already proves that every bit has the net's
    // resolution kind; requiring equal widths here would reject that legal
    // topology before execution.
    driverRecords.push_back(driver);
    previousDriverEnd = driver.valueOffset + driver.planeSize;
  }

  std::tuple<uint64_t, uint64_t, uint64_t, uint8_t, uint32_t>
      previousConnection;
  bool firstConnection = true;
  uint64_t expandedConnections = 0;
  uint64_t expandedStaticConnections = 0;
  struct ScalarConnection {
    uint64_t lhs = 0, rhs = 0;
    uint8_t lhsResolution = 0, rhsResolution = 0;
    uint8_t dominanceFlags = 0;
    uint32_t passSwitchId = 0;
    auto tie() const {
      return std::tie(lhs, rhs, lhsResolution, rhsResolution, dominanceFlags,
                      passSwitchId);
    }
  };
  std::vector<ConnectivityRecord> connectionRecords;
  std::vector<ScalarConnection> scalarConnections;
  // Connectivity and net-kind checks run over every net bit, so they use
  // dense net-bit indices (net k holds [netBase[k], netBase[k] + planeSize)):
  // the records are sorted and disjoint, so the index is monotonic in the
  // state bit and a component's root, its smallest index, is its smallest bit.
  std::vector<uint64_t> netBase;
  netBase.reserve(netRecords.size());
  uint64_t totalNetBits = 0;
  for (const CaptureRecord &net : netRecords) {
    netBase.push_back(totalNetBits);
    totalNetBits += net.planeSize;
  }
  // Nets are disjoint within the state, so the sum cannot overflow; a 32-bit
  // host still cannot index more than SIZE_MAX words (the per-bit hash maps
  // these vectors replace failed allocation the same way).
  if (totalNetBits > std::numeric_limits<size_t>::max() / sizeof(uint64_t))
    talos_rt_out_of_memory();
  // Callers pass only bits already proven to lie in a net record.
  auto netBitIndex = [&](uint64_t bit) {
    auto after = std::upper_bound(netRecords.begin(), netRecords.end(), bit,
                                  [](uint64_t value, const CaptureRecord &net) {
                                    return value < net.valueOffset;
                                  });
    size_t net = static_cast<size_t>(std::prev(after) - netRecords.begin());
    return netBase[net] + (bit - netRecords[net].valueOffset);
  };
  std::vector<uint64_t> connectivityParents(totalNetBits);
  std::iota(connectivityParents.begin(), connectivityParents.end(),
            uint64_t{0});
  auto findRoot = [&](uint64_t index) {
    uint64_t root = index;
    while (connectivityParents[root] != root)
      root = connectivityParents[root];
    while (connectivityParents[index] != index) {
      uint64_t next = connectivityParents[index];
      connectivityParents[index] = root;
      index = next;
    }
    return root;
  };
  auto findConnectivity = [&](uint64_t bit) {
    return findRoot(netBitIndex(bit));
  };
  for (uint64_t index = 0; index != image.connectivityCount; ++index) {
    ConnectivityRecord connection = connectivityAt(image, index);
    auto key = std::make_tuple(connection.lhsOffset, connection.rhsOffset,
                               connection.width, connection.flags,
                               connection.tailReserved);
    bool passSwitch = (connection.flags & 8) != 0;
    const CaptureRecord *lhs =
        containingNet(connection.lhsOffset, connection.width, false);
    const CaptureRecord *rhs = containingNet(
        connection.rhsOffset, connection.width, (connection.flags & 1) != 0);
    bool resistivePass = (connection.flags & 16) != 0;
    bool controlledPass = (connection.flags & 32) != 0;
    bool delayedPass = (connection.flags & 64) != 0;
    bool directedPass = (connection.flags & 2) != 0;
    if (connection.width == 0 || (connection.flags & ~uint8_t{127}) != 0 ||
        ((connection.flags & 2) == 0 && (connection.flags & 4) != 0) ||
        (passSwitch && connection.tailReserved == 0) ||
        (delayedPass && (!passSwitch || !controlledPass || !directedPass)) ||
        (!passSwitch && (connection.tailReserved != 0 || resistivePass ||
                         controlledPass || delayedPass)) ||
        connection.reserved != 0 || connection.lhsResolution > 9 ||
        connection.rhsResolution > 9 || !lhs || !rhs ||
        connection.lhsResolution != decodeNetResolution(lhs->argument) ||
        connection.rhsResolution != decodeNetResolution(rhs->argument) ||
        ((lhs->argument ^ rhs->argument) & 1) != 0 ||
        (!firstConnection && key <= previousConnection) ||
        connection.width > UINT64_MAX - expandedConnections)
      return reject(__LINE__, "invalid or noncanonical connectivity record");
    previousConnection = key;
    firstConnection = false;
    connectionRecords.push_back(connection);
    expandedConnections += connection.width;
    if (!passSwitch)
      expandedStaticConnections += connection.width;
    // A corrupt image must not turn validation into an unbounded expansion.
    if ((image.stateBitCount <= UINT64_MAX / 8 &&
         expandedStaticConnections > image.stateBitCount * 8) ||
        expandedConnections > UINT32_MAX)
      return reject(__LINE__, "connectivity expansion exceeds image bounds");
    for (uint64_t bit = 0; bit != connection.width; ++bit) {
      uint64_t lhsBit = connection.lhsOffset + bit;
      uint64_t rhsBit = (connection.flags & 1) ? connection.rhsOffset - bit
                                               : connection.rhsOffset + bit;
      if (lhsBit >= rhsBit)
        return reject(
            __LINE__,
            "connectivity edge endpoints are not canonically ordered");
      scalarConnections.push_back({lhsBit, rhsBit, connection.lhsResolution,
                                   connection.rhsResolution,
                                   static_cast<uint8_t>(connection.flags & 118),
                                   connection.tailReserved});
      if (!passSwitch) {
        uint64_t lhsRoot = findConnectivity(lhsBit);
        uint64_t rhsRoot = findConnectivity(rhsBit);
        if (lhsRoot != rhsRoot)
          connectivityParents[std::max(lhsRoot, rhsRoot)] =
              std::min(lhsRoot, rhsRoot);
      }
    }
  }
  std::sort(scalarConnections.begin(), scalarConnections.end(),
            [](const ScalarConnection &lhs, const ScalarConnection &rhs) {
              return lhs.tie() < rhs.tie();
            });
  for (size_t index = 1; index < scalarConnections.size(); ++index)
    if (scalarConnections[index - 1].lhs == scalarConnections[index].lhs &&
        scalarConnections[index - 1].rhs == scalarConnections[index].rhs &&
        scalarConnections[index - 1].passSwitchId ==
            scalarConnections[index].passSwitchId)
      return reject(__LINE__, "duplicate scalar connectivity edge");

  // The serialized table is the unique maximal interval encoding of its
  // canonical scalar edges. Reject alternative spellings so malformed images
  // cannot hide duplicates in overlaps, swapped endpoints, or split runs.
  auto withinNet = [](const CaptureRecord *net, uint64_t bit) {
    return net && bit >= net->valueOffset &&
           bit - net->valueOffset < net->planeSize;
  };
  std::vector<ConnectivityRecord> canonicalRecords;
  for (size_t scalar = 0; scalar != scalarConnections.size();) {
    const ScalarConnection &first = scalarConnections[scalar];
    uint64_t width = 1;
    int direction = 0;
    size_t next = scalar + 1;
    // A record must lie inside one net on each side, so a run stops at a net
    // boundary even when the neighbouring edge continues the stride: two
    // unrelated net pairs can sit adjacent in the state layout.
    const CaptureRecord *lhsNet = containingNet(first.lhs, 1, false);
    const CaptureRecord *rhsNet = containingNet(first.rhs, 1, false);
    while (next != scalarConnections.size()) {
      const ScalarConnection &candidate = scalarConnections[next];
      if (candidate.lhsResolution != first.lhsResolution ||
          candidate.rhsResolution != first.rhsResolution ||
          candidate.dominanceFlags != first.dominanceFlags ||
          candidate.passSwitchId != first.passSwitchId ||
          candidate.lhs != first.lhs + width)
        break;
      if (!withinNet(lhsNet, candidate.lhs) ||
          !withinNet(rhsNet, candidate.rhs))
        break;
      int candidateDirection = 0;
      if (candidate.rhs == first.rhs + width)
        candidateDirection = 1;
      else if (first.rhs >= width && candidate.rhs == first.rhs - width)
        candidateDirection = -1;
      if (candidateDirection == 0 ||
          (direction != 0 && direction != candidateDirection))
        break;
      direction = candidateDirection;
      ++width;
      ++next;
    }
    canonicalRecords.push_back(
        {first.lhs, first.rhs, width, first.lhsResolution, first.rhsResolution,
         static_cast<uint8_t>((direction < 0) | first.dominanceFlags |
                              (first.passSwitchId ? 8 : 0)),
         0, first.passSwitchId});
    scalar = next;
  }
  if (canonicalRecords.size() != connectionRecords.size())
    return reject(__LINE__, "connectivity table is not maximally encoded");
  for (size_t index = 0; index != canonicalRecords.size(); ++index) {
    const ConnectivityRecord &actual = connectionRecords[index];
    const ConnectivityRecord &expected = canonicalRecords[index];
    if (actual.lhsOffset != expected.lhsOffset ||
        actual.rhsOffset != expected.rhsOffset ||
        actual.width != expected.width ||
        actual.lhsResolution != expected.lhsResolution ||
        actual.rhsResolution != expected.rhsResolution ||
        actual.flags != expected.flags ||
        actual.tailReserved != expected.tailReserved)
      return reject(__LINE__,
                    "connectivity table differs from its canonical encoding");
  }
  // Mixed collapsed nets must retain the unique dominating scalar endpoint.
  // This is both the source of the simulated net's resolution kind (23.3.3.7)
  // and a trust-boundary check on the serialized dominance flags.
  std::vector<uint8_t> resolutionByIndex(totalNetBits);
  for (size_t net = 0; net != netRecords.size(); ++net) {
    uint8_t resolution = decodeNetResolution(netRecords[net].argument);
    if (resolution == 1)
      resolution = 0;
    std::fill_n(resolutionByIndex.begin() + netBase[net],
                netRecords[net].planeSize, resolution);
  }
  // Per component root: the set of resolution kinds (bit per kind, kinds are
  // at most 9) and whether some edge lacks or carries serialized dominance.
  std::vector<uint16_t> componentKinds(totalNetBits);
  for (uint64_t index = 0; index != totalNetBits; ++index)
    componentKinds[findRoot(index)] |=
        static_cast<uint16_t>(1u << resolutionByIndex[index]);
  auto mixed = [&](uint64_t root) {
    return (componentKinds[root] & (componentKinds[root] - 1)) != 0;
  };
  constexpr uint8_t kIncompleteComponent = 1, kDirectedComponent = 2;
  std::vector<uint8_t> componentFlags(totalNetBits);
  // Dominance structure is consulted only for mixed components.
  std::unordered_map<uint64_t, std::vector<uint64_t>> componentBits;
  std::unordered_map<uint64_t, std::unordered_set<uint64_t>> dominatedBits;
  std::unordered_map<uint64_t,
                     std::unordered_map<uint64_t, std::vector<uint64_t>>>
      dominanceOutgoingByRoot;
  for (uint64_t index = 0; index != totalNetBits; ++index) {
    uint64_t root = findRoot(index);
    if (mixed(root))
      componentBits[root].push_back(index);
  }
  for (const ScalarConnection &connection : scalarConnections) {
    if (connection.passSwitchId)
      continue;
    uint8_t lhsResolution =
        connection.lhsResolution == 1 ? 0 : connection.lhsResolution;
    uint8_t rhsResolution =
        connection.rhsResolution == 1 ? 0 : connection.rhsResolution;
    bool hasDominance = (connection.dominanceFlags & 2) != 0;
    bool rhsDominates = (connection.dominanceFlags & 4) != 0;
    uint64_t root = findConnectivity(connection.lhs);
    componentFlags[root] |=
        hasDominance ? kDirectedComponent : kIncompleteComponent;
    if (hasDominance && mixed(root)) {
      uint64_t dominated =
          netBitIndex(rhsDominates ? connection.lhs : connection.rhs);
      uint64_t dominating =
          netBitIndex(rhsDominates ? connection.rhs : connection.lhs);
      dominatedBits[root].insert(dominated);
      dominanceOutgoingByRoot[root][dominated].push_back(dominating);
    }
    if (lhsResolution == rhsResolution)
      continue;
    if (!hasDominance)
      continue;
    uint8_t winner = rhsDominates ? rhsResolution : lhsResolution;
    uint8_t loser = rhsDominates ? lhsResolution : rhsResolution;
    auto isSupply = [](uint8_t kind) { return kind == 7 || kind == 8; };
    bool invalidWinner = false;
    if (isSupply(winner) != isSupply(loser))
      invalidWinner = !isSupply(winner);
    else if (!isSupply(winner) && ((winner == 2) != (loser == 2)))
      invalidWinner = winner != 2;
    else if (((winner == 9) && (loser == 5 || loser == 6)) ||
             ((loser == 9) && (winner == 5 || winner == 6)))
      invalidWinner = winner == 9;
    else if (!isSupply(winner) && winner != 2 && loser != 2 &&
             ((winner == 0) != (loser == 0)))
      invalidWinner = winner == 0;
    if (invalidWinner)
      return reject(__LINE__, "connectivity has an invalid dominant net type");
  }
  std::vector<uint8_t> effectiveResolutionByRoot(totalNetBits);
  for (uint64_t root = 0; root != totalNetBits; ++root) {
    if (connectivityParents[root] != root)
      continue;
    uint16_t kinds = componentKinds[root];
    if (!mixed(root)) {
      effectiveResolutionByRoot[root] =
          static_cast<uint8_t>(__builtin_ctz(kinds));
      continue;
    }
    // Older images could only contain mixed wire/tri and uwire topology, and
    // did not serialize dominance. Uwire is intrinsically dominant over the
    // other supported kinds, so accepting those images is unambiguous.
    bool legacyUWire = kinds == ((1u << 0) | (1u << 2));
    if (componentFlags[root] & kIncompleteComponent) {
      if (legacyUWire && !(componentFlags[root] & kDirectedComponent)) {
        effectiveResolutionByRoot[root] = 2;
        continue;
      }
      return reject(__LINE__, "mixed connectivity is missing port dominance");
    }
    const std::vector<uint64_t> &bits = componentBits[root];
    std::unordered_map<uint64_t, uint64_t> incomingCount;
    for (uint64_t bit : bits)
      incomingCount.emplace(bit, 0);
    const auto &dominanceOutgoing = dominanceOutgoingByRoot[root];
    for (const auto &[from, targets] : dominanceOutgoing)
      for (uint64_t target : targets)
        ++incomingCount[target];
    std::vector<uint64_t> pending;
    for (const auto &[bit, count] : incomingCount)
      if (count == 0)
        pending.push_back(bit);
    uint64_t visited = 0;
    while (!pending.empty()) {
      uint64_t bit = pending.back();
      pending.pop_back();
      ++visited;
      auto outgoing = dominanceOutgoing.find(bit);
      if (outgoing != dominanceOutgoing.end())
        for (uint64_t target : outgoing->second)
          if (--incomingCount[target] == 0)
            pending.push_back(target);
    }
    if (visited != incomingCount.size())
      return reject(__LINE__, "mixed connectivity has cyclic port dominance");
    std::optional<uint8_t> dominantKind;
    const std::unordered_set<uint64_t> &dominated = dominatedBits[root];
    for (uint64_t bit : bits) {
      if (dominated.count(bit))
        continue;
      uint8_t kind = resolutionByIndex[bit];
      if (dominantKind && *dominantKind != kind)
        return reject(
            __LINE__,
            "mixed connectivity has ambiguous dominant resolution kinds");
      dominantKind = kind;
    }
    if (!dominantKind)
      return reject(__LINE__,
                    "mixed connectivity has ambiguous port dominance");
    effectiveResolutionByRoot[root] = *dominantKind;
  }
  // Every logical alias of one simulated-net bit must mature together. The
  // compiler normalizes each member to the dominating net's delay; enforce
  // the same invariant at the bytecode trust boundary. Without delayed nets
  // every member has the same (absent) delay.
  if (std::any_of(netRecords.begin(), netRecords.end(),
                  [](const CaptureRecord &net) {
                    return (net.argument & (uint32_t{1} << 3)) != 0;
                  })) {
    std::unordered_map<uint64_t, std::optional<std::array<uint64_t, 3>>>
        componentDelays;
    for (size_t index = 0; index != netRecords.size(); ++index) {
      const CaptureRecord &net = netRecords[index];
      bool delayed = (net.argument & (uint32_t{1} << 3)) != 0;
      bool bitwise = (net.argument & (uint32_t{1} << 4)) != 0;
      for (uint64_t bit = 0; bit != net.planeSize; ++bit) {
        uint64_t root = findRoot(netBase[index] + bit);
        std::optional<std::array<uint64_t, 3>> delay;
        if (delayed) {
          const uint8_t *triple = image.data + image.constants +
                                  net.unknownOffset + (bitwise ? bit * 24 : 0);
          uint64_t rise = read64(triple);
          if (!bitwise || rise != UINT64_MAX) {
            delay = std::array<uint64_t, 3>{rise, read64(triple + 8),
                                            read64(triple + 16)};
            if ((*delay)[2] == UINT64_MAX &&
                effectiveResolutionByRoot[root] != 9)
              return reject(
                  __LINE__,
                  "omitted charge decay requires an effective trireg");
          }
        }
        auto [found, inserted] = componentDelays.try_emplace(root, delay);
        if (!inserted && found->second != delay)
          return reject(
              __LINE__,
              "collapsed net members have unequal propagation delays");
      }
    }
  }
  // A uwire component has at most one design-lifetime driver for every
  // connected scalar equivalence class, including aliases of its target.
  std::unordered_map<uint64_t, uint32_t> uwireDrivers;
  for (const CaptureRecord &driver : driverRecords) {
    if ((driver.argument & (uint32_t{1} << 11)) != 0)
      continue;
    for (uint64_t bit = 0; bit != driver.planeSize; ++bit) {
      uint64_t root = findConnectivity(driver.unknownOffset + bit);
      if (effectiveResolutionByRoot[root] != 2)
        continue;
      if (++uwireDrivers[root] > 1)
        return reject(__LINE__,
                      "uwire connectivity component has multiple drivers");
    }
  }
  uint64_t previousID = 0;
  for (uint32_t functionIndex = 0; functionIndex != image.functionCount;
       ++functionIndex) {
    Function function = functionAt(image, functionIndex);
    if (function.id == 0 || function.initialScheduleRank > UINT32_MAX ||
        (functionIndex != 0 && function.id <= previousID) ||
        function.firstInstruction > image.instructionCount ||
        function.instructionCount == 0 ||
        function.instructionCount >
            image.instructionCount - function.firstInstruction ||
        function.firstLayout > image.layoutCount ||
        function.layoutCount > image.layoutCount - function.firstLayout ||
        function.argumentCount > function.layoutCount ||
        function.resultCount > function.layoutCount - function.argumentCount ||
        function.scratchAlignment == 0 || function.scratchAlignment > 4096 ||
        (function.scratchAlignment & (function.scratchAlignment - 1)) != 0 ||
        function.scratchSize % function.scratchAlignment != 0 ||
        !validProcessFunctionFlags(function) ||
        function.continuationCount == 0 ||
        function.firstContinuation > image.continuationCount ||
        function.continuationCount >
            image.continuationCount - function.firstContinuation)
      return reject(__LINE__, "invalid function metadata or table range",
                    functionIndex);
    previousID = function.id;
    uint64_t previousEnd = 0;
    for (uint32_t registerIndex = 0; registerIndex != function.layoutCount;
         ++registerIndex) {
      // Shapes were validated up front; the record adds the frame offset.
      Layout layout = layoutAt(image, function, registerIndex);
      if (layout.offset % 8 != 0 || layout.offset < previousEnd ||
          layout.offset > function.scratchSize ||
          layout.size > function.scratchSize - layout.offset)
        return reject(__LINE__, "invalid or overlapping register layout",
                      functionIndex);
      previousEnd = layout.offset + layout.size;
    }
    uint32_t previousContinuation = 0;
    for (uint64_t index = 0; index != function.continuationCount; ++index) {
      Continuation entry =
          continuationAt(image, function.firstContinuation + index);
      if (entry.function != functionIndex || entry.reserved != 0 ||
          (index == 0 ? entry.id != 0 : entry.id <= previousContinuation) ||
          entry.instruction < function.firstInstruction ||
          entry.instruction >=
              function.firstInstruction + function.instructionCount)
        return reject(__LINE__, "invalid or misordered continuation record",
                      functionIndex);
      previousContinuation = entry.id;
    }
    if ((function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 &&
        continuationAt(image, function.firstContinuation).instruction !=
            function.firstInstruction)
      return reject(__LINE__,
                    "zero-time function entry continuation is invalid",
                    functionIndex);
  }
  // Instructions are checked against every function's metadata and layouts
  // (callees included), so check them only once all of those are validated.
  if (validateCode)
    for (uint32_t functionIndex = 0; functionIndex != image.functionCount;
         ++functionIndex)
      if (!validateFunctionCode(image, functionIndex))
        return false;
  return true;
}

const Image *validatedImage(const talos_rt_design_bytecode_entry_v1 &entry,
                            talos_rt_context *context, Image &storage,
                            bool inventoryOnly) {
  if (entry.reserved != 0) {
    rejectImage(__LINE__, "bytecode entry reserved field is nonzero");
    return nullptr;
  }
  // Context creation validates the complete inventory and immutable bytecode
  // image before publishing the context. Standalone entries retain full
  // checksum and structural validation.
  if (context && context->execution == entry.execution &&
      context->designBytecodeImageValidated) {
    const Image &cached = context->designBytecodeImage;
    if (cached.data != entry.execution->bytecode ||
        cached.size != entry.execution->bytecode_size ||
        cached.stateBitCount != entry.execution->state_bit_count ||
        (!inventoryOnly && entry.function >= cached.functionCount)) {
      rejectImage(__LINE__, "cached bytecode image does not match entry");
      return nullptr;
    }
    return &cached;
  }
  return parseImage(entry, storage, inventoryOnly) && validateImage(storage)
             ? &storage
             : nullptr;
}

bool loadValidatedImage(const talos_rt_design_bytecode_entry_v1 &entry,
                        talos_rt_context *context, Image &image,
                        bool inventoryOnly) {
  const Image *validated = validatedImage(entry, context, image, inventoryOnly);
  if (validated && validated != &image)
    image = *validated;
  return validated != nullptr;
}

} // namespace talos::designbytecode

using namespace talos::designbytecode;

static bool matchesActivationBytecodeInventory(
    const talos_rt_execution_descriptor_v1 &execution, const Image &image) {
  for (uint64_t index = 0; index != execution.activation_count; ++index) {
    const talos_rt_activation_descriptor_v1 &activation =
        execution.activations[index];
    if ((activation.flags & TALOS_RT_ACTIVATION_HAS_BYTECODE) == 0)
      continue;
    if (activation.bytecode_function >= image.functionCount)
      return rejectImage(__LINE__,
                         "activation bytecode function is out of range");
    Function function = functionAt(image, activation.bytecode_function);
    if (function.id != activation.code_unit_id ||
        (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) == 0 ||
        function.resultCount != 0)
      return rejectImage(
          __LINE__, "activation descriptor does not match bytecode function");
  }
  for (uint64_t index = 0; index != execution.observer_count; ++index) {
    const talos_rt_observer_descriptor_v1 &observer =
        execution.observers[index];
    if (observer.bytecode_function == TALOS_RT_OBSERVER_NO_BYTECODE)
      continue;
    if (observer.bytecode_function >= image.functionCount)
      return rejectImage(__LINE__,
                         "observer bytecode function is out of range");
    Function function = functionAt(image, observer.bytecode_function);
    if (function.id != observer.code_unit_id ||
        (function.flags & TALOS_RT_DESIGN_FUNCTION_PROCESS) != 0 ||
        function.resultCount != 1 ||
        function.argumentCount != observer.capture_count + 1)
      return rejectImage(
          __LINE__, "observer descriptor does not match bytecode function");
    Layout result = layoutAt(image, function, function.argumentCount);
    bool fourState = (observer.flags & TALOS_RT_OBSERVER_FOUR_STATE) != 0;
    uint32_t expectedKind = (observer.flags & TALOS_RT_OBSERVER_REAL32) != 0
                                ? TALOS_RT_DBREG_REAL32
                            : (observer.flags & TALOS_RT_OBSERVER_REAL64) != 0
                                ? TALOS_RT_DBREG_REAL64
                            : fourState ? TALOS_RT_DBREG_LOGIC
                                        : TALOS_RT_DBREG_BITS;
    if (layoutAt(image, function, 0).kind != TALOS_RT_DBREG_HANDLE ||
        layoutAt(image, function, 0).size != 32 ||
        result.width != observer.result_width || result.kind != expectedKind)
      return rejectImage(__LINE__,
                         "observer layout does not match bytecode function");
    for (uint32_t capture = 0; capture != observer.capture_count; ++capture) {
      Layout captureLayout = layoutAt(image, function, capture + 1);
      const talos_rt_observer_capture_abi_v1 &abi =
          observer.capture_abi[capture];
      if (abi.kind == TALOS_RT_OBSERVER_CAPTURE_ARGUMENT_REF) {
        if (captureLayout.kind != TALOS_RT_DBREG_ARGUMENT_REF ||
            captureLayout.size != 24)
          return rejectImage(
              __LINE__,
              "argument-ref observer capture layout is not a 24-byte alias");
        continue;
      }
      if (abi.kind == TALOS_RT_OBSERVER_CAPTURE_MANAGED) {
        if (captureLayout.kind != TALOS_RT_DBREG_MANAGED ||
            captureLayout.size != 8)
          return rejectImage(__LINE__,
                             "managed observer capture layout is not a handle");
        continue;
      }
      if (abi.kind == TALOS_RT_OBSERVER_CAPTURE_COVERGROUP) {
        if (captureLayout.kind != TALOS_RT_DBREG_BITS ||
            captureLayout.width != 64 || captureLayout.size != 8)
          return rejectImage(
              __LINE__,
              "covergroup observer capture layout is not an i64 value");
        continue;
      }
      if (captureLayout.kind != TALOS_RT_DBREG_HANDLE ||
          captureLayout.size != 32)
        return rejectImage(__LINE__,
                           "observer capture layout is not a 32-byte handle");
    }
  }
  return true;
}

talos_rt_status talos_rt_initialize_design_bytecode_image(
    const talos_rt_execution_descriptor_v1 &execution,
    Image &outImage) noexcept {
  if ((execution.flags & TALOS_RT_EXECUTION_HAS_BYTECODE) == 0)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    talos_rt_design_bytecode_entry_v1 entry{&execution, 0, 0};
    Image image;
    if (!parseImage(entry, image, /*inventoryOnly=*/true) ||
        !validateImage(image, /*validateCode=*/false) ||
        !matchesActivationBytecodeInventory(execution, image))
      return TALOS_RT_INVALID_DESIGN;
    outImage = image;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL {
    rejectImage(__LINE__, "exception while validating bytecode image");
    return TALOS_RT_INVALID_DESIGN;
  }
}

talos_rt_status talos_rt_validate_design_bytecode(
    const talos_rt_design_bytecode_entry_v1 &entry, talos_rt_context *context,
    uint64_t *outScratchSize, uint64_t *outScratchAlignment) noexcept {
  TALOS_RT_TRY {
    Image image;
    if (!loadValidatedImage(entry, context, image))
      return TALOS_RT_INVALID_BYTECODE;
    Function function = functionAt(image, entry.function);
    if (outScratchSize)
      *outScratchSize = function.scratchSize;
    if (outScratchAlignment)
      *outScratchAlignment = function.scratchAlignment;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL {
    rejectImage(__LINE__, "exception while loading bytecode image");
    return TALOS_RT_INVALID_BYTECODE;
  }
}
