//===- BytecodeImageTestPass.cpp - Print design-bytecode records ---------===//
//
// Decode the module's serialized design-bytecode image and print its
// instruction stream and side tables, one record per line.
//
//===----------------------------------------------------------------------===//

#include "AnalysisTestPasses.h"

#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Runtime/Runtime.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/Endian.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"

#include <array>
#include <cstddef>

using namespace mlir;

namespace {

using Header = talos_rt_design_bytecode_header_v1;

/// Bounds-checked little-endian reader over one serialized image.
class ImageReader {
public:
  explicit ImageReader(ArrayRef<uint8_t> image) : image(image) {}

  template <typename T> T read(uint64_t offset) const {
    return llvm::support::endian::read<T, llvm::endianness::little>(
        image.data() + offset);
  }
  uint64_t header(size_t field) const { return read<uint64_t>(field); }

  /// Return whether `count` records of `size` bytes fit at `offset`.
  bool fits(uint64_t offset, uint64_t count, uint64_t size) const {
    return offset <= image.size() && count <= (image.size() - offset) / size;
  }

  ArrayRef<uint8_t> image;
};

class BytecodeImageTestPass
    : public PassWrapper<BytecodeImageTestPass, OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(BytecodeImageTestPass)

  BytecodeImageTestPass() = default;
  BytecodeImageTestPass(const BytecodeImageTestPass &other)
      : PassWrapper(other) {}

  StringRef getArgument() const final { return "test-talos-print-bytecode"; }
  StringRef getDescription() const final {
    return "print the serialized design-bytecode image records";
  }

  Option<bool> metadata{*this, "metadata",
                        llvm::cl::desc("print function, register-layout, and "
                                       "operand-map metadata"),
                        llvm::cl::init(false)};
  Option<bool> shapes{*this, "shapes",
                      llvm::cl::desc("print the shared register shape table"),
                      llvm::cl::init(false)};
  Option<bool> state{*this, "state",
                     llvm::cl::desc("print static net and driver state "
                                    "descriptors"),
                     llvm::cl::init(false)};

