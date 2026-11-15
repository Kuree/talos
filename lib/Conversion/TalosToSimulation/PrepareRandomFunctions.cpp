//===- PrepareRandomFunctions.cpp - Frozen constraint functions -----------===//

#include "PrepareRandomFunctions.h"
#include "Detail.h"
#include "PrepareRandomIteration.h"
#include "talos/Runtime/Runtime.h"

#include "mlir/IR/Diagnostics.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallString.h"

#include <functional>
#include <limits>
#include <memory>
#include <string>
#include <tuple>

using namespace mlir;

namespace talos::simlowering {

std::optional<unsigned> getIntegralRandomWidth(Type type) {
  if (auto width = sim::getPackedWidth(type))
    return width;
  if (auto array = dyn_cast<sim::UnpackedArrayType>(type)) {
    auto elementWidth = getIntegralRandomWidth(array.getElementType());
    if (!elementWidth)
      return std::nullopt;
    uint64_t width =
        uint64_t{*elementWidth} * sim::getAggregateNumElements(array);
    if (width <= std::numeric_limits<unsigned>::max())
      return static_cast<unsigned>(width);
  }
  return std::nullopt;
}

std::optional<unsigned> getRandomPropertyWidth(Type type) {
  if (type.isF32())
    return TALOS_RT_REAL32_RANK_BITS;
  if (type.isF64())
    return TALOS_RT_REAL64_RANK_BITS;
  return getIntegralRandomWidth(type);
}

std::optional<FixedRandomArrayLayout> getFixedRandomArrayLayout(Type type) {
  if (!isa<sim::UnpackedArrayType>(type))
    return std::nullopt;
  auto width = getIntegralRandomWidth(type);
  while (auto array = dyn_cast<sim::UnpackedArrayType>(type))
    type = array.getElementType();
  auto elementWidth = sim::getPackedWidth(type);
  if (!width || !elementWidth || *elementWidth == 0 || *width == 0 ||
      *width % *elementWidth != 0)
    return std::nullopt;
  return FixedRandomArrayLayout{*elementWidth, *width / *elementWidth};
}

Type getRandomCyclicStateType(Type type, Type stateType) {
  if (auto array = dyn_cast<sim::UnpackedArrayType>(type))
    return sim::UnpackedArrayType::get(
        type.getContext(),
        getRandomCyclicStateType(array.getElementType(), stateType),
        array.getLeft(), array.getRight());
  return stateType;
}

FailureOr<SmallVector<QualifiedRandomMember>>
collectQualifiedRandomStructMembers(Type type, Location location,
                                    Operation *scope) {
  SmallVector<QualifiedRandomMember> members;
  SmallVector<int64_t> path;
  std::function<LogicalResult(Type)> visit = [&](Type source) -> LogicalResult {
    auto structure = dyn_cast<semantic::SourceAggregateType>(source);
    if (!structure || structure.getIsPacked() || structure.getIsUnion())
      return failure();
    for (auto [ordinal, attribute] : llvm::enumerate(structure.getFields())) {
      auto field = dyn_cast<DictionaryAttr>(attribute);
      auto fieldType = field ? field.getAs<TypeAttr>("type") : TypeAttr{};
      auto mode = field ? field.getAs<IntegerAttr>("rand_mode") : IntegerAttr{};
      if (!fieldType || (field.contains("rand_mode") && !mode) ||
          (mode &&
           (mode.getValue().isNegative() ||
            mode.getValue().getActiveBits() > 2 || mode.getInt() > 2))) {
        emitError(location) << "unpacked random structure has malformed member "
                               "qualifier metadata";
        return failure();
      }
      if (!mode || mode.getInt() == 0)
        continue;
      bool randc = mode.getInt() == 2;
      path.push_back(ordinal);
      auto nested =
          dyn_cast<semantic::SourceAggregateType>(fieldType.getValue());
      if (nested && !nested.getIsPacked()) {
        if (nested.getIsUnion() || randc) {
          emitError(location)
              << (nested.getIsUnion()
                      ? "unpacked unions shall not be random"
                      : "unpacked structures shall not be randc");
          return failure();
        }
        if (failed(visit(fieldType.getValue())))
          return failure();
      } else {
        FailureOr<Type> normalized =
            normalizeSemanticType(fieldType.getValue(), location, scope);
        if (failed(normalized))
          return failure();
        members.push_back({path, fieldType.getValue(), *normalized, randc});
      }
      path.pop_back();
    }
    return success();
  };
  if (failed(visit(type)))
    return failure();
  return members;
}

FailureOr<std::optional<RandomConstraintPath>>
getRandomConstraintPath(Operation *expression,
                        ArrayRef<uint64_t> propertyWidths,
                        llvm::function_ref<std::optional<unsigned>(Operation *)>
                            propertyForExpression) {
  if (auto index = propertyForExpression(expression))
    return std::optional<RandomConstraintPath>(RandomConstraintPath{
        *index, 0, static_cast<unsigned>(propertyWidths[*index]), true,
        sim::has<sim::metadata::RandomFunctionState>(expression)});
  SmallVector<Operation *> children = getChildren(expression);
  if (children.empty())
    return std::optional<RandomConstraintPath>{};
  bool member = isa<semantic::SVMemberAccessExpressionOp>(expression);
  bool element = isa<semantic::SVElementSelectExpressionOp>(expression);
  auto range = dyn_cast<semantic::SVRangeSelectExpressionOp>(expression);
  if (!member && !element && !range)
    return std::optional<RandomConstraintPath>{};
  FailureOr<std::optional<RandomConstraintPath>> base = getRandomConstraintPath(
      children.front(), propertyWidths, propertyForExpression);
  if (failed(base) || !*base)
    return base;
  auto evaluationError = [&]() {
    sim::mark<sim::metadata::RandomEvaluationError>(expression);
    (**base).precise = false;
    return base;
  };
  if (sim::has<sim::metadata::RandomEvaluationError>(children.front()))
    return evaluationError();
  if (!(**base).precise)
    return base;
  FailureOr<Type> resultType = getNormalizedSemanticType(expression);
  std::optional<unsigned> resultWidth =
      succeeded(resultType) ? getIntegralRandomWidth(*resultType)
                            : std::nullopt;
  if (!resultWidth || *resultWidth == 0) {
    emitError(getSemanticLocation(expression))
        << "constraint function ordering path has no fixed integral width";
    return failure();
  }

  uint64_t relativeOffset = 0;
  if (member) {
    auto packedOffset = expression->getAttrOfType<IntegerAttr>("packed_offset");
    if (!packedOffset || packedOffset.getValue().isNegative() ||
        packedOffset.getValue().getActiveBits() > 64) {
      emitError(getSemanticLocation(expression))
          << "constraint function ordering path has malformed packed "
             "member metadata";
      return failure();
    }
    relativeOffset = packedOffset.getValue().getZExtValue();
  } else {
    if (children.size() != (element ? 2u : 3u)) {
      emitError(getSemanticLocation(expression))
          << "constraint function ordering path has malformed selection "
             "metadata";
      return failure();
    }
    auto parseKnownIndex =
        [&](Operation *index) -> FailureOr<std::optional<int64_t>> {
      std::optional<StringRef> spelling = getConstantSpelling(index);
      if (!spelling)
        return std::optional<int64_t>{};
      auto sourceType = index->getAttrOfType<TypeAttr>("semantic_type");
      auto sourceWidth = sourceType
                             ? getSemanticPackedWidth(sourceType.getValue())
                             : std::nullopt;
      unsigned parseWidth =
          sourceWidth ? static_cast<unsigned>(*sourceWidth) : 64;
      FailureOr<ParsedConstant> parsed =
          parseSVInteger(*spelling, parseWidth, getSemanticLocation(index));
      if (failed(parsed))
        return failure();
      bool signedIndex =
          sourceType && isSignedSemanticType(sourceType.getValue());
      if (!parsed->unknown.isZero() ||
          (signedIndex ? !parsed->value.isSignedIntN(64)
                       : parsed->value.getActiveBits() > 63)) {
        sim::mark<sim::metadata::RandomEvaluationError>(expression);
        return std::optional<int64_t>{};
      }
      return std::optional<int64_t>(
          signedIndex ? parsed->value.getSExtValue()
                      : static_cast<int64_t>(parsed->value.getZExtValue()));
    };
    FailureOr<std::optional<int64_t>> first = parseKnownIndex(children[1]);
    if (failed(first))
      return failure();
    if (!*first) {
      (**base).precise = false;
      return base;
    }

    auto sourceTypeAttr =
        children.front()->getAttrOfType<TypeAttr>("semantic_type");
    if (!sourceTypeAttr) {
      emitError(getSemanticLocation(expression))
          << "constraint function ordering selection has no source type";
      return failure();
    }
    // A selection from a runtime-sized container has no fixed bit position;
    // its ordering path covers the whole variable.
    auto layout = getSemanticSelectionLayout(sourceTypeAttr.getValue());
    if (!layout) {
      (**base).precise = false;
      return base;
    }
    int64_t left = layout->left, right = layout->right;
    unsigned elementWidth = layout->elementWidth;
    bool descending = left >= right;
    auto physicalOffset = [&](int64_t index) -> std::optional<uint64_t> {
      APInt selected(65, static_cast<uint64_t>(index), true);
      APInt boundary(65, static_cast<uint64_t>(right), true);
      APInt ordinal = descending ? selected - boundary : boundary - selected;
      if (ordinal.isNegative() || ordinal.getActiveBits() > 64)
        return std::nullopt;
      APInt scaled = ordinal * APInt(65, elementWidth);
      if (scaled.getActiveBits() > 64)
        return std::nullopt;
      return scaled.getZExtValue();
    };
    std::optional<uint64_t> low = physicalOffset(**first);
    if (!low)
      return evaluationError();
    if (element) {
      if (*resultWidth != elementWidth) {
        emitError(getSemanticLocation(expression))
            << "constraint function ordering element selection width is "
               "inconsistent";
        return failure();
      }
    } else if (range) {
      if (range.getSelectionKind() == semantic::SVRangeSelectionKind::Simple) {
        FailureOr<std::optional<int64_t>> second = parseKnownIndex(children[2]);
        if (failed(second))
          return failure();
        if (!*second) {
          (**base).precise = false;
          return base;
        }
        std::optional<uint64_t> other = physicalOffset(**second);
        if (!other)
          return evaluationError();
        uint64_t high = std::max(*low, *other);
        *low = std::min(*low, *other);
        uint64_t selectedWidth = high - *low + elementWidth;
        if (*resultWidth != selectedWidth) {
          emitError(getSemanticLocation(expression))
              << "constraint function ordering range selection width is "
                 "inconsistent";
          return failure();
        }
      } else {
        FailureOr<std::optional<int64_t>> selectedElements =
            parseKnownIndex(children[2]);
        if (failed(selectedElements))
          return failure();
        if (!*selectedElements || **selectedElements <= 0 ||
            static_cast<uint64_t>(**selectedElements) >
                UINT64_MAX / elementWidth ||
            static_cast<uint64_t>(**selectedElements) * elementWidth !=
                *resultWidth) {
          emitError(getSemanticLocation(expression))
              << "constraint function ordering indexed selection width "
                 "is inconsistent";
          return failure();
        }
        bool baseNamesHighBit =
            (descending && range.getSelectionKind() ==
                               semantic::SVRangeSelectionKind::IndexedDown) ||
            (!descending && range.getSelectionKind() ==
                                semantic::SVRangeSelectionKind::IndexedUp);
        if (baseNamesHighBit && *resultWidth > elementWidth) {
          uint64_t adjustment = *resultWidth - elementWidth;
          if (*low < adjustment) {
            return evaluationError();
          }
          *low -= adjustment;
        }
      }
    }
    relativeOffset = *low;
  }
  if (relativeOffset > (*base)->width ||
      *resultWidth > (*base)->width - relativeOffset)
    return evaluationError();
  (*base)->offset += relativeOffset;
  (*base)->width = *resultWidth;
  return base;
}

LogicalResult freezeRandomConstraintPriorityInputs(
    Operation *root, ArrayRef<uint64_t> randomPropertyOffsets,
    uint64_t randomPropertyOffset, Builder &builder,
    llvm::function_ref<
        FailureOr<std::optional<RandomConstraintPath>>(Operation *)>
        getRandomConstraintPath) {
  unsigned orderingWidth =
      static_cast<unsigned>(std::max<uint64_t>(64, randomPropertyOffset));
  uint64_t nextCondition = 0;
  bool invalid = false;
  root->walk<WalkOrder::PreOrder>([&](Operation *expression) {
    bool track = false;
    if (auto condition =
            dyn_cast<semantic::SVConditionalExpressionOp>(expression))
      track = condition.getConditionCount() == 1 &&
              condition.getConditionPatternFlags().size() == 1 &&
              condition.getConditionPatternFlags().front() == 0;
    if (auto binary = dyn_cast<semantic::SVBinaryExpressionOp>(expression))
      track |=
          binary.getOperatorKind() == semantic::SVBinaryOperator::LogicalAnd ||
          binary.getOperatorKind() == semantic::SVBinaryOperator::LogicalOr;
    if (sim::has<sim::metadata::RandomPriorityCondition>(expression) &&
        !track) {
      emitError(getSemanticLocation(expression))
          << "constraint priority condition metadata requires a conditional or "
             "logical expression";
      invalid = true;
    }
    if (track)
      sim::set<sim::metadata::RandomPriorityCondition>(
          expression, builder.getI64IntegerAttr(nextCondition++));
  });
  if (invalid)
    return failure();
  struct Context {
    unsigned parent;
    uint64_t condition;
    bool positive;
    unsigned kind;
  };
  SmallVector<Context> contexts;
  llvm::DenseMap<std::tuple<unsigned, uint64_t, uint8_t, unsigned>, unsigned>
      contextIds;
  auto branchContext = [&](unsigned parent, uint64_t condition, bool positive,
                           unsigned kind = 0) {
    auto [found, inserted] = contextIds.try_emplace(
        {parent, condition, static_cast<uint8_t>(positive), kind},
        contexts.size() + 1);
    if (inserted)
      contexts.push_back({parent, condition, positive, kind});
    return found->second;
  };
  // Function expansion can replace a call by a constant or eliminate an
  // unused argument. Guards still classify the source call as RANDOM when
  // one of its input arguments names an active random variable (18.5.12).
  std::function<FailureOr<APInt>(Operation *)> guardInputs =
      [&](Operation *expression) -> FailureOr<APInt> {
    APInt inputs = APInt::getZero(orderingWidth);
    auto function = dyn_cast<semantic::SVCallExpressionOp>(expression);
    SmallVector<Operation *> children = getChildren(expression);
    if (function && !function.getIsSystemCall()) {
      if (function.getArgumentCount() > children.size())
        return failure();
      children.erase(children.begin(),
                     children.end() - function.getArgumentCount());
    } else {
      FailureOr<std::optional<RandomConstraintPath>> path =
          getRandomConstraintPath(expression);
      if (failed(path))
        return failure();
      if (*path) {
        inputs |= APInt::getLowBitsSet(orderingWidth, (*path)->width)
                      .shl(randomPropertyOffsets[(*path)->property] +
                           (*path)->offset);
        if (isa<semantic::SVElementSelectExpressionOp,
                semantic::SVRangeSelectExpressionOp>(expression))
          children.erase(children.begin());
        else
          children.clear();
      }
    }
    for (Operation *child : children) {
      FailureOr<APInt> childInputs = guardInputs(child);
      if (failed(childInputs))
        return failure();
      inputs |= *childInputs;
    }
    if (function && !function.getIsSystemCall())
      sim::set<sim::metadata::RandomGuardInputs>(
          expression, builder.getIntegerAttr(
                          builder.getIntegerType(orderingWidth), inputs));
    return inputs;
  };
  if (failed(guardInputs(root)))
    return failure();
  struct Edge {
    APInt before, after;
    uint64_t source;
    unsigned beforePath, afterPath;
  };
  SmallVector<Edge> functionOrder;
  uint64_t nextSource = 0;
  bool functionArgumentsPresent = false;
  root->walk([&](Operation *expression) {
    if (!isa<semantic::SVExpressionConstraintOp,
             semantic::SVUniquenessConstraintOp,
             semantic::SVDisableSoftConstraintOp>(expression))
      return;
    uint64_t source = nextSource++;
    struct Path {
      APInt mask;
      bool argument;
      unsigned context;
    };
    SmallVector<Path> paths;
    llvm::DenseMap<std::tuple<APInt, uint8_t, unsigned>, unsigned> pathIds;
    SmallVector<unsigned> arguments, nonArguments;
    auto addPath = [&](APInt mask, bool argument, unsigned context) {
      auto [found, inserted] = pathIds.try_emplace(
          {mask, static_cast<uint8_t>(argument), context}, paths.size());
      if (inserted) {
        (argument ? arguments : nonArguments).push_back(found->second);
        paths.push_back({std::move(mask), argument, context});
      }
    };
    APInt referencedInputs = APInt::getZero(orderingWidth);
    bool impreciseArguments = false;
    bool impreciseNonArguments = false;
    Operation *imprecisePath = nullptr;
    std::function<void(Operation *, bool, unsigned, bool)> collectReferences =
        [&](Operation *nested, bool inFunctionArgument, unsigned context,
            bool sifting) {
          if (auto function = dyn_cast<semantic::SVCallExpressionOp>(nested);
              function && !function.getIsSystemCall()) {
            SmallVector<Operation *> children = getChildren(function);
            uint64_t argumentCount = function.getArgumentCount();
            if (argumentCount > children.size()) {
              emitError(getSemanticLocation(function))
                  << "constraint function has malformed argument metadata";
              invalid = true;
              return;
            }
            for (Operation *argument :
                 ArrayRef(children).take_back(argumentCount))
              collectReferences(argument, true, context, false);
            return;
          }
          if (auto index =
                  sim::get<sim::metadata::RandomPriorityCondition>(nested)) {
            auto children = getChildren(nested);
            uint64_t id = index.getValue().getZExtValue();
            if (isa<semantic::SVConditionalExpressionOp>(nested)) {
              if (children.size() != 3) {
                invalid = true;
                return;
              }
              collectReferences(children[0], inFunctionArgument, context,
                                sifting);
              collectReferences(children[1], inFunctionArgument,
                                branchContext(context, id, true), sifting);
              collectReferences(children[2], inFunctionArgument,
                                branchContext(context, id, false), sifting);
            } else {
              auto binary = dyn_cast<semantic::SVBinaryExpressionOp>(nested);
              if (!binary || (binary.getOperatorKind() !=
                                  semantic::SVBinaryOperator::LogicalAnd &&
                              binary.getOperatorKind() !=
                                  semantic::SVBinaryOperator::LogicalOr)) {
                emitError(getSemanticLocation(nested))
                    << "constraint priority condition metadata has an invalid "
                       "owner";
                invalid = true;
                return;
              }
              bool conjunction = binary.getOperatorKind() ==
                                 semantic::SVBinaryOperator::LogicalAnd;
              unsigned live = sifting
                                  ? branchContext(context, id, conjunction, 1)
                                  : context;
              for (Operation *child : children)
                collectReferences(child, inFunctionArgument, live, sifting);
            }
            return;
          }
          FailureOr<std::optional<RandomConstraintPath>> path =
              getRandomConstraintPath(nested);
          if (failed(path)) {
            invalid = true;
            return;
          }
          if (*path) {
            const RandomConstraintPath &valuePath = **path;
            // Preserve source references even if expression simplification
            // later removes their Boolean dependence. Function priority
            // classifies constraints by the variables they include.
            referencedInputs |=
                APInt::getLowBitsSet(orderingWidth, valuePath.width)
                    .shl(randomPropertyOffsets[valuePath.property] +
                         valuePath.offset);
            if (!valuePath.precise) {
              (inFunctionArgument ? impreciseArguments
                                  : impreciseNonArguments) = true;
              if (!imprecisePath)
                imprecisePath = nested;
            } else {
              uint64_t globalOffset =
                  randomPropertyOffsets[valuePath.property] + valuePath.offset;
              if (globalOffset >= randomPropertyOffset ||
                  valuePath.width > randomPropertyOffset - globalOffset) {
                (inFunctionArgument ? impreciseArguments
                                    : impreciseNonArguments) = true;
                if (!imprecisePath)
                  imprecisePath = nested;
                return;
              }
              APInt mask = APInt::getLowBitsSet(orderingWidth, valuePath.width)
                               .shl(globalOffset);
              addPath(mask, inFunctionArgument, context);
            }
            // A selected path consumes its base. Selection indices remain
            // independent expressions and can themselves name rand state.
            SmallVector<Operation *> children = getChildren(nested);
            if (isa<semantic::SVElementSelectExpressionOp,
                    semantic::SVRangeSelectExpressionOp>(nested))
              for (Operation *index : ArrayRef(children).drop_front())
                collectReferences(index, inFunctionArgument, context, sifting);
            return;
          }
          for (Operation *child : getChildren(nested))
            collectReferences(child, inFunctionArgument, context, sifting);
        };
    if (!isa<semantic::SVDisableSoftConstraintOp>(expression))
      for (Operation *child : getChildren(expression))
        collectReferences(child, false, 0, false);
    unsigned localPathCount = paths.size();
    for (Operation *parent = expression->getParentOp();
         parent && parent != root->getParentOp();
         parent = parent->getParentOp()) {
      if (isa<semantic::SVImplicationConstraintOp,
              semantic::SVConditionalConstraintOp>(parent)) {
        SmallVector<Operation *> parts = getChildren(parent);
        if (!parts.empty())
          collectReferences(parts.front(), false, 0, true);
      }
    }
    sim::set<sim::metadata::RandomPriorityInputs>(
        expression,
        builder.getIntegerAttr(builder.getIntegerType(orderingWidth),
                               referencedInputs));
    APInt argumentInputs = APInt::getZero(orderingWidth);
    for (unsigned argument : arguments)
      argumentInputs |= paths[argument].mask;
    sim::set<sim::metadata::RandomPriorityArguments>(
        expression, builder.getIntegerAttr(
                        builder.getIntegerType(orderingWidth), argumentInputs));
    functionArgumentsPresent |= !argumentInputs.isZero();
    bool hasArgumentPath = impreciseArguments || !arguments.empty();
    bool hasNonArgumentPath = impreciseNonArguments || !nonArguments.empty();
    if (hasArgumentPath && hasNonArgumentPath &&
        (impreciseArguments || impreciseNonArguments)) {
      emitError(getSemanticLocation(imprecisePath))
          << "constraint function implicit ordering requires statically "
             "selected rand paths";
      invalid = true;
      return;
    }
    if (!impreciseArguments && !impreciseNonArguments) {
      SmallVector<Attribute> encodedPaths;
      for (auto [index, path] : llvm::enumerate(paths))
        encodedPaths.push_back(builder.getDictionaryAttr(
            {builder.getNamedAttr(
                 "mask", builder.getIntegerAttr(
                             builder.getIntegerType(orderingWidth), path.mask)),
             builder.getNamedAttr("argument",
                                  builder.getBoolAttr(path.argument)),
             builder.getNamedAttr("local",
                                  builder.getBoolAttr(index < localPathCount)),
             builder.getNamedAttr("context",
                                  builder.getI64IntegerAttr(path.context))}));
      sim::set<sim::metadata::RandomPriorityPaths>(
          expression, builder.getArrayAttr(encodedPaths));
    }
    for (unsigned before : arguments)
      for (unsigned after : nonArguments)
        // Each path inventory is already unique within this source atom.
        if ((paths[before].mask & paths[after].mask).isZero())
          functionOrder.push_back(
              {paths[before].mask, paths[after].mask, source, before, after});
  });
  if (!functionOrder.empty() || functionArgumentsPresent) {
    SmallVector<Attribute> encoded;
    encoded.reserve(functionOrder.size());
    for (auto &[before, after, source, beforePath, afterPath] : functionOrder)
      encoded.push_back(builder.getDictionaryAttr(
          {builder.getNamedAttr(
               "before", builder.getIntegerAttr(
                             builder.getIntegerType(orderingWidth), before)),
           builder.getNamedAttr(
               "after", builder.getIntegerAttr(
                            builder.getIntegerType(orderingWidth), after)),
           builder.getNamedAttr("source", builder.getI64IntegerAttr(source)),
           builder.getNamedAttr("before_path",
                                builder.getI64IntegerAttr(beforePath)),
           builder.getNamedAttr("after_path",
                                builder.getI64IntegerAttr(afterPath))}));
    sim::set<sim::metadata::RandomFunctionOrder>(root,
                                                 builder.getArrayAttr(encoded));
  }
  if (!contexts.empty()) {
    SmallVector<Attribute> encoded;
    for (const Context &context : contexts)
      encoded.push_back(builder.getDictionaryAttr(
          {builder.getNamedAttr("parent",
                                builder.getI64IntegerAttr(context.parent)),
           builder.getNamedAttr("condition",
                                builder.getI64IntegerAttr(context.condition)),
           builder.getNamedAttr("positive",
                                builder.getBoolAttr(context.positive)),
           builder.getNamedAttr("kind",
                                builder.getI64IntegerAttr(context.kind))}));
    sim::set<sim::metadata::RandomPriorityContexts>(
        root, builder.getArrayAttr(encoded));
  }
  return failure(invalid);
}

namespace {

// Convert automatic, side-effect-free statement bodies into value expressions.
// Branch continuations carry distinct local environments, so a return exits
// exactly its source path and an assignment affects only subsequent reads.
// Every executed initializer/RHS remains an evaluation input even when its
// local result is unused: a bad state dereference still contributes ERROR.
/// Constraint function calls expand into the constraint's expression tree,
/// and every use of an argument or computed variable copies its expression.
/// Reuse can therefore grow the tree exponentially; bound the copies so such
/// a function reports an error instead of exhausting compile time.
class ExpansionBudget {
public:
  static constexpr uint64_t limit = uint64_t{1} << 20;

