//===- RandomBoundsTest.cpp - Exhaustive payload length bounds
//-------------===//

#include "PrepareRandomIteration.h"
#include "talos/Dialect/Talos/TalosDialect.h"
#include "talos/Dialect/Talos/TalosOps.h"
#include "talos/Dialect/Talos/TalosTypes.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "gtest/gtest.h"

#include <algorithm>
#include <optional>

using namespace mlir;
using namespace talos::simlowering;
namespace semantic = talos::ir;
using Binary = semantic::SVBinaryOperator;
using llvm::APInt;
using llvm::APSInt;

namespace {
class RandomBoundsTest : public testing::Test {
protected:
  MLIRContext context;
  Builder builder{&context};
  OwningOpRef<ModuleOp> owner{ModuleOp::create(builder.getUnknownLoc())};
  llvm::DenseMap<Operation *, RandomIntegralBounds> inputs;

  RandomBoundsTest() { context.loadDialect<semantic::TalosDialect>(); }

  Type type(unsigned width, bool isSigned, bool fourState = false) {
    return semantic::IntegralType::get(
        &context, width, isSigned, fourState, width - 1, 0,
        fourState ? semantic::SVIntegralFlavor::Logic
                  : semantic::SVIntegralFlavor::Bit);
  }
  Operation *node(StringRef name, Type type,
                  ArrayRef<NamedAttribute> attributes,
                  ArrayRef<Operation *> children = {}) {
    OperationState state(builder.getUnknownLoc(), name);
    state.addAttribute("node_id", builder.getI64IntegerAttr(1));
    state.addAttribute("semantic_type", TypeAttr::get(type));
    state.addAttribute(
        "is_signed",
        builder.getBoolAttr(cast<semantic::IntegralType>(type).getIsSigned()));
    state.addAttributes(attributes);
    Block *body = new Block();
    state.addRegion()->push_back(body);
    for (Operation *child : children) {
      child->remove();
      body->push_back(child);
    }
    Operation *result = Operation::create(state);
    owner->getBody()->push_back(result);
    return result;
  }
  static APSInt value(int64_t v) {
    return APSInt(APInt(randomConstantWidth, static_cast<uint64_t>(v), true),
                  false);
  }
  Operation *input(Type t, int64_t lower, int64_t upper) {
    Operation *result =
        node(semantic::SVNamedValueExpressionOp::getOperationName(), t, {});
    inputs.try_emplace(result,
                       RandomIntegralBounds{value(lower), value(upper)});
    return result;
  }
  Operation *literal(Type t, int64_t v) {
    return node(
        semantic::SVIntegerLiteralOp::getOperationName(), t,
        {builder.getNamedAttr("constant_value",
                              builder.getStringAttr(std::to_string(v)))});
  }
  Operation *binary(Type t, Binary kind, Operation *lhs, Operation *rhs) {
    return node(semantic::SVBinaryExpressionOp::getOperationName(), t,
                {builder.getNamedAttr(
                    "operator_kind",
                    semantic::SVBinaryOperatorAttr::get(&context, kind))},
                {lhs, rhs});
  }
  Operation *convert(Type t, Operation *operand) {
    return node(semantic::SVConversionExpressionOp::getOperationName(), t, {},
                {operand});
  }
  std::optional<RandomIntegralBounds> bounds(Operation *expression) {
    return evaluateRandomOperandBounds(
        expression,
        [&](Operation *value) -> std::optional<RandomIntegralBounds> {
          auto found = inputs.find(value);
          return found == inputs.end() ? std::nullopt
                                       : std::optional(found->second);
        },
        [](Operation *) -> std::optional<llvm::StringRef> {
          return std::nullopt;
        });
  }
  void contains(const RandomIntegralBounds &bounds, const APInt &result,
                bool isSigned) {
    APSInt numeric(isSigned ? result.sext(randomConstantWidth)
                            : result.zext(randomConstantWidth),
                   false);
    EXPECT_LE(bounds.lower, numeric);
    EXPECT_GE(bounds.upper, numeric);
  }
};

// Enumerate typed execution independently of mathematical interval propagation,
// including wrapping, negative operands, truncating division and remainder.
TEST_F(RandomBoundsTest, ExhaustiveSmallArithmeticDomains) {
  for (unsigned width : {3u, 4u, 5u, 8u}) {
    for (bool isSigned : {false, true}) {
      int64_t minimum = isSigned ? -(int64_t{1} << (width - 1)) : 0;
      int64_t maximum = (int64_t{1} << (width - (isSigned ? 1 : 0))) - 1;
      SmallVector<std::pair<int64_t, int64_t>> intervals{
          {minimum, minimum + 3},
          {maximum - 3, maximum},
          {std::max(minimum, int64_t{-2}), std::min(maximum, int64_t{2})},
          {0, std::min(maximum, int64_t{3})}};
      Type t = type(width, isSigned);
      for (Binary kind : {Binary::Add, Binary::Subtract, Binary::Multiply,
                          Binary::Divide, Binary::Mod, Binary::BinaryAnd}) {
        for (auto lhs : intervals) {
          for (auto rhs : intervals) {
            auto inferred =
                bounds(binary(t, kind, input(t, lhs.first, lhs.second),
                              input(t, rhs.first, rhs.second)));
            if (!inferred) {
              ASSERT_TRUE((kind == Binary::Divide || kind == Binary::Mod) &&
                          rhs.first <= 0 && rhs.second >= 0);
              continue;
            }
            EXPECT_FALSE(inferred->mayBeUnknown);
            for (int64_t a = lhs.first; a <= lhs.second; ++a) {
              for (int64_t b = rhs.first; b <= rhs.second; ++b) {
                APInt left(width, static_cast<uint64_t>(a), true);
                APInt right(width, static_cast<uint64_t>(b), true);
                APInt result(width, 0);
                switch (kind) {
                case Binary::Add:
                  result = left + right;
                  break;
                case Binary::Subtract:
                  result = left - right;
                  break;
                case Binary::Multiply:
                  result = left * right;
                  break;
                case Binary::Divide:
                  if (b == 0)
                    continue;
                  result = isSigned ? left.sdiv(right) : left.udiv(right);
                  break;
                case Binary::Mod:
                  if (b == 0)
                    continue;
                  result = isSigned ? left.srem(right) : left.urem(right);
                  break;
                case Binary::BinaryAnd:
                  result = left & right;
                  break;
                default:
                  FAIL();
                }
                contains(*inferred, result, isSigned);
              }
            }
          }
        }
      }
    }
  }
}

TEST_F(RandomBoundsTest, ExhaustiveConstantShiftsAndNarrowing) {
  for (bool isSigned : {false, true}) {
    Type t = type(8, isSigned);
    int64_t minimum = isSigned ? -128 : 0, maximum = isSigned ? 127 : 255;
    for (Binary kind :
         {Binary::LogicalShiftLeft, Binary::ArithmeticShiftLeft,
          Binary::LogicalShiftRight, Binary::ArithmeticShiftRight}) {
      for (unsigned shift : {0u, 1u, 3u, 7u, 8u, 9u}) {
        auto inferred = bounds(binary(t, kind, input(t, minimum, maximum),
                                      literal(type(8, false), shift)));
        ASSERT_TRUE(inferred);
        for (int64_t n = minimum; n <= maximum; ++n) {
          APInt bits(8, static_cast<uint64_t>(n), true), result(8, 0);
          if (shift >= 8)
            result = kind == Binary::ArithmeticShiftRight && isSigned && n < 0
                         ? APInt::getAllOnes(8)
                         : APInt(8, 0);
          else if (kind == Binary::LogicalShiftLeft ||
                   kind == Binary::ArithmeticShiftLeft)
            result = bits.shl(shift);
          else if (kind == Binary::ArithmeticShiftRight && isSigned)
            result = bits.ashr(shift);
          else
            result = bits.lshr(shift);
          contains(*inferred, result, isSigned);
        }
      }
    }
    for (bool narrowSigned : {false, true}) {
      auto inferred =
          bounds(convert(type(3, narrowSigned), input(t, minimum, maximum)));
      ASSERT_TRUE(inferred);
      for (int64_t n = minimum; n <= maximum; ++n)
        contains(*inferred, APInt(3, static_cast<uint64_t>(n), true),
                 narrowSigned);
    }
  }
}

TEST_F(RandomBoundsTest,
       UnknownArithmeticAndMergedBitsCannotNarrowTwoStateCast) {
  Type logic = type(8, false, true), bits = type(8, false);
  auto masked =
      binary(logic, Binary::BinaryAnd, input(logic, 0, 255), literal(logic, 7));
  auto sum = binary(logic, Binary::Add, masked, literal(logic, 8));
  auto inferred = bounds(convert(bits, sum));
  ASSERT_TRUE(inferred);
  // X & 7 still has unknown low bits; adding8 gives X; the cast yields0.
  contains(*inferred, APInt(8, 0), false);
  EXPECT_FALSE(inferred->mayBeUnknown);

  for (bool isSigned : {false, true}) {
    Type t = type(4, isSigned, true);
    Operation *conditional = node(
        semantic::SVConditionalExpressionOp::getOperationName(), t,
        {builder.getNamedAttr("condition_count", builder.getI64IntegerAttr(1)),
         builder.getNamedAttr("condition_pattern_flags",
                              builder.getDenseI64ArrayAttr({0}))},
        {input(type(1, false, true), 0, 1), literal(t, isSigned ? -3 : 5),
         literal(t, isSigned ? -2 : 6)});
    ASSERT_TRUE(conditional->getAttr("condition_count"));
    auto merged = bounds(convert(type(4, isSigned), conditional));
    ASSERT_TRUE(merged);
    // X ? 5 : 6 becomes01XX ->4; X ? -3 : -2 becomes11XX ->-4.
    contains(*merged, APInt(4, isSigned ? uint64_t(-4) : 4), isSigned);
    EXPECT_FALSE(merged->mayBeUnknown);
  }
}

TEST_F(RandomBoundsTest, WideOverflowUsesTheEntireResultDomain) {
  Type t = type(64, false);
  Operation *maximum = input(t, 0, 0);
  APSInt top(APInt::getAllOnes(64).zext(randomConstantWidth), false);
  inputs[maximum] = {top, top};
  auto product = bounds(binary(t, Binary::Multiply, maximum, literal(t, 2)));
  ASSERT_TRUE(product);
  EXPECT_EQ(product->lower, value(0));
  EXPECT_EQ(product->upper, top);
  EXPECT_FALSE(product->mayBeUnknown);

  Type signedType = type(64, true);
  Operation *minimum = input(signedType, INT64_MIN, INT64_MIN);
  auto quotient = bounds(
      binary(signedType, Binary::Divide, minimum, literal(signedType, -1)));
  ASSERT_TRUE(quotient);
  EXPECT_EQ(quotient->lower, value(INT64_MIN));
  EXPECT_EQ(quotient->upper, value(INT64_MAX));
}
} // namespace