  void runOnOperation() final {
    ModuleOp module = getOperation();
    DenseI8ArrayAttr attr =
        talos::runtime::get<talos::runtime::BytecodeImage>(module);
    if (!attr) {
      module.emitError("missing ")
          << talos::runtime::BytecodeImage::getNameStr() << " attribute";
      return signalPassFailure();
    }
    ArrayRef<int8_t> signedImage = attr.asArrayRef();
    ArrayRef<uint8_t> image(
        reinterpret_cast<const uint8_t *>(signedImage.data()),
        signedImage.size());
    if (image.size() < TALOS_RT_DESIGN_BYTECODE_HEADER_SIZE ||
        StringRef(reinterpret_cast<const char *>(image.data()), 8) !=
            StringRef(TALOS_RT_DESIGN_BYTECODE_MAGIC, 8)) {
      module.emitError("invalid Talos design-bytecode header");
      return signalPassFailure();
    }
    if (failed(print(ImageReader(image), llvm::errs()))) {
      module.emitError("malformed Talos design-bytecode image");
      return signalPassFailure();
    }
  }

private:
  LogicalResult print(const ImageReader &reader, raw_ostream &os) const {
    if (shapes) {
      uint64_t offset = reader.header(offsetof(Header, shape_offset));
      uint64_t count = reader.header(offsetof(Header, shape_count));
      uint64_t registers = reader.header(offsetof(Header, layout_count));
      if (!reader.fits(offset, count, 24))
        return failure();
      os << "shapes " << count << " registers " << registers << '\n';
      for (uint64_t index = 0; index < count; ++index) {
        uint64_t shape = offset + index * 24;
        os << "shape " << index
           << ": kind=" << unsigned(reader.read<uint8_t>(shape))
           << " flags=" << unsigned(reader.read<uint8_t>(shape + 1))
           << " width=" << reader.read<uint32_t>(shape + 4)
           << " size=" << reader.read<uint64_t>(shape + 8)
           << " auxiliary=" << reader.read<uint64_t>(shape + 16) << '\n';
      }
    }
    if (state) {
      uint64_t offset = reader.header(offsetof(Header, state_offset));
      uint64_t count = reader.header(offsetof(Header, state_count));
      if (!reader.fits(offset, count, 32))
        return failure();
      for (uint64_t index = 0; index < count; ++index) {
        uint64_t record = offset + index * 32;
        uint32_t kind = reader.read<uint32_t>(record);
        uint32_t flags = reader.read<uint32_t>(record + 4);
        os << "state " << index << ": kind=";
        if (kind == 0xFFFFFFFEu) {
          os << "net";
        } else if (kind == 0xFFFFFFFFu) {
          os << "driver";
        } else {
          os << "capture";
        }
        os << " flags=" << flags
           << " value=" << reader.read<uint64_t>(record + 8)
           << " target=" << reader.read<uint64_t>(record + 16)
           << " width=" << reader.read<uint64_t>(record + 24);
        if (kind == 0xFFFFFFFFu) {
          // Strength code 0 is the default strong drive (6); other codes are
          // offset by one from the strength ordinal.
          auto strength = [](uint32_t code) { return code ? code - 1 : 6; };
          os << " strength0=" << strength((flags >> 3) & 0xF)
             << " strength1=" << strength((flags >> 7) & 0xF);
        }
        os << '\n';
      }
    }

    uint64_t codeOffset = reader.header(offsetof(Header, code_offset));
    uint64_t instructionCount =
        reader.header(offsetof(Header, instruction_count));
    bool compact = (reader.read<uint32_t>(offsetof(Header, flags)) &
                    TALOS_RT_DESIGN_BYTECODE_COMPACT_CODE) != 0;
    uint64_t codeSize =
        compact ? reader.header(offsetof(Header, code_size))
                : instructionCount * TALOS_RT_DESIGN_BYTECODE_INSTRUCTION_SIZE;
    if ((!compact && !reader.fits(codeOffset, instructionCount,
                                  TALOS_RT_DESIGN_BYTECODE_INSTRUCTION_SIZE)) ||
        !reader.fits(codeOffset, codeSize, 1) ||
        (compact && codeSize / 4 < instructionCount))
      return failure();
    // Fields: opcode, flags, destination, source0..2, auxiliary, immediate.
    auto decode = [&](uint64_t index,
                      std::array<uint64_t, 8> &fields) -> LogicalResult {
      fields = {};
      if (!compact) {
        uint64_t record =
            codeOffset + index * TALOS_RT_DESIGN_BYTECODE_INSTRUCTION_SIZE;
        fields = {reader.read<uint16_t>(record),
                  reader.read<uint16_t>(record + 2),
                  reader.read<uint32_t>(record + 4),
                  reader.read<uint32_t>(record + 8),
                  reader.read<uint32_t>(record + 12),
                  reader.read<uint32_t>(record + 16),
                  reader.read<uint32_t>(record + 20),
                  reader.read<uint64_t>(record + 24)};
        return success();
      }
      uint64_t bytes = codeOffset + instructionCount * 4;
      uint64_t byteCount = codeSize - instructionCount * 4;
      uint64_t begin = reader.read<uint32_t>(codeOffset + index * 4);
      uint64_t end = index + 1 == instructionCount
                         ? byteCount
                         : reader.read<uint32_t>(codeOffset + (index + 1) * 4);
      if (begin + 2 > end || end > byteCount)
        return failure();
      uint64_t cursor = bytes + begin;
      fields[0] = reader.read<uint8_t>(cursor++);
      uint8_t mask = reader.read<uint8_t>(cursor++);
      for (unsigned bit = 0; bit != 7; ++bit) {
        if ((mask & (1u << bit)) == 0)
          continue;
        uint64_t value = 0;
        for (unsigned shift = 0;; shift += 7) {
          if (cursor == bytes + end || shift > 63)
            return failure();
          uint8_t byte = reader.read<uint8_t>(cursor++);
          value |= uint64_t{byte & 0x7fu} << shift;
          if ((byte & 0x80) == 0)
            break;
        }
        fields[bit + 1] = value;
      }
      return success(cursor == bytes + end);
    };

    uint64_t constantOffset = reader.header(offsetof(Header, constant_offset));
    uint64_t constantSize = reader.header(offsetof(Header, constant_size));
    if (!reader.fits(constantOffset, constantSize, 1))
      return failure();
    os << "constants: "
       << llvm::toHex(reader.image.slice(constantOffset, constantSize),
                      /*LowerCase=*/true)
       << '\n';

    uint64_t operandOffset = reader.header(offsetof(Header, operand_offset));
    uint64_t operandCount = reader.header(offsetof(Header, operand_count));
    if (!reader.fits(operandOffset, operandCount, 8))
      return failure();
    auto operandDestination = [&](uint64_t index) {
      return reader.read<uint32_t>(operandOffset + index * 8);
    };
    auto operandSource = [&](uint64_t index) {
      return reader.read<uint32_t>(operandOffset + index * 8 + 4);
    };

    if (metadata) {
      uint64_t functionOffset =
          reader.header(offsetof(Header, function_offset));
      uint64_t functionCount = reader.header(offsetof(Header, function_count));
      uint64_t layoutOffset = reader.header(offsetof(Header, layout_offset));
      uint64_t layoutCount = reader.header(offsetof(Header, layout_count));
      uint64_t shapeOffset = reader.header(offsetof(Header, shape_offset));
      uint64_t shapeCount = reader.header(offsetof(Header, shape_count));
      if (!reader.fits(functionOffset, functionCount, 96) ||
          !reader.fits(layoutOffset, layoutCount, 8) ||
          !reader.fits(shapeOffset, shapeCount, 24))
        return failure();
      for (uint64_t index = 0; index < functionCount; ++index) {
        uint64_t record = functionOffset + index * 96;
        uint64_t firstLayout = reader.read<uint64_t>(record + 32);
        uint64_t functionLayoutCount = reader.read<uint64_t>(record + 40);
        if (firstLayout > layoutCount ||
            functionLayoutCount > layoutCount - firstLayout)
          return failure();
        os << "function " << index << ": id=" << reader.read<uint64_t>(record)
           << " rank=" << reader.read<uint64_t>(record + 8)
           << " first_instruction=" << reader.read<uint64_t>(record + 16)
           << " instruction_count=" << reader.read<uint64_t>(record + 24)
           << " arguments=" << reader.read<uint32_t>(record + 48)
           << " results=" << reader.read<uint32_t>(record + 52) << '\n';
        for (uint64_t reg = 0; reg < functionLayoutCount; ++reg) {
          // A layout record is {shape index, frame offset}.
          uint64_t layout = layoutOffset + (firstLayout + reg) * 8;
          uint32_t shapeIndex = reader.read<uint32_t>(layout);
          if (shapeIndex >= shapeCount)
            return failure();
          uint64_t shape = shapeOffset + uint64_t{shapeIndex} * 24;
          os << "layout function=" << index << " register=" << reg
             << " kind=" << unsigned(reader.read<uint8_t>(shape))
             << " flags=" << unsigned(reader.read<uint8_t>(shape + 1))
             << " width=" << reader.read<uint32_t>(shape + 4)
             << " offset=" << reader.read<uint32_t>(layout + 4)
             << " size=" << reader.read<uint64_t>(shape + 8)
             << " auxiliary=" << reader.read<uint64_t>(shape + 16) << '\n';
        }
      }
      for (uint64_t index = 0; index < operandCount; ++index)
        os << "operand " << index << ": dst=" << operandDestination(index)
           << " src=" << operandSource(index) << '\n';
    }

    for (uint64_t index = 0; index < instructionCount; ++index) {
      std::array<uint64_t, 8> fields;
      if (failed(decode(index, fields)))
        return failure();
      os << index << ": opcode=" << fields[0] << " flags=" << fields[1]
         << " dst=" << fields[2] << " src0=" << fields[3]
         << " src1=" << fields[4] << " src2=" << fields[5]
         << " aux=" << fields[6] << " imm=" << fields[7] << '\n';
      if (metadata && (fields[0] == TALOS_RT_DB_NATIVE_VIRTUAL_CALL ||
                       fields[0] == TALOS_RT_DB_NATIVE_INTERFACE_CALL ||
                       fields[0] == TALOS_RT_DB_NATIVE_DIRECT_CALL)) {
        uint64_t site = constantOffset + fields[6];
        if (!reader.fits(site, 1, 24))
          return failure();
        uint32_t inputs = reader.read<uint32_t>(site + 4);
        uint32_t outputs = reader.read<uint32_t>(site + 8);
        os << "native method: argument_planes=" << inputs
           << " result_planes=" << outputs
           << " result_size=" << reader.read<uint64_t>(site + 16) << '\n';
        if (!reader.fits(site + 24, uint64_t{inputs} + outputs, 16))
          return failure();
        for (uint64_t plane = 0; plane != uint64_t{inputs} + outputs; ++plane) {
          uint64_t record = site + 24 + plane * 16;
          os << (plane < inputs ? "argument" : "result")
             << " plane=" << (plane < inputs ? plane : plane - inputs)
             << " register=" << reader.read<uint32_t>(record)
             << " byte_offset=" << reader.read<uint32_t>(record + 4)
             << " native_size=" << reader.read<uint32_t>(record + 8)
             << " result_offset=" << reader.read<uint32_t>(record + 12) << '\n';
        }
      }
    }

    uint64_t continuationOffset =
        reader.header(offsetof(Header, continuation_offset));
    uint64_t continuationCount =
        reader.header(offsetof(Header, continuation_count));
    if (!reader.fits(continuationOffset, continuationCount, 24))
      return failure();
    for (uint64_t index = 0; index < continuationCount; ++index) {
      uint64_t record = continuationOffset + index * 24;
      os << "continuation " << index
         << ": function=" << reader.read<uint32_t>(record)
         << " id=" << reader.read<uint32_t>(record + 4)
         << " instruction=" << reader.read<uint64_t>(record + 8)
         << " rank=" << reader.read<uint32_t>(record + 16)
         << " reserved=" << reader.read<uint32_t>(record + 20) << '\n';
    }

    uint64_t intrinsicOffset =
        reader.header(offsetof(Header, intrinsic_offset));
    uint64_t intrinsicCount = reader.header(offsetof(Header, intrinsic_count));
    if (!reader.fits(intrinsicOffset, intrinsicCount, 16))
      return failure();
    auto intrinsicId = [&](uint64_t index) {
      return reader.read<uint32_t>(intrinsicOffset + index * 16);
    };
    for (uint64_t index = 0; index < intrinsicCount; ++index) {
      uint64_t record = intrinsicOffset + index * 16;
      os << "intrinsic " << index
         << ": id=" << llvm::format_hex(intrinsicId(index), 10)
         << " inputs=" << reader.read<uint32_t>(record + 4)
         << " outputs=" << reader.read<uint32_t>(record + 8)
         << " flags=" << reader.read<uint32_t>(record + 12) << '\n';
    }

    uint64_t siteOffset = reader.header(offsetof(Header, site_offset));
    uint64_t siteCount = reader.header(offsetof(Header, site_count));
    if (!reader.fits(siteOffset, siteCount, 16))
      return failure();
    for (uint64_t index = 0; index < siteCount; ++index) {
      uint64_t record = siteOffset + index * 16;
      uint32_t signature = reader.read<uint32_t>(record);
      uint64_t firstOperand = reader.read<uint32_t>(record + 4);
      uint64_t inputCount = reader.read<uint32_t>(record + 8);
      uint64_t outputCount = reader.read<uint32_t>(record + 12);
      if (signature >= intrinsicCount || firstOperand > operandCount ||
          inputCount + outputCount > operandCount - firstOperand)
        return failure();
      os << "site " << index << ": signature=" << signature
         << " id=" << llvm::format_hex(intrinsicId(signature), 10)
         << " inputs=[";
      for (uint64_t input = 0; input < inputCount; ++input)
        os << (input ? ", " : "") << operandSource(firstOperand + input);
      os << "] outputs=[";
      for (uint64_t output = 0; output < outputCount; ++output)
        os << (output ? ", " : "")
           << operandDestination(firstOperand + inputCount + output);
      os << "]\n";
    }
    return success();
  }
};

} // namespace

namespace talos {
void registerBytecodeImageTestPass() {
  PassRegistration<BytecodeImageTestPass>();
}
} // namespace talos