  explicit ExpansionBudget(uint64_t available = limit) : remaining(available) {}

  /// Charge every operation in `root`; false once the budget is exhausted.
  bool spend(Operation *root) {
    uint64_t count = 0;
    root->walk([&](Operation *) { ++count; });
    return spend(count);
  }

  bool spend(uint64_t count) {
    if (exhausted() || count > remaining) {
      remaining = 0;
      return false;
    }
    remaining -= count;
    return true;
  }

  uint64_t available() const { return remaining; }
  bool exhausted() const { return remaining == 0; }

  void diagnose(Location location) {
    if (reported)
      return;
    reported = true;
    emitError(location) << "constraint function calls expand to more than "
                        << limit << " expression nodes";
  }

private:
  uint64_t remaining = limit;
  bool reported = false;
};

class ConstraintFunctionBody {
public:
  ConstraintFunctionBody(semantic::SVSubroutineSymbolOp function,
                         semantic::SVCallExpressionOp call,
                         const llvm::StringMap<Operation *> &symbols,
                         Builder &builder, Block &expressions,
                         ExpansionBudget &budget)
      : function(function), call(call), symbols(symbols), builder(builder),
        expressions(expressions), budget(budget) {}

  FailureOr<Operation *> compile() {
    resultType = call->getAttrOfType<TypeAttr>("semantic_type");
    if (!resultType)
      return failure();
    FailureOr<Type> normalizedResult = normalizeSemanticType(
        resultType.getValue(), getSemanticLocation(call), function);
    if (failed(normalizedResult) || !sim::getPackedWidth(*normalizedResult))
      return failure();
    if (auto reference = function.getReturnVariableSymbol())
      resultVariable = symbols.lookup(reference->getLeafReference());
    Environment environment;
    bool invalid = false;
    function->walk([&](Operation *node) {
      if (auto local = dyn_cast<semantic::SVVariableSymbolOp>(node)) {
        if (function.getThisVariableSymbol() &&
            function.getThisVariableSymbol()->getLeafReference() ==
                local.getSymName())
          return;
        if (node != resultVariable &&
            local.getLifetime() == semantic::SVVariableLifetime::Static)
          return;
        auto type = node->getAttrOfType<TypeAttr>("semantic_type");
        if (!type) {
          invalid = true;
          return;
        }
        FailureOr<Type> normalized = normalizeSemanticType(
            type.getValue(), getSemanticLocation(node), node);
        auto scalar = succeeded(normalized)
                          ? sim::getPackedScalarType(*normalized)
                          : Type{};
        if (!scalar) {
          invalid = true;
          return;
        }
        std::string initialSpelling =
            isa<sim::LogicType>(scalar)
                ? std::to_string(cast<sim::LogicType>(scalar).getWidth()) +
                      "'bx"
                : "0";
        Operation *initial = literal(node, type, initialSpelling);
        if (node == resultVariable &&
            local.getLifetime() == semantic::SVVariableLifetime::Static)
          unassignedStaticResult = initial;
        environment[node] = initial;
        initialValues[node] = initial;
        if (!local.getIsConst().value_or(false))
          writable.insert(node);
      } else if (auto formal =
                     dyn_cast<semantic::SVFormalArgumentSymbolOp>(node)) {
        if (formal.getDirection() == semantic::SVArgumentDirection::In &&
            !formal.getIsConst().value_or(false))
          writable.insert(node);
      }
    });
    if (invalid)
      return failure();
    SmallVector<Operation *> statements;
    for (Operation *child : getChildren(function))
      if (child->getName().getStringRef().starts_with("talos.sv.statement."))
        statements.push_back(child);
    return execute(
        statements, environment,
        [&](Environment &values) -> FailureOr<Operation *> {
          // A two-state automatic return variable has its ordinary default
          // value on fallthrough. Four-state defaults retain X and are never
          // invented as a valid two-state constraint value.
          if (resultVariable)
            return values.lookup(resultVariable) != unassignedStaticResult
                       ? FailureOr<Operation *>(values.lookup(resultVariable))
                       : FailureOr<Operation *>(failure());
          return literal(call, resultType, "0");
        });
  }

private:
  using Environment = llvm::DenseMap<Operation *, Operation *>;
  using Continuation = std::function<FailureOr<Operation *>(Environment &)>;
  struct LoopContext {
    Continuation leave;
    Continuation advance;
  };

  // These source expressions are cloned into both the generated checker and
  // the solver program. Larger or unbounded loops need staged execution rather
  // than an arbitrarily truncated unroll.
  static constexpr uint64_t maxUnrolledIterations = 256;

  Operation *symbol(Operation *node) const {
    auto reference = node->getAttrOfType<SymbolRefAttr>("referenced_symbol");
    return reference ? symbols.lookup(reference.getLeafReference()) : nullptr;
  }

  Operation *make(Operation *source, StringRef name, TypeAttr type,
                  ArrayRef<NamedAttribute> attributes,
                  ArrayRef<Operation *> operands) {
    OperationState state(source->getLoc(), name);
    if (type)
      state.addAttribute("semantic_type", type);
    state.addAttribute("node_id", source->getAttr("node_id"));
    state.addAttribute(sim::metadata::RandomFunctionExpression::getNameStr(),
                       builder.getUnitAttr());
    state.addAttributes(attributes);
    auto *region = state.addRegion();
    region->push_back(new Block());
    for (Operation *operand : operands)
      region->front().push_back(operand->clone());
    Operation *node = Operation::create(state);
    expressions.push_back(node);
    // An exhausted budget fails the whole expansion; the tree built so far
    // is discarded with the expression block.
    budget.spend(node);
    return node;
  }

  Operation *literal(Operation *source, TypeAttr type, StringRef value) {
    return make(
        source, semantic::SVIntegerLiteralOp::getOperationName(), type,
        {builder.getNamedAttr("constant_value", builder.getStringAttr(value))},
        {});
  }

  Operation *convert(Operation *source, TypeAttr type, Operation *value) {
    return make(
        source, semantic::SVConversionExpressionOp::getOperationName(), type,
        {builder.getNamedAttr("is_implicit", builder.getBoolAttr(true))},
        {value});
  }

  Operation *evaluateBefore(Operation *source, Operation *value,
                            Operation *result) {
    return make(source, semantic::SVConversionExpressionOp::getOperationName(),
                resultType,
                {builder.getNamedAttr("is_implicit", builder.getBoolAttr(true)),
                 sim::named<sim::metadata::RandomEvaluationInputs>(
                     builder.getI64IntegerAttr(1))},
                {value, result});
  }

  Operation *branch(Operation *source, Operation *condition, Operation *yes,
                    Operation *no) {
    // Procedural if treats an unknown truth value as false. A conditional
    // expression instead merges its arms, so reduce the full condition to
    // one bit before converting its truth value to a two-state predicate.
    TypeAttr truthType = TypeAttr::get(
        semantic::IntegralType::get(builder.getContext(), 1, false, true, 0, 0,
                                    semantic::SVIntegralFlavor::Logic));
    TypeAttr predicateType = TypeAttr::get(
        semantic::IntegralType::get(builder.getContext(), 1, false, false, 0, 0,
                                    semantic::SVIntegralFlavor::Bit));
    auto logicalNot = [&](Operation *value) {
      return make(
          source, semantic::SVUnaryExpressionOp::getOperationName(), truthType,
          {builder.getNamedAttr("operator_kind",
                                builder.getI32IntegerAttr(static_cast<int32_t>(
                                    semantic::SVUnaryOperator::LogicalNot)))},
          {value});
    };
    Operation *predicate =
        convert(source, predicateType, logicalNot(logicalNot(condition)));
    return make(
        source, semantic::SVConditionalExpressionOp::getOperationName(),
        resultType,
        {sim::named<sim::metadata::RandomFunctionConditional>(
             builder.getUnitAttr()),
         builder.getNamedAttr("condition_count", builder.getI64IntegerAttr(1)),
         builder.getNamedAttr("condition_pattern_flags",
                              builder.getDenseI64ArrayAttr({0})),
         builder.getNamedAttr(
             "is_signed",
             builder.getBoolAttr(isSignedSemanticType(resultType.getValue())))},
        {predicate, yes, no});
  }

  std::optional<uint64_t> width(Operation *source) const {
    auto type = source->getAttrOfType<TypeAttr>("semantic_type");
    return type ? getSemanticBitstreamWidth(type.getValue()) : std::nullopt;
  }

  std::optional<uint64_t> integralWidth(Operation *source) const {
    auto type = source->getAttrOfType<TypeAttr>("semantic_type");
    if (!type)
      return std::nullopt;
    if (isa<semantic::TimeType>(type.getValue()))
      return 64;
    return getSemanticPackedWidth(type.getValue());
  }

  // Match ordinary lowering: only the outer implicit operand conversion is
  // context-determined (11.8.2). Assignment initialization and explicit casts
  // extend by the source sign (11.8.3), including an unsigned destination.
  FailureOr<ParsedConstant> scalarConstant(Operation *source,
                                           bool contextDetermined = false) {
    auto bitWidth = integralWidth(source);
    if (!bitWidth || *bitWidth == 0 ||
        *bitWidth > std::numeric_limits<unsigned>::max())
      return failure();
    if (auto spelling = getConstantSpelling(source)) {
      auto parsed =
          parseSVInteger(*spelling, *bitWidth, getSemanticLocation(source));
      return succeeded(parsed) ? coerceConstant(source, *parsed)
                               : FailureOr<ParsedConstant>(failure());
    }
    if (isa<semantic::SVConversionExpressionOp>(source)) {
      auto operands = getChildren(source);
      if (operands.size() != 1)
        return failure();
      FailureOr<ParsedConstant> value = scalarConstant(operands.front());
      auto type = operands.front()->getAttrOfType<TypeAttr>("semantic_type");
      if (failed(value) || !type)
        return failure();
      bool signExtend = isSignedSemanticType(type.getValue());
      auto implicit = source->getAttrOfType<BoolAttr>("is_implicit");
      if (contextDetermined && (!implicit || implicit.getValue())) {
        auto target = source->getAttrOfType<TypeAttr>("semantic_type");
        signExtend = isSignedSemanticType(target.getValue());
      }
      signExtend |=
          isa<semantic::SVUnbasedUnsizedIntegerLiteralOp>(operands.front());
      value->value = signExtend ? value->value.sextOrTrunc(*bitWidth)
                                : value->value.zextOrTrunc(*bitWidth);
      value->unknown = signExtend ? value->unknown.sextOrTrunc(*bitWidth)
                                  : value->unknown.zextOrTrunc(*bitWidth);
      return coerceConstant(source, *value);
    }
    if (auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(source)) {
      auto operands = getChildren(unary);
      if (operands.size() != 1 ||
          (unary.getOperatorKind() != semantic::SVUnaryOperator::Plus &&
           unary.getOperatorKind() != semantic::SVUnaryOperator::Minus))
        return failure();
      FailureOr<ParsedConstant> value = scalarConstant(operands.front(), true);
      if (failed(value) || value->value.getBitWidth() != *bitWidth)
        return failure();
      if (unary.getOperatorKind() == semantic::SVUnaryOperator::Minus) {
        if (value->unknown.isZero())
          value->value = -value->value;
        else {
          value->value = APInt::getZero(*bitWidth);
          value->unknown = APInt::getAllOnes(*bitWidth);
        }
      }
      return coerceConstant(source, *value);
    }
    return failure();
  }

  FailureOr<ParsedConstant> coerceConstant(Operation *source,
                                           ParsedConstant value) {
    auto type = source->getAttrOfType<TypeAttr>("semantic_type");
    if (!type)
      return failure();
    FailureOr<Type> normalized = normalizeSemanticType(
        type.getValue(), getSemanticLocation(source), function);
    if (failed(normalized))
      return failure();
    Type scalar = sim::getPackedScalarType(*normalized);
    if (!scalar)
      return failure();
    if (isa<IntegerType>(scalar)) {
      value.value &= ~value.unknown;
      value.unknown.clearAllBits();
    }
    return value;
  }

  FailureOr<APInt> constant(Operation *source, bool contextDetermined = false) {
    FailureOr<ParsedConstant> value = scalarConstant(source, contextDetermined);
    if (failed(value) || !value->unknown.isZero())
      return failure();
    return value->value;
  }

  // Each conversion must preserve every source bit. Shift steps additionally
  // require the declared width, so widening a signed value before shifting
  // cannot reintroduce sign bits when it is truncated back into the variable.
  Operation *selectedVariable(Operation *source, uint64_t declaredWidth,
                              bool exactWidth) const {
    while (isa<semantic::SVConversionExpressionOp>(source)) {
      auto operands = getChildren(source);
      auto convertedWidth = integralWidth(source);
      if (operands.size() != 1 || !convertedWidth ||
          (exactWidth ? *convertedWidth != declaredWidth
                      : *convertedWidth < declaredWidth))
        return nullptr;
      source = operands.front();
    }
    return isa<semantic::SVNamedValueExpressionOp>(source) &&
                   integralWidth(source) == declaredWidth
               ? symbol(source)
               : nullptr;
  }

  bool isUpdate(Operation *node) const {
    if (isa<semantic::SVAssignmentExpressionOp>(node))
      return true;
    if (auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(node)) {
      using Unary = semantic::SVUnaryOperator;
      auto kind = unary.getOperatorKind();
      return kind == Unary::Preincrement || kind == Unary::Predecrement ||
             kind == Unary::Postincrement || kind == Unary::Postdecrement;
    }
    return false;
  }

  bool writesVariable(Operation *body, Operation *variable) const {
    bool writes = false;
    body->walk([&](Operation *node) {
      auto targets = getChildren(node);
      if (isUpdate(node) && !targets.empty())
        targets.front()->walk(
            [&](Operation *target) { writes |= symbol(target) == variable; });
      else if (isa<semantic::SVVariableDeclStatementOp>(node))
        writes |= symbol(node) == variable;
    });
    return writes;
  }

  bool writesVariable(ArrayRef<Operation *> body, Operation *variable) const {
    return llvm::any_of(body, [&](Operation *statement) {
      return writesVariable(statement, variable);
    });
  }

  struct CountedLoop {
    Operation *variable;
    // The value before every iteration, including the final false test.
    SmallVector<APInt> values;
  };

  struct CounterStep {
    Operation *variable;
    APInt delta;
  };

  std::optional<CounterStep> countedStep(Operation *step) {
    auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(step);
    bool increment =
        unary &&
        (unary.getOperatorKind() == semantic::SVUnaryOperator::Preincrement ||
         unary.getOperatorKind() == semantic::SVUnaryOperator::Postincrement);
    bool decrement =
        unary &&
        (unary.getOperatorKind() == semantic::SVUnaryOperator::Predecrement ||
         unary.getOperatorKind() == semantic::SVUnaryOperator::Postdecrement);
    auto assignment = dyn_cast<semantic::SVAssignmentExpressionOp>(step);
    auto targets = getChildren(step);
    Operation *variable = targets.size() == (assignment ? 2u : 1u)
                              ? symbol(targets.front())
                              : nullptr;
    if ((!increment && !decrement && !assignment) || !variable ||
        !writable.contains(variable) ||
        !isa<semantic::SVNamedValueExpressionOp>(targets.front()))
      return std::nullopt;
    auto declaredWidth = integralWidth(variable);
    if (!declaredWidth || !*declaredWidth ||
        *declaredWidth > std::numeric_limits<unsigned>::max())
      return std::nullopt;
    APInt delta(*declaredWidth, 1);
    if (!assignment)
      return CounterStep{variable, increment ? delta : -delta};
    if (assignment.getAssignmentKind() !=
            semantic::SVAssignmentKind::Blocking ||
        assignment.getHasTimingControl())
      return std::nullopt;
    auto peel = [&](Operation *source) -> Operation * {
      while (isa<semantic::SVConversionExpressionOp>(source)) {
        auto operands = getChildren(source);
        auto convertedWidth = integralWidth(source);
        if (operands.size() != 1 || !convertedWidth ||
            *convertedWidth < *declaredWidth)
          return nullptr;
        source = operands.front();
      }
      return source;
    };
    Operation *rhs = peel(targets.back());
    auto binary = dyn_cast_if_present<semantic::SVBinaryExpressionOp>(rhs);
    if (!binary || !integralWidth(rhs) || *integralWidth(rhs) < *declaredWidth)
      return std::nullopt;
    using Binary = semantic::SVBinaryOperator;
    bool subtract = binary.getOperatorKind() == Binary::Subtract;
    if (!subtract && binary.getOperatorKind() != Binary::Add)
      return std::nullopt;
    auto operands = getChildren(rhs);
    if (operands.size() != 2 ||
        integralWidth(operands[0]) != integralWidth(rhs) ||
        integralWidth(operands[1]) != integralWidth(rhs))
      return std::nullopt;
    auto counter = [&](Operation *operand) {
      Operation *source = peel(operand);
      return source &&
             (selectedVariable(operand, *declaredWidth, false) == variable ||
              (isa<semantic::SVLValueReferenceExpressionOp>(source) &&
               integralWidth(source) == declaredWidth));
    };
    unsigned counterIndex = counter(operands[0]) ? 0 : 1;
    if (!counter(operands[counterIndex]) || (subtract && counterIndex != 0))
      return std::nullopt;
    FailureOr<APInt> amount = constant(operands[1 - counterIndex], true);
    if (failed(amount))
      return std::nullopt;
    // Every intervening operation preserves the declared low bits. Integral
    // addition/subtraction therefore advances by this modular delta even if
    // the source arithmetic has a wider signed/unsigned context.
    delta = amount->zextOrTrunc(*declaredWidth);
    return CounterStep{variable, subtract ? -delta : delta};
  }

  std::optional<CountedLoop> countedLoop(Operation *condition, Operation *step,
                                         ArrayRef<Operation *> body,
                                         const Environment &environment,
                                         bool postTest = false) {
    auto update = countedStep(step);
    if (!update || writesVariable(body, update->variable))
      return std::nullopt;
    Operation *variable = update->variable;
    Operation *initial = environment.lookup(variable);
    if (!initial || initial == unassignedStaticResult)
      return std::nullopt;
    FailureOr<APInt> value = constant(initial);
    auto declaredWidth = width(variable);
    if (failed(value) || !declaredWidth ||
        value->getBitWidth() != *declaredWidth)
      return std::nullopt;
    auto comparison = dyn_cast<semantic::SVBinaryExpressionOp>(condition);
    auto operands =
        comparison ? getChildren(condition) : SmallVector<Operation *>{};
    if (operands.size() != 2 || width(operands[0]) != width(operands[1]))
      return std::nullopt;
    unsigned variableIndex =
        selectedVariable(operands[0], *declaredWidth, false) == variable ? 0
                                                                         : 1;
    Operation *selected = operands[variableIndex];
    if (selectedVariable(selected, *declaredWidth, false) != variable)
      return std::nullopt;
    FailureOr<APInt> endpoint = constant(operands[1 - variableIndex], true);
    if (failed(endpoint))
      return std::nullopt;
    using Binary = semantic::SVBinaryOperator;
    auto kind = comparison.getOperatorKind();
    if (kind != Binary::LessThan && kind != Binary::LessThanEqual &&
        kind != Binary::GreaterThan && kind != Binary::GreaterThanEqual &&
        kind != Binary::Equality && kind != Binary::Inequality)
      return std::nullopt;
    SmallVector<Operation *> conversions;
    while (isa<semantic::SVConversionExpressionOp>(selected)) {
      conversions.push_back(selected);
      selected = getChildren(selected).front();
    }
    bool signedComparison = llvm::all_of(operands, [](Operation *operand) {
      auto type = operand->getAttrOfType<TypeAttr>("semantic_type");
      return type && isSignedSemanticType(type.getValue());
    });
    CountedLoop result{variable, {}};
    // Simulate only the counter, at its declared modular width. This proves
    // termination without assuming mathematical integers: wrapping inclusive
    // bounds can run forever. No body operations are cloned during the proof.
    for (uint64_t iteration = 0; iteration <= maxUnrolledIterations;
         ++iteration) {
      result.values.push_back(*value);
      // A do...while body executes once before the first test (12.7.5).
      if (postTest && iteration == 0) {
        *value += update->delta;
        continue;
      }
      APInt tested = *value;
      Operation *source = selected;
      for (Operation *conversion : llvm::reverse(conversions)) {
        auto type = source->getAttrOfType<TypeAttr>("semantic_type");
        if (!type)
          return std::nullopt;
        bool signExtend = isSignedSemanticType(type.getValue());
        auto implicit = conversion->getAttrOfType<BoolAttr>("is_implicit");
        // An explicit cast forms a self-determined boundary; inner casts
        // retain their source rules even within an unsigned comparison.
        if (conversion == operands[variableIndex] &&
            (!implicit || implicit.getValue())) {
          auto target = conversion->getAttrOfType<TypeAttr>("semantic_type");
          signExtend = isSignedSemanticType(target.getValue());
        }
        tested = signExtend ? tested.sextOrTrunc(*width(conversion))
                            : tested.zextOrTrunc(*width(conversion));
        source = conversion;
      }
      const APInt &lhs = variableIndex == 0 ? tested : *endpoint;
      const APInt &rhs = variableIndex == 0 ? *endpoint : tested;
      bool less = signedComparison ? lhs.slt(rhs) : lhs.ult(rhs);
      bool greater = signedComparison ? lhs.sgt(rhs) : lhs.ugt(rhs);
      bool active = kind == Binary::LessThan           ? less
                    : kind == Binary::LessThanEqual    ? !greater
                    : kind == Binary::GreaterThan      ? greater
                    : kind == Binary::GreaterThanEqual ? !less
                    : kind == Binary::Equality         ? lhs == rhs
                                                       : lhs != rhs;
      if (!active)
        return result;
      *value += update->delta;
    }
    return std::nullopt;
  }

  std::optional<uint64_t> shiftLoopBound(Operation *condition, Operation *step,
                                         ArrayRef<Operation *> body) {
    auto assignment = dyn_cast<semantic::SVAssignmentExpressionOp>(step);
    auto operands = assignment ? getChildren(step) : SmallVector<Operation *>{};
    Operation *variable =
        operands.size() == 2 ? symbol(operands.front()) : nullptr;
    if (!assignment ||
        assignment.getAssignmentKind() !=
            semantic::SVAssignmentKind::Blocking ||
        assignment.getHasTimingControl() || !variable ||
        !writable.contains(variable) ||
        !isa<semantic::SVNamedValueExpressionOp>(operands.front()))
      return std::nullopt;
    uint64_t declaredWidth = width(variable).value_or(0);
    if (declaredWidth == 0)
      return std::nullopt;
    Operation *rhs = operands.back();
    while (isa<semantic::SVConversionExpressionOp>(rhs)) {
      auto inputs = getChildren(rhs);
      if (inputs.size() != 1 || width(rhs) != declaredWidth)
        return std::nullopt;
      rhs = inputs.front();
    }
    auto shift = dyn_cast<semantic::SVBinaryExpressionOp>(rhs);
    auto inputs = shift ? getChildren(shift) : SmallVector<Operation *>{};
    if (!shift ||
        shift.getOperatorKind() !=
            semantic::SVBinaryOperator::LogicalShiftRight ||
        inputs.size() != 2 || width(shift) != declaredWidth ||
        (selectedVariable(inputs.front(), declaredWidth, true) != variable &&
         !(isa<semantic::SVLValueReferenceExpressionOp>(inputs.front()) &&
           width(inputs.front()) == declaredWidth)))
      return std::nullopt;
    FailureOr<APInt> amount = constant(inputs.back());
    auto amountType = inputs.back()->getAttrOfType<TypeAttr>("semantic_type");
    if (failed(amount) || !amountType || amount->isZero() ||
        (isSignedSemanticType(amountType.getValue()) && amount->isNegative()) ||
        amount->getActiveBits() > 64)
      return std::nullopt;
    auto comparison = dyn_cast<semantic::SVBinaryExpressionOp>(condition);
    auto predicates =
        comparison ? getChildren(comparison) : SmallVector<Operation *>{};
    bool nonzeroTest =
        selectedVariable(condition, declaredWidth, false) == variable;
    if (comparison &&
        comparison.getOperatorKind() ==
            semantic::SVBinaryOperator::Inequality &&
        predicates.size() == 2)
      for (unsigned index = 0; index != 2; ++index) {
        FailureOr<APInt> zero = constant(predicates[1 - index]);
        nonzeroTest |= selectedVariable(predicates[index], declaredWidth,
                                        false) == variable &&
                       succeeded(zero) && zero->isZero();
      }
    if (!nonzeroTest)
      return std::nullopt;
    if (writesVariable(body, variable))
      return std::nullopt;
    uint64_t shiftBits = amount->getZExtValue();
    uint64_t bound = declaredWidth / shiftBits +
                     static_cast<uint64_t>(declaredWidth % shiftBits != 0);
    return bound <= maxUnrolledIterations ? std::optional<uint64_t>(bound)
                                          : std::nullopt;
  }

  // Expose only unconditional statements in the loop's sequential body. An
  // update in a branch or a nested loop cannot establish progress for every
  // iteration of the containing while loop.
  void loopStatements(Operation *body, SmallVectorImpl<Operation *> &result) {
    if (isa<semantic::SVStatementListOp>(body) ||
        (isa<semantic::SVBlockStatementOp>(body) &&
         cast<semantic::SVBlockStatementOp>(body).getBlockKind() ==
             semantic::SVStatementBlockKind::Sequential)) {
      for (Operation *child : getChildren(body))
        loopStatements(child, result);
      return;
    }
    result.push_back(body);
  }

  bool continuesLoop(Operation *statement) const {
    bool found = false;
    statement->walk<WalkOrder::PreOrder>([&](Operation *node) {
      if (isa<semantic::SVForLoopStatementOp, semantic::SVWhileLoopStatementOp,
              semantic::SVDoWhileLoopStatementOp,
              semantic::SVRepeatLoopStatementOp,
              semantic::SVForeachLoopStatementOp,
              semantic::SVForeverLoopStatementOp>(node))
        return WalkResult::skip();
      found |= isa<semantic::SVContinueStatementOp>(node);
      return WalkResult::advance();
    });
    return found;
  }

  SmallVector<Operation *> expressionStatements(ArrayRef<Operation *> values) {
    SmallVector<Operation *> statements;
    for (Operation *value : values)
      statements.push_back(
          make(value, semantic::SVExpressionStatementOp::getOperationName(), {},
               {}, {value}));
    return statements;
  }

  FailureOr<Operation *> expression(Operation *source, Environment &environment,
                                    Operation *assignmentValue = nullptr) {
    if (isa<semantic::SVAssignmentExpressionOp>(source))
      return failure();
    if (auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(source))
      if (unary.getOperatorKind() == semantic::SVUnaryOperator::Preincrement ||
          unary.getOperatorKind() == semantic::SVUnaryOperator::Predecrement ||
          unary.getOperatorKind() == semantic::SVUnaryOperator::Postincrement ||
          unary.getOperatorKind() == semantic::SVUnaryOperator::Postdecrement)
        return failure();
    if (isa<semantic::SVLValueReferenceExpressionOp>(source))
      return assignmentValue ? FailureOr<Operation *>(assignmentValue)
                             : FailureOr<Operation *>(failure());
    if (Operation *declaration = symbol(source))
      if (Operation *value = environment.lookup(declaration))
        return value != unassignedStaticResult
                   ? FailureOr<Operation *>(value)
                   : FailureOr<Operation *>(failure());
    Operation *cloned = source->cloneWithoutRegions();
    sim::mark<sim::metadata::RandomFunctionExpression>(cloned);
    for (auto [sourceRegion, clonedRegion] :
         llvm::zip_equal(source->getRegions(), cloned->getRegions())) {
      for (Block &block : sourceRegion) {
        auto *target = new Block();
        clonedRegion.push_back(target);
        for (Operation &child : block) {
          FailureOr<Operation *> value =
              expression(&child, environment, assignmentValue);
          if (failed(value)) {
            cloned->destroy();
            return failure();
          }
          target->push_back((*value)->clone());
        }
      }
    }
    expressions.push_back(cloned);
    if (!budget.spend(cloned))
      return failure();
    return cloned;
  }

  FailureOr<Operation *>
  executeBoundedLoop(Operation *statement, Operation *condition,
                     ArrayRef<Operation *> body, ArrayRef<Operation *> steps,
                     uint64_t bound, const std::optional<CountedLoop> &counted,
                     bool postTest, Environment &environment,
                     const Continuation &next, LoopContext *enclosingLoop) {
    std::function<FailureOr<Operation *>(uint64_t, Environment &)> iterate;
    iterate = [&](uint64_t remaining,
                  Environment &values) -> FailureOr<Operation *> {
      if (counted) {
        const APInt &counter = counted->values[bound - remaining];
        SmallString<32> digits;
        counter.toString(digits, 16, false);
        values[counted->variable] = literal(
            statement,
            counted->variable->getAttrOfType<TypeAttr>("semantic_type"),
            std::to_string(counter.getBitWidth()) + "'h" + digits.str().str());
      }
      // Both proofs establish that this final test is false. It reads only a
      // local counter and constants, so omitting it cannot suppress an error
      // or a side effect.
      if (remaining == 0)
        return next(values);
      if (remainingUnrollBudget == 0)
        return failure();
      --remainingUnrollBudget;
      Continuation advance = [&](Environment &updated) {
        return execute(
            steps, updated,
            [&](Environment &stepped) {
              return iterate(remaining - 1, stepped);
            },
            enclosingLoop);
      };
      LoopContext current{next, advance};
      // Counted tests are known. A do...while also enters its first body
      // unconditionally; every subsequent entry checks the preceding body's
      // post-test before executing another iteration.
      if (counted || (postTest && remaining == bound))
        return execute(body, values, advance, &current);
      FailureOr<Operation *> predicate = expression(condition, values);
      if (failed(predicate))
        return failure();
      Environment trueValues = values;
      Environment falseValues = values;
      FailureOr<Operation *> yes = execute(body, trueValues, advance, &current);
      FailureOr<Operation *> no = next(falseValues);
      return succeeded(yes) && succeeded(no)
                 ? FailureOr<Operation *>(
                       branch(statement, *predicate, *yes, *no))
                 : FailureOr<Operation *>(failure());
    };
    return iterate(bound, environment);
  }

  FailureOr<Operation *> execute(ArrayRef<Operation *> statements,
                                 Environment &environment,
                                 const Continuation &continuation,
                                 LoopContext *loop = nullptr) {
    if (statements.empty())
      return continuation(environment);
    Operation *statement = statements.front();
    Continuation next = [&](Environment &values) {
      return execute(statements.drop_front(), values, continuation, loop);
    };
    if (isa<semantic::SVStatementListOp, semantic::SVBlockStatementOp>(
            statement)) {
      if (auto block = dyn_cast<semantic::SVBlockStatementOp>(statement))
        if (block.getBlockKind() != semantic::SVStatementBlockKind::Sequential)
          return failure();
      auto children = getChildren(statement);
      return execute(children, environment, next, loop);
    }
    if (isa<semantic::SVEmptyStatementOp>(statement) ||
        statement->getName().getStringRef().starts_with("talos.sv.symbol."))
      return next(environment);
    if (isa<semantic::SVBreakStatementOp>(statement))
      return loop ? loop->leave(environment)
                  : FailureOr<Operation *>(failure());
    if (isa<semantic::SVContinueStatementOp>(statement))
      return loop ? loop->advance(environment)
                  : FailureOr<Operation *>(failure());
    if (auto declaration =
            dyn_cast<semantic::SVVariableDeclStatementOp>(statement)) {
      Operation *variable = symbol(statement);
      if (!variable)
        return failure();
      if (!environment.contains(variable))
        return next(environment);
      environment[variable] = initialValues.lookup(variable);
      auto initializers = getChildren(statement);
      if (initializers.empty())
        initializers = getChildren(variable);
      if (initializers.empty())
        return next(environment);
      if (initializers.size() != 1)
        return failure();
      FailureOr<Operation *> value =
          expression(initializers.front(), environment);
      if (failed(value))
        return failure();
      Operation *converted =
          convert(statement, variable->getAttrOfType<TypeAttr>("semantic_type"),
                  *value);
      environment[variable] = converted;
      FailureOr<Operation *> result = next(environment);
      return succeeded(result) ? FailureOr<Operation *>(evaluateBefore(
                                     statement, converted, *result))
                               : result;
    }
    if (isa<semantic::SVRepeatLoopStatementOp>(statement)) {
      auto children = getChildren(statement);
      if (children.size() != 2)
        return failure();
      FailureOr<ParsedConstant> count = scalarConstant(children.front());
      auto type = children.front()->getAttrOfType<TypeAttr>("semantic_type");
      if (failed(count) || !type)
        return failure();
      uint64_t iterations = 0;
      // IEEE 1800-2023 12.7.2 treats negative, X and Z counts as zero. Apply
      // intervening casts first; a two-state cast may leave known positive
      // bits after discarding its unknown bits.
      if (count->unknown.isZero() && (!isSignedSemanticType(type.getValue()) ||
                                      !count->value.isNegative())) {
        if (count->value.getActiveBits() > 64 ||
            count->value.getZExtValue() > maxUnrolledIterations)
          return failure();
        iterations = count->value.getZExtValue();
      }
      std::function<FailureOr<Operation *>(uint64_t, Environment &)> iterate;
      iterate = [&](uint64_t remaining,
                    Environment &values) -> FailureOr<Operation *> {
        if (remaining == 0)
          return next(values);
        if (remainingUnrollBudget == 0)
          return failure();
        --remainingUnrollBudget;
        Continuation advance = [&](Environment &updated) {
          return iterate(remaining - 1, updated);
        };
        LoopContext current{next, advance};
        return execute({children[1]}, values, advance, &current);
      };
      return iterate(iterations, environment);
    }
    if (auto forLoop = dyn_cast<semantic::SVForLoopStatementOp>(statement)) {
      auto children = getChildren(statement);
      uint64_t initializerCount = forLoop.getInitializerCount();
      if (!forLoop.getHasCondition() || forLoop.getStepCount() != 1 ||
          initializerCount > children.size() ||
          children.size() - initializerCount != 3)
        return failure();
      Operation *condition = children[initializerCount];
      Operation *step = children[initializerCount + 1];
      Operation *body = children.back();
      std::optional<uint64_t> bound = shiftLoopBound(condition, step, {body});
      SmallVector<Operation *> initializers =
          expressionStatements(ArrayRef(children).take_front(initializerCount));
      SmallVector<Operation *> steps = expressionStatements({step});
      return execute(
          initializers, environment,
          [&](Environment &initialized) {
            std::optional<CountedLoop> counted;
            if (!bound) {
              counted = countedLoop(condition, step, {body}, initialized);
              if (!counted)
                return FailureOr<Operation *>(failure());
              bound = counted->values.size() - 1;
            }
            return executeBoundedLoop(statement, condition, {body}, steps,
                                      *bound, counted, false, initialized, next,
                                      loop);
          },
          loop);
    }
    if (isa<semantic::SVWhileLoopStatementOp,
            semantic::SVDoWhileLoopStatementOp>(statement)) {
      auto children = getChildren(statement);
      if (children.size() != 2)
        return failure();
      Operation *condition = children.front();
      SmallVector<Operation *> body;
      loopStatements(children.back(), body);
      bool postTest = isa<semantic::SVDoWhileLoopStatementOp>(statement);

      // Each admitted condition selects at most two possible counters, one
      // through each comparison operand. Filter candidates before scanning
      // the body: unrelated updates must not introduce quadratic proof work.
      llvm::SmallPtrSet<Operation *, 2> counters;
      auto collectCounter = [&](Operation *operand) {
        while (isa<semantic::SVConversionExpressionOp>(operand)) {
          auto inputs = getChildren(operand);
          if (inputs.size() != 1)
            return;
          operand = inputs.front();
        }
        if (isa<semantic::SVNamedValueExpressionOp>(operand))
          if (Operation *variable = symbol(operand))
            if (writable.contains(variable))
              counters.insert(variable);
      };
      if (isa<semantic::SVBinaryExpressionOp>(condition)) {
        auto operands = getChildren(condition);
        if (operands.size() != 2)
          return failure();
        for (Operation *operand : operands)
          collectCounter(operand);
      } else {
        collectCounter(condition);
      }
      struct Candidate {
        Operation *variable;
        Operation *step;
        size_t index;
      };
      SmallVector<Candidate, 2> candidates;
      bool prefixContinues = false;
      for (auto [index, candidate] : llvm::enumerate(body)) {
        bool skipsUpdate = prefixContinues;
        prefixContinues |= continuesLoop(candidate);
        auto operands = getChildren(candidate);
        if (!isa<semantic::SVExpressionStatementOp>(candidate) ||
            operands.size() != 1 || !isUpdate(operands.front()))
          continue;
        Operation *step = operands.front();
        auto targets = getChildren(step);
        Operation *variable =
            !targets.empty() &&
                    isa<semantic::SVNamedValueExpressionOp>(targets.front())
                ? symbol(targets.front())
                : nullptr;
        if (!counters.contains(variable))
          continue;
        auto previous = llvm::find_if(candidates, [&](const Candidate &entry) {
          return entry.variable == variable;
        });
        if (previous != candidates.end()) {
          previous->step = nullptr;
          continue;
        }
        // A continue before the update can skip progress altogether. Nested
        // loops own their continues; a break or return exits this loop and
        // therefore needs no progress proof.
        candidates.push_back({variable, skipsUpdate ? nullptr : step, index});
      }
      for (const Candidate &candidate : candidates) {
        if (!candidate.step)
          continue;
        SmallVector<Operation *> otherBody(body);
        otherBody.erase(otherBody.begin() + candidate.index);
        Operation *step = candidate.step;
        std::optional<uint64_t> bound =
            shiftLoopBound(condition, step, otherBody);
        std::optional<CountedLoop> counted;
        if (!bound) {
          counted =
              countedLoop(condition, step, otherBody, environment, postTest);
          if (!counted)
            continue;
          bound = counted->values.size() - 1;
        }
        return executeBoundedLoop(statement, condition, body, {}, *bound,
                                  counted, postTest, environment, next, loop);
      }
      return failure();
    }
    if (auto ret = dyn_cast<semantic::SVReturnStatementOp>(statement)) {
      auto values = getChildren(ret);
      if (values.empty())
        return resultVariable && environment.lookup(resultVariable) !=
                                     unassignedStaticResult
                   ? FailureOr<Operation *>(environment.lookup(resultVariable))
                   : FailureOr<Operation *>(failure());
      if (values.size() != 1)
        return failure();
      FailureOr<Operation *> value = expression(values.front(), environment);
      return succeeded(value) ? FailureOr<Operation *>(
                                    convert(statement, resultType, *value))
                              : value;
    }
    if (auto caseStatement = dyn_cast<semantic::SVCaseStatementOp>(statement)) {
      // 12.5 evaluates the selector first, then the labels in source order,
      // and executes only the first matching item. Wildcard comparisons
      // compile into exact value/X/Z planes under 12.5.1. Case-inside uses
      // RHS-only wildcard membership under 12.5.4; an X result does not match.
      // Pattern matching and qualifier reports need their own implementation.
      if (caseStatement.getCheckKind() != semantic::SVUniquePriorityCheck::None)
        return failure();
      bool inside =
          caseStatement.getConditionKind() == semantic::SVCaseCondition::Inside;
      auto children = getChildren(statement);
      auto labelCounts = caseStatement.getItemLabelCounts();
      uint64_t itemCount = caseStatement.getItemCount();
      uint64_t statementCount =
          itemCount + static_cast<unsigned>(caseStatement.getHasDefault());
      if (children.empty() || itemCount != labelCounts.size() ||
          statementCount > children.size() - 1)
        return failure();
      uint64_t totalLabels = 0;
      for (int64_t count : labelCounts) {
        if (count <= 0 ||
            static_cast<uint64_t>(count) > children.size() - totalLabels)
          return failure();
        totalLabels += count;
      }
      if (children.size() - 1 - statementCount != totalLabels)
        return failure();
      auto comparisons = ArrayRef(children).take_front(1 + totalLabels);
      auto bodies = ArrayRef(children).take_back(statementCount);
      SmallVector<Operation *> comparisonOperands;
      for (Operation *operand : comparisons) {
        if (auto range =
                dyn_cast<semantic::SVValueRangeExpressionOp>(operand)) {
          auto bounds = getChildren(operand);
          if (!inside ||
              range.getRangeKind() != semantic::SVValueRangeKind::Simple ||
              bounds.size() != 2 ||
              (isUnboundedEndpoint(bounds[0]) &&
               isUnboundedEndpoint(bounds[1])))
            return failure();
          for (Operation *bound : bounds)
            if (!isUnboundedEndpoint(bound))
              comparisonOperands.push_back(bound);
        } else {
          comparisonOperands.push_back(operand);
        }
      }
      uint64_t comparisonWidth = 0;
      bool comparisonSigned = true;
      bool comparisonFourState = false;
      auto membershipElementType = [&](Type type) {
        while (inside) {
          if (auto array = dyn_cast<semantic::RangedUnpackedArrayType>(type))
            type = array.getElementType();
          else if (auto array = dyn_cast<semantic::UnpackedArrayType>(type))
            type = array.getElementType();
          else
            break;
        }
        return type;
      };
      for (Operation *operand : comparisonOperands) {
        auto type = operand->getAttrOfType<TypeAttr>("semantic_type");
        Type elementType =
            type ? membershipElementType(type.getValue()) : Type{};
        FailureOr<Type> normalized =
            type ? normalizeSemanticType(elementType,
                                         getSemanticLocation(operand), function)
                 : FailureOr<Type>(failure());
        Type scalar = succeeded(normalized)
                          ? sim::getPackedScalarType(*normalized)
                          : Type{};
        auto operandWidth = scalar ? sim::getPackedWidth(scalar) : std::nullopt;
        if (!operandWidth || *operandWidth == 0)
          return failure();
        comparisonWidth = std::max(comparisonWidth, uint64_t(*operandWidth));
        comparisonSigned &= isSignedSemanticType(elementType);
        comparisonFourState |= isa<sim::LogicType>(scalar);
      }
      auto integralType = [&](uint64_t bitWidth, bool fourState) {
        return TypeAttr::get(semantic::IntegralType::get(
            builder.getContext(), bitWidth, comparisonSigned, fourState,
            bitWidth - 1, 0,
            fourState ? semantic::SVIntegralFlavor::Logic
                      : semantic::SVIntegralFlavor::Bit));
      };
      TypeAttr comparisonType =
          integralType(comparisonWidth, comparisonFourState);
      auto contextValue = [&](Operation *source) -> FailureOr<Operation *> {
        // Imported implicit conversions express the common case context.
        // Reapply that context here: a narrow signed operand must zero-extend
        // when any case operand is unsigned (12.5), while explicit casts
        // retain their self-determined result.
        if (auto conversion =
                dyn_cast<semantic::SVConversionExpressionOp>(source)) {
          auto implicit = source->getAttrOfType<BoolAttr>("is_implicit");
          auto inputs = getChildren(source);
          if ((!implicit || implicit.getValue()) && inputs.size() == 1)
            source = inputs.front();
        }
        FailureOr<Operation *> value = expression(source, environment);
        auto bitWidth = width(source);
        auto type = source->getAttrOfType<TypeAttr>("semantic_type");
        FailureOr<Type> normalized =
            type ? normalizeSemanticType(type.getValue(),
                                         getSemanticLocation(source), function)
                 : FailureOr<Type>(failure());
        if (failed(value) || !bitWidth || failed(normalized))
          return failure();
        if (isa<semantic::SVUnbasedUnsizedIntegerLiteralOp>(source)) {
          // '0/'1/'x/'z fill the complete case context, including an
          // unsigned context, instead of behaving like an ordinary 1-bit
          // based literal (5.7.1).
          FailureOr<ParsedConstant> digit = scalarConstant(source);
          if (failed(digit))
            return failure();
          char fill = digit->unknown.isZero()
                          ? (digit->value.isZero() ? '0' : '1')
                          : (digit->value.isZero() ? 'x' : 'z');
          return literal(source, comparisonType,
                         std::to_string(comparisonWidth) + "'b" +
                             std::string(comparisonWidth, fill));
        }
        TypeAttr sourceContextType = integralType(
            *bitWidth,
            isa<sim::LogicType>(sim::getPackedScalarType(*normalized)));
        // An unsized based literal with an unknown high bit also fills
        // through a wider context regardless of common signedness (5.7.1).
        if (auto fillWidth = getUnsizedUnknownFillWidth(source);
            fillWidth && comparisonWidth > *fillWidth)
          sourceContextType = TypeAttr::get(semantic::IntegralType::get(
              builder.getContext(), *bitWidth, true, true, *bitWidth - 1, 0,
              semantic::SVIntegralFlavor::Logic));
        Operation *typed = convert(source, sourceContextType, *value);
        return convert(source, comparisonType, typed);
      };
      FailureOr<Operation *> selector = contextValue(comparisons.front());
      if (failed(selector))
        return failure();
      SmallVector<Operation *> labels;
      for (Operation *label : comparisons.drop_front()) {
        if (auto range = dyn_cast<semantic::SVValueRangeExpressionOp>(label)) {
          auto bounds = getChildren(label);
          SmallVector<Operation *> endpoints;
          for (auto [index, bound] : llvm::enumerate(bounds)) {
            if (isUnboundedEndpoint(bound)) {
              // 11.4.13: '$' denotes the minimum/maximum of the selector's
              // common case type. It contributes no evaluation input.
              std::string bits(comparisonWidth, index == 0 ? '0' : '1');
              if (comparisonSigned)
                bits.front() = index == 0 ? '1' : '0';
              endpoints.push_back(
                  literal(bound, comparisonType,
                          std::to_string(comparisonWidth) + "'b" + bits));
              continue;
            }
            FailureOr<Operation *> value = contextValue(bound);
            if (failed(value))
              return failure();
            endpoints.push_back(*value);
          }
          labels.push_back(make(
              label, semantic::SVValueRangeExpressionOp::getOperationName(),
              label->getAttrOfType<TypeAttr>("semantic_type"),
              {builder.getNamedAttr("range_kind",
                                    label->getAttr("range_kind"))},
              endpoints));
          continue;
        }
        auto labelType = label->getAttrOfType<TypeAttr>("semantic_type");
        // 11.4.13 traverses unpacked labels to singular members. The array
        // itself retains its element type; each member is compared in the
        // selector's common context after fixed-array expansion.
        bool arrayLabel =
            labelType &&
            membershipElementType(labelType.getValue()) != labelType.getValue();
        FailureOr<Operation *> value =
            arrayLabel ? expression(label, environment) : contextValue(label);
        if (failed(value))
          return failure();
        labels.push_back(*value);
      }
      TypeAttr predicateType = TypeAttr::get(
          semantic::IntegralType::get(builder.getContext(), 1, false, false, 0,
                                      0, semantic::SVIntegralFlavor::Bit));
      TypeAttr membershipType = TypeAttr::get(
          semantic::IntegralType::get(builder.getContext(), 1, false, true, 0,
                                      0, semantic::SVIntegralFlavor::Logic));
      Environment unmatchedValues = environment;
      FailureOr<Operation *> unmatched =
          caseStatement.getHasDefault()
              ? execute({bodies.back()}, unmatchedValues, next, loop)
              : next(unmatchedValues);
      if (failed(unmatched))
        return failure();
      Operation *selection = *unmatched;
      uint64_t labelIndex = totalLabels;
      for (uint64_t item = itemCount; item != 0;) {
        --item;
        Environment values = environment;
        FailureOr<Operation *> result =
            execute({bodies[item]}, values, next, loop);
        if (failed(result))
          return failure();
        // Nested conditionals preserve label short-circuiting, including
        // evaluation errors in labels after an earlier match.
        for (int64_t count = labelCounts[item]; count != 0; --count) {
          --labelIndex;
          Operation *matches =
              inside
                  ? make(statement,
                         semantic::SVInsideExpressionOp::getOperationName(),
                         membershipType,
                         {builder.getNamedAttr("item_count",
                                               builder.getI64IntegerAttr(1))},
                         {*selector, labels[labelIndex]})
                  : make(
                        statement,
                        semantic::SVBinaryExpressionOp::getOperationName(),
                        predicateType,
                        {builder.getNamedAttr(
                             "operator_kind",
                             builder.getI32IntegerAttr(static_cast<int32_t>(
                                 semantic::SVBinaryOperator::CaseEquality))),
                         sim::named<sim::metadata::RandomFunctionCaseCondition>(
                             builder.getI32IntegerAttr(static_cast<int32_t>(
                                 caseStatement.getConditionKind())))},
                        {*selector, labels[labelIndex]});
          selection = branch(statement, matches, *result, selection);
        }
      }
      return evaluateBefore(statement, *selector, selection);
    }
    if (auto conditional =
            dyn_cast<semantic::SVConditionalStatementOp>(statement)) {
      auto children = getChildren(statement);
      if (conditional.getConditionCount() != 1 ||
          conditional.getConditionPatternFlags().size() != 1 ||
          conditional.getConditionPatternFlags().front() != 0 ||
          children.size() !=
              2u + static_cast<unsigned>(conditional.getHasElse()))
        return failure();
      FailureOr<Operation *> condition =
          expression(children.front(), environment);
      if (failed(condition))
        return failure();
      Environment trueValues = environment;
      Environment falseValues = environment;
      FailureOr<Operation *> yes =
          execute({children[1]}, trueValues, next, loop);
      FailureOr<Operation *> no =
          conditional.getHasElse()
              ? execute({children[2]}, falseValues, next, loop)
              : next(falseValues);
      if (failed(yes) || failed(no))
        return failure();
      return branch(statement, *condition, *yes, *no);
    }
    if (auto expr = dyn_cast<semantic::SVExpressionStatementOp>(statement)) {
      auto children = getChildren(expr);
      auto assignment =
          children.size() == 1
              ? dyn_cast<semantic::SVAssignmentExpressionOp>(children.front())
              : semantic::SVAssignmentExpressionOp{};
      auto unary =
          children.size() == 1
              ? dyn_cast<semantic::SVUnaryExpressionOp>(children.front())
              : semantic::SVUnaryExpressionOp{};
      bool increment =
          unary &&
          (unary.getOperatorKind() == semantic::SVUnaryOperator::Preincrement ||
           unary.getOperatorKind() == semantic::SVUnaryOperator::Postincrement);
      bool decrement =
          unary &&
          (unary.getOperatorKind() == semantic::SVUnaryOperator::Predecrement ||
           unary.getOperatorKind() == semantic::SVUnaryOperator::Postdecrement);
      auto operands = assignment ? getChildren(assignment)
                      : unary    ? getChildren(unary)
                                 : SmallVector<Operation *>{};
      Operation *variable = operands.size() == (assignment ? 2u : 1u)
                                ? symbol(operands.front())
                                : nullptr;
      if ((!assignment && !increment && !decrement) ||
          (assignment && (assignment.getHasTimingControl() ||
                          assignment.getAssignmentKind() !=
                              semantic::SVAssignmentKind::Blocking)) ||
          !variable || !writable.contains(variable) ||
          !isa<semantic::SVNamedValueExpressionOp>(operands.front()))
        return failure();
      Operation *oldValue = environment.lookup(variable);
      if (unassignedStaticResult && oldValue == unassignedStaticResult)
        oldValue = nullptr;
      else if (!oldValue)
        oldValue = operands.front();
      auto type = variable->getAttrOfType<TypeAttr>("semantic_type");
      if (!assignment && !oldValue)
        return failure();
      FailureOr<Operation *> value =
          assignment
              ? expression(operands.back(), environment, oldValue)
              : FailureOr<Operation *>(make(
                    unary, semantic::SVBinaryExpressionOp::getOperationName(),
                    type,
                    {builder.getNamedAttr(
                        "operator_kind",
                        builder.getI32IntegerAttr(static_cast<int32_t>(
                            increment
                                ? semantic::SVBinaryOperator::Add
                                : semantic::SVBinaryOperator::Subtract)))},
                    {oldValue, literal(unary, type, "1")}));
      if (failed(value))
        return failure();
      Operation *converted =
          convert(statement, variable->getAttrOfType<TypeAttr>("semantic_type"),
                  *value);
      environment[variable] = converted;
      FailureOr<Operation *> result = next(environment);
      return succeeded(result) ? FailureOr<Operation *>(evaluateBefore(
                                     statement, converted, *result))
                               : result;
    }
    return failure();
  }

  semantic::SVSubroutineSymbolOp function;
  semantic::SVCallExpressionOp call;
  const llvm::StringMap<Operation *> &symbols;
  Builder &builder;
  Block &expressions;
  TypeAttr resultType;
  Operation *resultVariable = nullptr;
  Operation *unassignedStaticResult = nullptr;
  Environment initialValues;
  uint64_t remainingUnrollBudget = 4096;
  llvm::SmallPtrSet<Operation *, 16> writable;
  ExpansionBudget &budget;
};

} // namespace

// Native state captures need no expression-tree expansion. Admit a closed
// automatic scalar call graph only after checking every write and call,
// including in unused initializers or return values. Operations whose ERROR
// state needs constraint-specific instrumentation retain expression lowering.
static bool
canExecuteNativeConstraintFunction(semantic::SVSubroutineSymbolOp entry,
                                   const llvm::StringMap<Operation *> &symbols,
                                   bool &hasCallees) {
  llvm::SmallPtrSet<Operation *, 16> visited;
  auto resolve = [&](Operation *expression) -> Operation * {
    auto reference =
        expression->getAttrOfType<SymbolRefAttr>("referenced_symbol");
    return reference ? symbols.lookup(reference.getLeafReference()) : nullptr;
  };
  auto integral = [](Operation *symbol) {
    auto type = symbol->getAttrOfType<TypeAttr>("semantic_type");
    return type && (getSemanticPackedWidth(type.getValue()).has_value() ||
                    isa<semantic::TimeType>(type.getValue()));
  };
  std::function<bool(semantic::SVSubroutineSymbolOp)> validate;
  validate = [&](semantic::SVSubroutineSymbolOp function) -> bool {
    if (visited.contains(function))
      return true;
    if (function.getSubroutineKind() != semantic::SVSubroutineKind::Function ||
        function.getDefaultLifetime() !=
            semantic::SVVariableLifetime::Automatic ||
        function.getIsDpiImport().value_or(false) ||
        function.getIsConstructor().value_or(false) ||
        function.getIsBuiltin().value_or(false) ||
        function.getIsVirtual().value_or(false))
      return false;
    auto result = function.getReturnVariableSymbol();
    Operation *returnVariable =
        result ? symbols.lookup(result->getLeafReference()) : nullptr;
    if (!returnVariable || !integral(returnVariable))
      return false;
    visited.insert(function);
    llvm::SmallPtrSet<Operation *, 16> writable;
    bool valid = true;
    function->walk([&](Operation *node) {
      if (auto local = dyn_cast<semantic::SVVariableSymbolOp>(node)) {
        if (function.getThisVariableSymbol() &&
            function.getThisVariableSymbol()->getLeafReference() ==
                local.getSymName())
          return;
        if (!integral(local) ||
            local.getLifetime() != semantic::SVVariableLifetime::Automatic) {
          valid = false;
          return;
        }
        if (!local.getIsConst().value_or(false))
          writable.insert(local);
      } else if (auto formal =
                     dyn_cast<semantic::SVFormalArgumentSymbolOp>(node)) {
        bool input = formal.getDirection() == semantic::SVArgumentDirection::In;
        bool constRef =
            formal.getDirection() == semantic::SVArgumentDirection::Ref &&
            formal.getIsConst().value_or(false);
        if ((!input && !constRef) || !integral(formal))
          valid = false;
        if (input && !formal.getIsConst().value_or(false))
          writable.insert(formal);
      }
    });
    if (!valid)
      return false;
    auto writableLocal = [&](Operation *expression) {
      return isa<semantic::SVNamedValueExpressionOp>(expression) &&
             writable.contains(resolve(expression));
    };
    auto checked = function->walk([&](Operation *node) -> WalkResult {
      SmallVector<Operation *> children = getChildren(node);
      if (auto assignment =
              dyn_cast<semantic::SVAssignmentExpressionOp>(node)) {
        if (assignment.getHasTimingControl() ||
            assignment.getAssignmentKind() !=
                semantic::SVAssignmentKind::Blocking ||
            children.size() != 2 || !writableLocal(children.front()))
          return WalkResult::interrupt();
      }
      if (auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(node)) {
        using Unary = semantic::SVUnaryOperator;
        if (unary.getOperatorKind() == Unary::Preincrement ||
            unary.getOperatorKind() == Unary::Predecrement ||
            unary.getOperatorKind() == Unary::Postincrement ||
            unary.getOperatorKind() == Unary::Postdecrement)
          if (children.size() != 1 || !writableLocal(children.front()))
            return WalkResult::interrupt();
      }
      if (auto binary = dyn_cast<semantic::SVBinaryExpressionOp>(node)) {
        using Binary = semantic::SVBinaryOperator;
        if (binary.getOperatorKind() == Binary::Divide ||
            binary.getOperatorKind() == Binary::Mod ||
            binary.getOperatorKind() == Binary::Power)
          return WalkResult::interrupt();
      }
      if (isa<semantic::SVElementSelectExpressionOp,
              semantic::SVRangeSelectExpressionOp,
              semantic::SVNewClassExpressionOp,
              semantic::SVCopyClassExpressionOp,
              semantic::SVNewArrayExpressionOp,
              semantic::SVNewCovergroupExpressionOp>(node))
        return WalkResult::interrupt();
      if (isa<semantic::SVMemberAccessExpressionOp>(node)) {
        // Only a method's own non-null receiver can be read without carrying
        // a nullable address's ERROR state back to constraint creation.
        Operation *base =
            children.empty() ? nullptr : resolve(children.front());
        if (!base || !function.getThisVariableSymbol() ||
            base != symbols.lookup(
                        function.getThisVariableSymbol()->getLeafReference()))
          return WalkResult::interrupt();
      }
      if (auto call = dyn_cast<semantic::SVCallExpressionOp>(node)) {
        if (call.getIsSystemCall()) {
          if (!isRandomConstraintSystemFunction(call.getCalleeName()))
            return WalkResult::interrupt();
        } else {
          hasCallees = true;
          auto target =
              dyn_cast_or_null<semantic::SVSubroutineSymbolOp>(resolve(call));
          if (!target || !validate(target))
            return WalkResult::interrupt();
          // An explicit receiver must be this, rather than a nullable handle.
          if (call.getHasThisClass()) {
            Operation *base =
                children.empty() ? nullptr : resolve(children.front());
            if (!base || !function.getThisVariableSymbol() ||
                base !=
                    symbols.lookup(
                        function.getThisVariableSymbol()->getLeafReference()))
              return WalkResult::interrupt();
          }
        }
      }
      if (auto block = dyn_cast<semantic::SVBlockStatementOp>(node))
        if (block.getBlockKind() != semantic::SVStatementBlockKind::Sequential)
          return WalkResult::interrupt();
      if (node->getName().getStringRef().starts_with("talos.sv.statement.") &&
          !isa<semantic::SVStatementListOp, semantic::SVBlockStatementOp,
               semantic::SVEmptyStatementOp,
               semantic::SVVariableDeclStatementOp,
               semantic::SVExpressionStatementOp, semantic::SVReturnStatementOp,
               semantic::SVConditionalStatementOp, semantic::SVCaseStatementOp,
               semantic::SVForLoopStatementOp, semantic::SVWhileLoopStatementOp,
               semantic::SVDoWhileLoopStatementOp,
               semantic::SVRepeatLoopStatementOp,
               semantic::SVForeverLoopStatementOp, semantic::SVBreakStatementOp,
               semantic::SVContinueStatementOp>(node))
        return WalkResult::interrupt();
      return WalkResult::advance();
    });
    return !checked.wasInterrupted();
  };
  return validate(entry);
}

static FailureOr<Operation *> getConstraintFunctionResult(
    semantic::SVSubroutineSymbolOp function, semantic::SVCallExpressionOp call,
    const llvm::StringMap<Operation *> &symbols, Builder &builder,
    Block &expressions, ExpansionBudget &budget) {
  MLIRContext *context = function.getContext();
  SmallVector<semantic::SVReturnStatementOp> returns;
  SmallVector<semantic::SVExpressionStatementOp> expressionStatements;
  bool unsupportedStatement = false;
  bool unsupportedLocal = false;
  function->walk([&](Operation *nested) {
    if (nested == function.getOperation())
      return;
    if (auto local = dyn_cast<semantic::SVVariableSymbolOp>(nested)) {
      auto reference = FlatSymbolRefAttr::get(context, local.getSymName());
      bool compilerState =
          local.getIsCompilerGenerated().value_or(false) &&
          ((function.getReturnVariableSymbol() &&
            function.getReturnVariableSymbol()->getLeafReference() ==
                reference.getValue()) ||
           (function.getThisVariableSymbol() &&
            function.getThisVariableSymbol()->getLeafReference() ==
                reference.getValue()));
      unsupportedLocal |= !compilerState;
      return;
    }
    if (auto ret = dyn_cast<semantic::SVReturnStatementOp>(nested)) {
      returns.push_back(ret);
      return;
    }
    if (auto statement = dyn_cast<semantic::SVExpressionStatementOp>(nested)) {
      expressionStatements.push_back(statement);
      return;
    }
    StringRef name = nested->getName().getStringRef();
    if (auto block = dyn_cast<semantic::SVBlockStatementOp>(nested))
      unsupportedStatement |=
          block.getBlockKind() != semantic::SVStatementBlockKind::Sequential;
    if (name.starts_with("talos.sv.statement.") &&
        !isa<semantic::SVStatementListOp, semantic::SVBlockStatementOp>(nested))
      unsupportedStatement = true;
  });
  if (unsupportedLocal || unsupportedStatement) {
    FailureOr<Operation *> result =
        ConstraintFunctionBody(function, call, symbols, builder, expressions,
                               budget)
            .compile();
    if (succeeded(result))
      return result;
    if (budget.exhausted()) {
      budget.diagnose(getSemanticLocation(call));
      return failure();
    }
    emitError(getSemanticLocation(call))
        << "constraint function " << function.getName().value_or("")
        << " must be a side-effect-free expression function or an admitted "
           "automatic statement body";
    return failure();
  }
  auto requiresStatementEvaluation = [&](Operation *expression) {
    bool required = false;
    expression->walk([&](Operation *node) {
      required |= isa<semantic::SVAssignmentExpressionOp>(node);
      if (auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(node))
        required |=
            unary.getOperatorKind() ==
                semantic::SVUnaryOperator::Preincrement ||
            unary.getOperatorKind() ==
                semantic::SVUnaryOperator::Predecrement ||
            unary.getOperatorKind() ==
                semantic::SVUnaryOperator::Postincrement ||
            unary.getOperatorKind() == semantic::SVUnaryOperator::Postdecrement;
      if (auto reference =
              node->getAttrOfType<SymbolRefAttr>("referenced_symbol"))
        required |= function.getReturnVariableSymbol() &&
                    reference.getLeafReference() ==
                        function.getReturnVariableSymbol()->getLeafReference();
    });
    return required;
  };
  if (returns.size() == 1 && expressionStatements.empty()) {
    SmallVector<Operation *> values = getChildren(returns.front());
    if (values.size() == 1 && !requiresStatementEvaluation(values.front()))
      return values.front();
  }
  if (returns.empty() && expressionStatements.size() == 1) {
    SmallVector<Operation *> statement =
        getChildren(expressionStatements.front());
    auto assignment =
        statement.size() == 1
            ? dyn_cast<semantic::SVAssignmentExpressionOp>(statement.front())
            : semantic::SVAssignmentExpressionOp{};
    SmallVector<Operation *> operands =
        assignment ? getChildren(assignment) : SmallVector<Operation *>{};
    auto lhs = operands.size() == 2
                   ? operands.front()->getAttrOfType<SymbolRefAttr>(
                         "referenced_symbol")
                   : SymbolRefAttr{};
    if (assignment && !assignment.getHasTimingControl() &&
        assignment.getAssignmentKind() ==
            semantic::SVAssignmentKind::Blocking &&
        function.getReturnVariableSymbol() && lhs &&
        lhs.getLeafReference() ==
            function.getReturnVariableSymbol()->getLeafReference() &&
        !requiresStatementEvaluation(operands.back()))
      return operands.back();
  }
  FailureOr<Operation *> result =
      ConstraintFunctionBody(function, call, symbols, builder, expressions,
                             budget)
          .compile();
  if (succeeded(result))
    return result;
  if (budget.exhausted()) {
    budget.diagnose(getSemanticLocation(call));
    return failure();
  }
  emitError(getSemanticLocation(call))
      << "constraint function " << function.getName().value_or("")
      << " must be a side-effect-free expression function or an admitted "
         "automatic statement body";
  return failure();
}

LogicalResult expandRandomConstraintFunctions(
    MutableArrayRef<Operation *> constraintRoots,
    const llvm::StringMap<Operation *> &semanticSymbols, Builder &builder,
    const llvm::DenseMap<Operation *, unsigned> &,
    llvm::function_ref<bool(semantic::SVCallExpressionOp)> isAdmittedCall,
    llvm::function_ref<
        FailureOr<semantic::SVSubroutineSymbolOp>(semantic::SVCallExpressionOp)>
        resolveConstraintFunction) {
  ExpansionBudget budget;
  std::function<FailureOr<Operation *>(
      Operation *, const llvm::DenseMap<Operation *, Operation *> &, bool,
      SmallVectorImpl<Operation *> &)>
      cloneConstraintExpression;
  cloneConstraintExpression =
      [&](Operation *source,
          const llvm::DenseMap<Operation *, Operation *> &substitutions,
          bool functionBody,
          SmallVectorImpl<Operation *> &callStack) -> FailureOr<Operation *> {
    if (auto reference =
            source->getAttrOfType<SymbolRefAttr>("referenced_symbol")) {
      auto symbol = semanticSymbols.find(reference.getLeafReference());
      if (symbol != semanticSymbols.end())
        if (auto substitution = substitutions.find(symbol->second);
            substitution != substitutions.end()) {
          Operation *copy = substitution->second->clone();
          if (!budget.spend(copy)) {
            copy->destroy();
            budget.diagnose(getSemanticLocation(source));
            return failure();
          }
          return copy;
        }
    }

    if (auto callExpression = dyn_cast<semantic::SVCallExpressionOp>(source);
        callExpression && !isAdmittedCall(callExpression)) {
      FailureOr<semantic::SVSubroutineSymbolOp> function =
          resolveConstraintFunction(callExpression);
      if (failed(function))
        return failure();
      if (llvm::is_contained(callStack, function->getOperation())) {
        emitError(getSemanticLocation(callExpression))
            << "recursive constraint function calls are not executable";
        return failure();
      }

      SmallVector<semantic::SVFormalArgumentSymbolOp> formals;
      for (Operation *child : getChildren(*function))
        if (auto formal = dyn_cast<semantic::SVFormalArgumentSymbolOp>(child))
          formals.push_back(formal);
      SmallVector<Operation *> children = getChildren(callExpression);
      uint64_t argumentCount = callExpression.getArgumentCount();
      if (argumentCount > children.size() || formals.size() != argumentCount) {
        emitError(getSemanticLocation(callExpression))
            << "constraint function argument count does not match its "
               "declaration";
        return failure();
      }
      for (semantic::SVFormalArgumentSymbolOp formal : formals) {
        bool constReference =
            formal.getDirection() == semantic::SVArgumentDirection::Ref &&
            formal.getIsConst().value_or(false);
        if (formal.getDirection() != semantic::SVArgumentDirection::In &&
            !constReference) {
          emitError(getSemanticLocation(callExpression))
              << "constraint functions cannot have output, inout, or "
                 "non-const ref arguments";
          return failure();
        }
      }

      auto functionExpressions = std::make_unique<Block>();
      FailureOr<Operation *> result = failure();
      auto inputs = sim::get<sim::metadata::RandomGuardInputs>(source);
      bool hasCallees = false;
      if (!functionBody && inputs &&
          canExecuteNativeConstraintFunction(*function, semanticSymbols,
                                             hasCallees)) {
        // Keep inexpensive leaf expressions and proved bounded bodies available
        // for folding. A failed trial consumes neither the shared expansion
        // budget nor a diagnostic: the validated native body is the fallback.
        // Retain closed graphs containing user calls as a whole: an immediate
        // return expression can still call an unbounded or recursive body.
        if (!hasCallees) {
          // A native fallback makes a large speculative expansion unnecessary.
          // Keep the folding trial cheap even for exponentially reused locals.
          uint64_t allowance = budget.available();
          if (!inputs.getValue().isZero())
            allowance = std::min(allowance, uint64_t{1} << 14);
          ExpansionBudget trial(allowance);
          ScopedDiagnosticHandler handler(
              source->getContext(), [](Diagnostic &) { return success(); });
          result = getConstraintFunctionResult(*function, callExpression,
                                               semanticSymbols, builder,
                                               *functionExpressions, trial);
          if (succeeded(result))
            budget.spend(allowance - trial.available());
        }
        if (failed(result)) {
          // Ordinary function lowering executes the validated graph. Source
          // random arguments require a priority-stage handoff before its
          // opaque return capture is ready.
          Operation *cloned = source->cloneWithoutRegions();
          sim::mark<sim::metadata::RandomNativeFunction>(cloned);
          if (!budget.spend(cloned)) {
            cloned->destroy();
            budget.diagnose(getSemanticLocation(source));
            return failure();
          }
          for (auto [sourceRegion, clonedRegion] :
               llvm::zip_equal(source->getRegions(), cloned->getRegions()))
            for (Block &block : sourceRegion) {
              auto *clonedBlock = new Block();
              clonedRegion.push_back(clonedBlock);
              for (Operation &child : block) {
                auto input = cloneConstraintExpression(&child, substitutions,
                                                       false, callStack);
                if (failed(input)) {
                  cloned->destroy();
                  return failure();
                }
                clonedBlock->push_back(*input);
              }
            }
          return cloned;
        }
      }

      auto templates = std::make_unique<Block>();
      for (Operation *argument : ArrayRef(children).take_back(argumentCount)) {
        FailureOr<Operation *> cloned = cloneConstraintExpression(
            argument, substitutions, functionBody, callStack);
        if (failed(cloned))
          return failure();
        templates->push_back(*cloned);
      }
      llvm::DenseMap<Operation *, Operation *> functionSubstitutions;
      for (auto [formal, actual] :
           llvm::zip_equal(formals, templates->getOperations()))
        functionSubstitutions[formal.getOperation()] = &actual;

      if (failed(result))
        result = getConstraintFunctionResult(*function, callExpression,
                                             semanticSymbols, builder,
                                             *functionExpressions, budget);
      if (failed(result))
        return failure();
      callStack.push_back(function->getOperation());
      FailureOr<Operation *> cloned = cloneConstraintExpression(
          *result, functionSubstitutions, true, callStack);
      callStack.pop_back();
      if (succeeded(cloned)) {
        // Evaluate every input even when the return expression ignores it.
        // Guard creation propagates ERROR; unused input values add no solver
        // dependence to the expanded return expression.
        OperationState state(
            callExpression.getLoc(),
            semantic::SVConversionExpressionOp::getOperationName());
        state.addAttribute("semantic_type", source->getAttr("semantic_type"));
        state.addAttribute("node_id", source->getAttr("node_id"));
        state.addAttribute("is_implicit", builder.getBoolAttr(true));
        state.addAttribute(sim::metadata::RandomEvaluationInputs::getNameStr(),
                           builder.getI64IntegerAttr(argumentCount));
        auto *region = state.addRegion();
        region->push_back(new Block());
        bool spent = true;
        for (Operation &argument : templates->getOperations()) {
          region->front().push_back(argument.clone());
          spent &= budget.spend(&region->front().back());
        }
        region->front().push_back(*cloned);
        cloned = Operation::create(state);
        if (!spent) {
          (*cloned)->destroy();
          budget.diagnose(getSemanticLocation(callExpression));
          return failure();
        }
      }
      if (succeeded(cloned))
        if (auto inputs = sim::get<sim::metadata::RandomGuardInputs>(source)) {
          APInt mask = inputs.getValue();
          if (auto existing =
                  sim::get<sim::metadata::RandomGuardInputs>((*cloned)))
            mask |= existing.getValue().zextOrTrunc(mask.getBitWidth());
          sim::set<sim::metadata::RandomGuardInputs>(
              (*cloned), builder.getIntegerAttr(inputs.getType(), mask));
        }
      return cloned;
    }

    Operation *cloned = source->cloneWithoutRegions();
    if (!budget.spend(cloned)) {
      cloned->destroy();
      budget.diagnose(getSemanticLocation(source));
      return failure();
    }
    if (functionBody) {
      sim::mark<sim::metadata::RandomFunctionExpression>(cloned);
      if (auto reference =
              source->getAttrOfType<SymbolRefAttr>("referenced_symbol")) {
        auto symbol = semanticSymbols.find(reference.getLeafReference());
        if (symbol != semanticSymbols.end())
          sim::mark<sim::metadata::RandomFunctionState>(cloned);
      }
    }
    for (auto [sourceRegion, clonedRegion] :
         llvm::zip_equal(source->getRegions(), cloned->getRegions())) {
      for (Block &sourceBlock : sourceRegion) {
        auto *clonedBlock = new Block();
        clonedRegion.push_back(clonedBlock);
        for (Operation &child : sourceBlock) {
          FailureOr<Operation *> clonedChild = cloneConstraintExpression(
              &child, substitutions, functionBody, callStack);
          if (failed(clonedChild)) {
            cloned->destroy();
            return failure();
          }
          clonedBlock->push_back(*clonedChild);
        }
      }
    }
    return cloned;
  };

  for (Operation *&root : constraintRoots) {
    llvm::DenseMap<Operation *, Operation *> substitutions;
    SmallVector<Operation *> callStack;
    FailureOr<Operation *> expanded =
        cloneConstraintExpression(root, substitutions, false, callStack);
    if (failed(expanded)) {
      return failure();
    }
    root->getBlock()->getOperations().insert(root->getIterator(), *expanded);
    root->erase();
    root = *expanded;
  }

  return expandStaticRandomInsideExpressions(constraintRoots, builder);
}

} // namespace talos::simlowering
