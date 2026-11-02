//===- PrepareExpressions.cpp - Immutable source expression relations
//------===//

#include "PrepareExpressions.h"
#include "talos/Dialect/Simulation/SimulationVPI.h"
#include "talos/Dialect/Simulation/SimulationVPIConstantValues.h"
#include "talos/Reflection/VPIObjectModel.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/StringSet.h"

using namespace mlir;

namespace talos::simlowering {
VPIExpressionResolver::VPIExpressionResolver(
    sim::SimDesignOp design, const llvm::StringMap<DescriptorInfo> &descriptors)
    : design(design), module(design->getParentOfType<ModuleOp>()),
      descriptors(descriptors) {
  for (auto declaration : design.getOps<sim::SimVPINetIdentityDeclOp>()) {
    auto [entry, inserted] = netIdentities.try_emplace(
        declaration.getHierarchicalName(), declaration);
    // Display paths need not distinguish compilation units. Ambiguity is not
    // permission to pick an arbitrary declaration.
    if (!inserted)
      entry->second = {};
  }
  for (auto declaration : design.getOps<sim::SimStorageDeclOp>())
    storages[declaration.getId()] = declaration;
  for (auto declaration : design.getOps<sim::SimNetDeclOp>())
    nets[declaration.getId()] = declaration;
}

std::optional<VPIExpressionEndpoint>
VPIExpressionResolver::resolve(Operation *expression) {
  if (!isa<semantic::SVNamedValueExpressionOp,
           semantic::SVHierarchicalValueExpressionOp>(expression))
    return std::nullopt;
  auto reference =
      expression->getAttrOfType<SymbolRefAttr>("referenced_symbol");
  Operation *source =
      reference && module ? symbols.lookupSymbolIn(module, reference) : nullptr;
  if (!source)
    return std::nullopt;
  // Ref declarations are expressions through their RefObj, even if later
  // preparation attaches an owned-local or anchor identity to the source.
  if (auto formal = dyn_cast<semantic::SVFormalArgumentSymbolOp>(source);
      formal && formal.getDirection() == semantic::SVArgumentDirection::Ref)
    return std::nullopt;
  if (auto port = dyn_cast<semantic::SVPortSymbolOp>(source);
      port && port.getDirection() == semantic::SVArgumentDirection::Ref)
    return std::nullopt;
  auto symbolic =
      [&](FlatSymbolRefAttr symbol) -> std::optional<VPIExpressionEndpoint> {
    if (!symbol)
      return std::nullopt;
    Operation *declaration = symbols.lookupSymbolIn(design, symbol);
    uint32_t kind = 0;
    if (auto local = dyn_cast_or_null<sim::SimVPILocalDeclOp>(declaration))
      kind = sim::vpiKindForClassMember(local.getVpiType());
    else if (auto anchor =
                 dyn_cast_or_null<sim::SimVPIObjectAnchorOp>(declaration))
      kind = anchor.getVpiKind();
    if (!kind)
      return std::nullopt;
    return VPIExpressionEndpoint{
        sim::VPIObjectRefAttr::get(expression->getContext(),
                                   sim::VPIObjectRefKind::Symbol, {}, symbol),
        kind};
  };
  if (auto member = sim::get<sim::metadata::VpiDefinitionMember>(source)) {
    if (failed(
            sim::verifyVPIDefinitionMemberRef(source, design, member, symbols)))
      return std::nullopt;
    auto declaration =
        symbols.lookupSymbolIn<sim::SimVPIDefinitionMemberDeclOp>(
            design, member.getSymbol());
    return VPIExpressionEndpoint{member, declaration.getVpiKind()};
  }
  if (auto local = sim::get<sim::metadata::VpiLocal>(source))
    return symbolic(local);
  if (auto anchor = sim::get<sim::metadata::VpiAnchor>(source))
    return symbolic(anchor);
  // Ref formals/ports require their RefObj identity. Do not expose an aliased
  // backing variable as the expression of the formal declaration (37.15).
  if (!isa<semantic::SVVariableSymbolOp, semantic::SVNetSymbolOp>(source))
    return std::nullopt;
  StringRef path = getHierarchyName(source);
  if (path.empty())
    return std::nullopt;
  auto found = descriptors.find(path);
  if (found == descriptors.end())
    return std::nullopt;
  const DescriptorInfo &descriptor = found->second;
  if (descriptor.viewOffset || descriptor.packedViewOffset ||
      !descriptor.viewIndices.empty() || descriptor.type != descriptor.rootType)
    return std::nullopt;
  Builder builder(expression->getContext());
  if (descriptor.kind == DescriptorInfo::Kind::Net) {
    auto declared = netIdentities.find(path);
    if (declared != netIdentities.end()) {
      auto identity = declared->second;
      if (!identity || identity.getBackingNetId() != descriptor.id)
        return std::nullopt;
      return VPIExpressionEndpoint{
          sim::VPIObjectRefAttr::get(expression->getContext(),
                                     sim::VPIObjectRefKind::NetIdentity,
                                     identity.getIdAttr()),
          sim::vpiKindForNet(identity.getVpiType())};
    }
    auto net = nets.lookup(descriptor.id);
    if (!net || !net.getVpiTypeAttr() || net.getHierarchicalName() != path)
      return std::nullopt;
    return VPIExpressionEndpoint{
        sim::VPIObjectRefAttr::get(expression->getContext(),
                                   sim::VPIObjectRefKind::Net,
                                   builder.getI64IntegerAttr(descriptor.id)),
        sim::vpiKindForNet(net.getVpiTypeAttr())};
  }
  if (descriptor.kind == DescriptorInfo::Kind::Storage) {
    auto storage = storages.lookup(descriptor.id);
    if (!storage || !storage.getVpiTypeAttr() ||
        storage.getHierarchicalName() != path)
      return std::nullopt;
    return VPIExpressionEndpoint{
        sim::VPIObjectRefAttr::get(expression->getContext(),
                                   sim::VPIObjectRefKind::Storage,
                                   builder.getI64IntegerAttr(descriptor.id)),
        sim::vpiKindForStorage(storage.getVpiTypeAttr())};
  }
  return std::nullopt;
}

VPIExpressionMaterializer::VPIExpressionMaterializer(
    sim::SimDesignOp design, const llvm::StringMap<DescriptorInfo> &descriptors,
    OpBuilder &builder)
    : design(design), declarations(design, descriptors), builder(builder) {
  for (auto expression : design.getOps<sim::SimVPIExpressionDeclOp>())
    nextID = std::max(nextID, uint64_t(expression.getId()) + 1);
  for (Operation &operation : design.getBody().front())
    if (auto name = operation.getAttrOfType<StringAttr>(
            SymbolTable::getSymbolAttrName()))
      designSymbols.insert(name.getValue());
}

FailureOr<std::optional<VPIExpressionEndpoint>>
VPIExpressionMaterializer::resolve(Operation *expression,
                                   sim::VPIObjectRefAttr owner,
                                   uint32_t ownerKind, uint64_t scope,
                                   uint32_t selector, sim::VPIRelationMode mode,
                                   uint64_t ordinal) {
  return resolveImpl(expression, owner, ownerKind, scope, selector, mode,
                     ordinal, true);
}

FailureOr<std::optional<SmallVector<VPIExpressionEndpoint>>>
VPIExpressionMaterializer::resolveGroup(ArrayRef<Operation *> expressions,
                                        sim::VPIObjectRefAttr owner,
                                        uint32_t ownerKind, uint64_t scope,
                                        uint32_t selector) {
  for (auto [ordinal, expression] : llvm::enumerate(expressions)) {
    auto result = resolveImpl(expression, owner, ownerKind, scope, selector,
                              sim::VPIRelationMode::Iterate, ordinal, false);
    if (failed(result))
      return failure();
    if (!*result)
      return std::optional<SmallVector<VPIExpressionEndpoint>>{};
  }
  SmallVector<VPIExpressionEndpoint> targets;
  for (auto [ordinal, expression] : llvm::enumerate(expressions)) {
    auto result = resolveImpl(expression, owner, ownerKind, scope, selector,
                              sim::VPIRelationMode::Iterate, ordinal, true);
    if (failed(result) || !*result)
      return failure();
    targets.push_back(**result);
  }
  return std::optional<SmallVector<VPIExpressionEndpoint>>(std::move(targets));
}

FailureOr<std::optional<VPIExpressionEndpoint>>
VPIExpressionMaterializer::resolveImpl(Operation *expression,
                                       sim::VPIObjectRefAttr owner,
                                       uint32_t ownerKind, uint64_t scope,
                                       uint32_t selector,
                                       sim::VPIRelationMode mode,
                                       uint64_t ordinal, bool materialize) {
  using Kind = reflection::VPIObjectKind;
  using Rel = reflection::VPIRelationKind;
  auto unsupported = []() -> std::optional<VPIExpressionEndpoint> {
    return std::nullopt;
  };
  auto integral = [](Type type) {
    for (;;) {
      if (auto array = dyn_cast<semantic::RangedPackedArrayType>(type))
        type = array.getElementType();
      else if (auto array = dyn_cast<semantic::PackedArrayType>(type))
        type = array.getElementType();
      else
        return isa<semantic::IntegralType, semantic::LogicType>(type);
    }
  };
  struct Planned {
    Operation *source;
    std::optional<VPIExpressionEndpoint> endpoint;
    uint32_t kind = 0, code = 0;
    Type type{};
    sim::VPITypeSemanticsAttr semantic{};
    sim::FrozenConstantAttr frozen{};
    StringAttr identifier{};
    SmallVector<unsigned> children{};
    bool sourceOnly = false;
    bool unqualifiedEvent = false;
  };
  SmallVector<Planned> plan;
  plan.push_back({expression, {}});
  // The source AST is an owned tree. Each visit is a separate occurrence;
  // even repeated declaration leaves occupy distinct ordered operand slots.
  for (size_t index = 0; index != plan.size(); ++index) {
    Operation *source = plan[index].source;
    // Bound implicit integral conversions apply the surrounding context; they
    // are not explicit source cast occurrences. Exact child operations already
    // carry Slang's propagated type, while declaration leaves retain their
    // declared type and are resized by the operator. Unsized X/Z filling
    // remains unavailable until its context can be represented exactly.
    for (;;) {
      auto children = getChildren(source);
      if (auto signal = dyn_cast<semantic::SVSignalEventControlOp>(source);
          signal && signal.getEdgeKind() == semantic::EdgeKind::Change &&
          !signal.getHasIff() && children.size() == 1)
        source = children.front();
      else if (isa<semantic::SVEventListControlOp>(source) &&
               children.size() == 1)
        source = children.front();
      else if (auto conversion =
                   dyn_cast<semantic::SVConversionExpressionOp>(source);
               conversion && source->getAttrOfType<BoolAttr>("is_implicit") &&
               source->getAttrOfType<BoolAttr>("is_implicit").getValue() &&
               children.size() == 1) {
        auto type = source->getAttrOfType<TypeAttr>("semantic_type");
        auto childType =
            children.front()->getAttrOfType<TypeAttr>("semantic_type");
        if (!type || !childType || !integral(type.getValue()) ||
            !integral(childType.getValue()) ||
            getUnsizedUnknownFillWidth(children.front()))
          return unsupported();
        source = children.front();
      } else
        break;
    }
    plan[index].source = source;
    if (auto endpoint = declarations.resolve(source)) {
      auto type = source->getAttrOfType<TypeAttr>("semantic_type");
      if (index != 0 && (!type || !integral(type.getValue())))
        return unsupported();
      plan[index].endpoint = endpoint;
      plan[index].kind = endpoint->kind;
      if (isa<semantic::SVNamedValueExpressionOp>(source)) {
        auto reference =
            source->getAttrOfType<SymbolRefAttr>("referenced_symbol");
        auto module = source->getParentOfType<ModuleOp>();
        auto *declaration =
            reference && module
                ? sourceSymbols.lookupSymbolIn(module, reference)
                : nullptr;
        auto name = declaration ? declaration->getAttrOfType<StringAttr>("name")
                                : StringAttr{};
        // Only an exact unqualified reference to a lexical ancestor's direct
        // declaration supplies a raw identifier. Imported/hierarchical names
        // need their complete source reference syntax in a later extension.
        bool lexical = false;
        for (auto *parent = source->getParentOp(); parent;
             parent = parent->getParentOp())
          lexical |= declaration && declaration->getParentOp() == parent;
        if (lexical && name && !name.empty())
          plan[index].identifier = name;
      }
      continue;
    }
    SmallVector<Operation *> children;
    uint32_t kind = 0, code = 0;
    bool sourceOnly = false;
    if (auto signal = dyn_cast<semantic::SVSignalEventControlOp>(source)) {
      auto syntax = getChildren(source);
      if (syntax.size() != (signal.getHasIff() ? 2u : 1u))
        return unsupported();
      auto edge = signal.getEdgeKind();
      if (edge != semantic::EdgeKind::Change &&
          edge != semantic::EdgeKind::Posedge &&
          edge != semantic::EdgeKind::Negedge)
        return unsupported();
      kind = uint32_t(Kind::Operation);
      sourceOnly = true;
      if (signal.getHasIff() && !plan[index].unqualifiedEvent) {
        code = 68; // vpiIffOp
        // A qualified edge owns a distinct edge operation below the iff.
        // Plan that occurrence from the same typed source, without cloning IR.
        children = {edge == semantic::EdgeKind::Change ? syntax.front()
                                                       : source,
                    syntax.back()};
      } else {
        if (edge == semantic::EdgeKind::Change)
          return unsupported();
        code = edge == semantic::EdgeKind::Posedge ? 39 : 40;
        children.push_back(syntax.front());
      }
    } else if (isa<semantic::SVEventListControlOp>(source)) {
      kind = uint32_t(Kind::Operation);
      code = 35; // vpiEventOrOp
      sourceOnly = true;
      children = getChildren(source);
      if (children.size() < 2)
        return unsupported();
    } else if (isa<semantic::SVIntegerLiteralOp,
                   semantic::SVUnbasedUnsizedIntegerLiteralOp>(source)) {
      auto value = source->getAttrOfType<StringAttr>("constant_value");
      if (!value || value.getValue() == "$")
        return unsupported();
      kind = uint32_t(Kind::Constant);
    } else if (isa<semantic::SVUnaryExpressionOp,
                   semantic::SVBinaryExpressionOp,
                   semantic::SVConditionalExpressionOp>(source)) {
      const reflection::VPISourceOperatorDescriptor *operation = nullptr;
      if (auto unary = dyn_cast<semantic::SVUnaryExpressionOp>(source)) {
        auto name = semantic::stringifySVUnaryOperator(unary.getOperatorKind());
        operation = reflection::findVPISourceOperator(
            std::string_view(name.data(), name.size()), 1);
      } else if (auto binary =
                     dyn_cast<semantic::SVBinaryExpressionOp>(source)) {
        auto name =
            semantic::stringifySVBinaryOperator(binary.getOperatorKind());
        operation = reflection::findVPISourceOperator(
            std::string_view(name.data(), name.size()), 2);
      } else {
        auto conditional = cast<semantic::SVConditionalExpressionOp>(source);
        auto patterns = conditional.getConditionPatternFlags();
        if (conditional.getConditionCount() != 1 || patterns.size() != 1 ||
            patterns.front())
          return unsupported();
        operation = reflection::findVPISourceOperator("conditional", 3);
      }
      children = getChildren(source);
      if (!operation || children.size() != operation->arity ||
          reflection::integralOperatorRule(operation->value) ==
              reflection::VPIIntegralOperatorRule::Unsupported)
        return unsupported();
      kind = uint32_t(Kind::Operation);
      code = operation->value;
    } else if (isa<semantic::SVConversionExpressionOp>(source)) {
      auto implicit = source->getAttrOfType<BoolAttr>("is_implicit");
      auto constant = source->getAttrOfType<BoolAttr>("is_const_cast");
      children = getChildren(source);
      if (!implicit || implicit.getValue() ||
          (constant && constant.getValue()) || children.size() != 1)
        return unsupported();
      kind = uint32_t(Kind::Operation);
      code = 67; // vpiCastOp: the semantic root is its exact target Typespec.
    } else if (isa<semantic::SVConcatenationExpressionOp>(source)) {
      kind = uint32_t(Kind::Operation);
      code = 33;
      children = getChildren(source);
      if (children.empty())
        return unsupported();
    } else if (isa<semantic::SVReplicationExpressionOp>(source)) {
      kind = uint32_t(Kind::Operation);
      code = 34;
      auto syntax = getChildren(source);
      if (syntax.size() != 2 ||
          !isa<semantic::SVConcatenationExpressionOp>(syntax[1]))
        return unsupported();
      // 37.59 detail 1: multiplier followed by the expressions within the
      // replicated concatenation, without a fabricated nested Concat node.
      children.push_back(syntax[0]);
      auto operands = getChildren(syntax[1]);
      children.append(operands);
      if (children.size() < 2)
        return unsupported();
    } else if (isa<semantic::SVElementSelectExpressionOp>(source)) {
      children = getChildren(source);
      if (children.size() != 2)
        return unsupported();
      auto parent = declarations.resolve(children[0]);
      auto parentType = children[0]->getAttrOfType<TypeAttr>("semantic_type");
      auto layout = parentType
                        ? getSemanticSelectionLayout(parentType.getValue())
                        : std::nullopt;
      if (!parent || !layout || layout->elementWidth != 1 ||
          !(kind = reflection::vpiScalarBitSelectionKind(parent->kind)))
        return unsupported();
    } else if (auto range =
                   dyn_cast<semantic::SVRangeSelectExpressionOp>(source)) {
      children = getChildren(source);
      if (children.size() != 3)
        return unsupported();
      auto parentType = children[0]->getAttrOfType<TypeAttr>("semantic_type");
      auto layout = parentType
                        ? getSemanticSelectionLayout(parentType.getValue())
                        : std::nullopt;
      if (!layout || layout->elementWidth != 1)
        return unsupported();
      if (range.getSelectionKind() == semantic::SVRangeSelectionKind::Simple)
        kind = uint32_t(Kind::PartSelect);
      else {
        kind = uint32_t(Kind::IndexedPartSelect);
        code = range.getSelectionKind() ==
                       semantic::SVRangeSelectionKind::IndexedUp
                   ? 1
                   : 2;
      }
    } else
      return unsupported();
    plan[index].kind = kind;
    plan[index].code = code;
    plan[index].sourceOnly = sourceOnly;
    if (!sourceOnly) {
      auto sourceType = source->getAttrOfType<TypeAttr>("semantic_type");
      if (!sourceType || !integral(sourceType.getValue()))
        return unsupported();
      auto normalized = getNormalizedSemanticType(source);
      auto declared = sim::get<sim::metadata::VpiDeclaredType>(source);
      if (code == 67 && source->hasAttr(vpiTypedefLayersAttrName) && !declared)
        return unsupported();
      FailureOr<sim::VPITypeSemanticsAttr> semantic =
          declared
              ? declared
              : makeVPITypeSemantics(sourceType.getValue(),
                                     getSemanticLocation(source), {}, source);
      if (failed(normalized) || failed(semantic))
        return failure();
      if (!sim::getPackedScalarType(*normalized) ||
          !sim::getPackedWidth(*normalized).value_or(0))
        return unsupported();
      plan[index].type = *normalized;
      plan[index].semantic = *semantic;
      if (kind == uint32_t(Kind::Constant)) {
        auto frozen = freezeSemanticConstant(source);
        if (failed(frozen))
          return failure();
        plan[index].frozen = *frozen;
      }
    }
    for (Operation *child : children) {
      if (plan.size() >= std::numeric_limits<unsigned>::max()) {
        source->emitError(
            "VPI expression occurrence count exceeds the supported limit");
        return failure();
      }
      unsigned childIndex = static_cast<unsigned>(plan.size());
      plan.push_back({child, {}});
      plan.back().unqualifiedEvent = child == source;
      plan[index].children.push_back(childIndex);
    }
  }
  auto legal = [](uint32_t sourceKind, uint32_t selector,
                  sim::VPIRelationMode mode, uint32_t targetKind) {
    const auto *edge = reflection::findVPITraversal(
        sourceKind, selector,
        mode == sim::VPIRelationMode::Handle
            ? reflection::VPITraversalMode::Handle
            : reflection::VPITraversalMode::Iterate);
    return edge && !edge->statementContainment &&
           edge->automaticRelation == reflection::VPIAutomaticRelation::None &&
           reflection::vpiObjectSetContains(edge->targets, targetKind);
  };
  auto childSelector = [](const Planned &node, unsigned child) {
    if (node.kind == uint32_t(Kind::Operation))
      return uint32_t(Rel::OperandRel);
    if (child == 0)
      return uint32_t(Rel::ParentRel);
    if (reflection::isVPIBitSelection(node.kind))
      return uint32_t(Rel::IndexRel);
    bool part = node.kind == uint32_t(Kind::PartSelect);
    return uint32_t(child == 1
                        ? (part ? Rel::LeftRangeRel : Rel::BaseExprRel)
                        : (part ? Rel::RightRangeRel : Rel::WidthExprRel));
  };
  if (!legal(ownerKind, selector, mode, plan.front().kind))
    return unsupported();
  auto shape = [&](const Planned &node)
      -> std::optional<reflection::VPIIntegralExpressionShape> {
    auto type = node.source->getAttrOfType<TypeAttr>("semantic_type");
    if (!type || !integral(type.getValue()))
      return std::nullopt;
    auto normalized = getNormalizedSemanticType(node.source);
    auto semantic = makeVPITypeSemantics(
        type.getValue(), getSemanticLocation(node.source), {}, node.source);
    if (failed(normalized) || failed(semantic))
      return std::nullopt;
    auto width = sim::getPackedWidth(*normalized);
    if (!width)
      return std::nullopt;
    return reflection::VPIIntegralExpressionShape{
        *width, semantic->getIsSigned(), semantic->getIsFourState(), node.code};
  };
  // Prove immutable arithmetic from the exact source tree. These temporary
  // values are validation state only; the database retains the original
  // operations and contextual parameter references, never another value copy.
  SmallVector<std::optional<sim::VPIConstantValue>> constants(plan.size());
  SmallVector<std::optional<reflection::VPIIntegralExpressionShape>> shapes;
  for (const auto &node : plan)
    shapes.push_back(shape(node));
  for (size_t index = plan.size(); index-- != 0;) {
    const auto &node = plan[index];
    if (!shapes[index])
      continue;
    auto frozen = node.frozen;
    if (node.endpoint && (node.kind == uint32_t(Kind::Parameter) ||
                          node.kind == uint32_t(Kind::SpecParam) ||
                          node.kind == uint32_t(Kind::EnumConst))) {
      auto reference =
          node.source->getAttrOfType<SymbolRefAttr>("referenced_symbol");
      auto module = node.source->getParentOfType<ModuleOp>();
      auto *declaration = reference && module
                              ? sourceSymbols.lookupSymbolIn(module, reference)
                              : nullptr;
      if (declaration && declaration->hasAttr("constant_value")) {
        auto value = freezeSemanticConstant(declaration);
        if (failed(value))
          return failure();
        frozen = *value;
      }
    }
    if (frozen) {
      auto planes = dyn_cast<ArrayAttr>(frozen.getValue());
      if (!planes || planes.size() != 2)
        continue;
      auto value = dyn_cast<IntegerAttr>(planes[0]);
      auto unknown = dyn_cast<IntegerAttr>(planes[1]);
      if (value && unknown &&
          value.getValue().getBitWidth() == shapes[index]->width &&
          unknown.getValue().getBitWidth() == shapes[index]->width)
        constants[index] =
            sim::VPIConstantValue{value.getValue(), unknown.getValue()};
      continue;
    }
    if (node.kind != uint32_t(Kind::Operation) || node.sourceOnly)
      continue;
    SmallVector<sim::VPIConstantValue, 3> values;
    SmallVector<reflection::VPIIntegralExpressionShape, 3> operands;
    for (unsigned child : node.children) {
      if (!constants[child] || !shapes[child])
        break;
      values.push_back(*constants[child]);
      operands.push_back(*shapes[child]);
    }
    if (values.size() == node.children.size())
      constants[index] = sim::evaluateVPIIntegralConstant(
          node.code, *shapes[index], values, operands);
  }
  for (size_t nodeIndex = 0; nodeIndex != plan.size(); ++nodeIndex) {
    const auto &node = plan[nodeIndex];
    auto knownBound = [&](unsigned position) -> std::optional<int64_t> {
      if (position >= node.children.size())
        return std::nullopt;
      unsigned child = node.children[position];
      return constants[child] && shapes[child]
                 ? sim::knownVPIConstantInteger(*constants[child],
                                                shapes[child]->isSigned)
                 : std::nullopt;
    };
    if ((node.kind == uint32_t(Kind::PartSelect) &&
         (!knownBound(1) || !knownBound(2))) ||
        (node.kind == uint32_t(Kind::IndexedPartSelect) &&
         (!knownBound(2) || *knownBound(2) <= 0)) ||
        (node.kind == uint32_t(Kind::Operation) && node.code == 34 &&
         (!knownBound(0) || *knownBound(0) <= 0)))
      return unsupported();
    if (!node.sourceOnly && node.kind == uint32_t(Kind::Operation) &&
        reflection::integralOperatorRule(node.code) !=
            reflection::VPIIntegralOperatorRule::Unsupported) {
      auto resultShape = shapes[nodeIndex];
      SmallVector<reflection::VPIIntegralExpressionShape, 3> operands;
      for (unsigned child : node.children) {
        auto childShape = shapes[child];
        if (!childShape)
          return unsupported();
        operands.push_back(*childShape);
      }
      if (!resultShape ||
          !reflection::validVPIIntegralOperator(
              node.code, *resultShape, operands.data(), operands.size()))
        return unsupported();
    }
    auto childMode = node.kind == uint32_t(Kind::Operation)
                         ? sim::VPIRelationMode::Iterate
                         : sim::VPIRelationMode::Handle;
    for (auto [index, child] : llvm::enumerate(node.children))
      if (!legal(node.kind, childSelector(node, index), childMode,
                 plan[child].kind))
        return unsupported();
  }
  if (!materialize)
    return std::optional<VPIExpressionEndpoint>(
        VPIExpressionEndpoint{{}, plan.front().kind});
  uint64_t computed =
      llvm::count_if(plan, [](const Planned &node) { return !node.endpoint; });
  if (nextID > uint64_t(INT64_MAX) || computed > uint64_t(INT64_MAX) - nextID)
    return expression->emitError("VPI source expression ID space exhausted"),
           failure();
  // Assign all exact identities before materialization. No partial declarations
  // exist when unsupported syntax or a generated relation check rejects a plan.
  SmallVector<uint64_t> ids(plan.size());
  for (auto [index, node] : llvm::enumerate(plan)) {
    if (node.endpoint)
      continue;
    ids[index] = nextID++;
    std::string name =
        "__talos_vpi_rtl_expression_" + std::to_string(ids[index]);
    while (designSymbols.contains(name)) {
      if (nextID > uint64_t(INT64_MAX))
        return expression->emitError(
                   "VPI source expression ID space exhausted"),
               failure();
      ids[index] = nextID++;
      name = "__talos_vpi_rtl_expression_" + std::to_string(ids[index]);
    }
    designSymbols.insert(name);
    node.endpoint = VPIExpressionEndpoint{
        sim::VPIObjectRefAttr::get(
            builder.getContext(),
            FlatSymbolRefAttr::get(builder.getContext(), name)),
        node.kind};
  }
  struct Incoming {
    sim::VPIObjectRefAttr owner;
    uint32_t selector;
    sim::VPIRelationMode mode;
    uint64_t ordinal;
  };
  SmallVector<Incoming> incoming(plan.size());
  incoming[0] = {owner, selector, mode, ordinal};
  for (const auto &node : plan)
    for (auto [index, child] : llvm::enumerate(node.children)) {
      bool operand = node.kind == uint32_t(Kind::Operation);
      incoming[child] = {node.endpoint->reference, childSelector(node, index),
                         operand ? sim::VPIRelationMode::Iterate
                                 : sim::VPIRelationMode::Handle,
                         operand ? index : 0};
    }
  OpBuilder::InsertionGuard guard(builder);
  builder.setInsertionPointToEnd(&design.getBody().front());
  for (auto [index, node] : llvm::enumerate(plan)) {
    if (!node.type && !node.sourceOnly)
      continue;
    auto slot = incoming[index];
    sim::SimVPIExpressionDeclOp::create(
        builder, getSemanticLocation(node.source),
        node.endpoint->reference.getSymbol().getValue(), ids[index], node.kind,
        builder.getI64IntegerAttr(scope), slot.owner, slot.selector, slot.mode,
        slot.ordinal, node.type ? TypeAttr::get(node.type) : TypeAttr{},
        node.semantic, node.frozen,
        node.kind == uint32_t(Kind::Operation)
            ? builder.getI32IntegerAttr(node.code)
            : IntegerAttr{},
        node.kind == uint32_t(Kind::IndexedPartSelect)
            ? builder.getI32IntegerAttr(node.code)
            : IntegerAttr{},
        node.sourceOnly, FlatSymbolRefAttr{});
    for (unsigned child : node.children) {
      auto edge = incoming[child];
      auto relation = sim::SimVPIRelationDeclOp::create(
          builder, getSemanticLocation(plan[child].source), edge.owner,
          edge.selector, edge.mode, edge.ordinal,
          plan[child].endpoint->reference);
      if (plan[child].identifier)
        sim::set<sim::metadata::VpiExpressionIdentifier>(
            relation, plan[child].identifier);
    }
  }
  return plan.front().endpoint;
}

LogicalResult materializeProceduralExpressionRelations(
    sim::SimDesignOp design, const PreparedUnits &units,
    const llvm::StringMap<DescriptorInfo> &descriptors, OpBuilder &builder) {
  using Relation = reflection::VPIRelationKind;
  using Mode = reflection::VPITraversalMode;
  llvm::DenseMap<uint64_t, sim::SimStatementDeclOp> statements;
  for (auto statement : design.getOps<sim::SimStatementDeclOp>())
    statements[statement.getId()] = statement;
  llvm::DenseMap<uint64_t, Operation *> unitSources;
  for (const PreparedUnit &unit : units.units)
    unitSources[unit.id] = unit.source;
  llvm::StringMap<sim::SimVPICallDeclOp> calls;
  for (auto call : design.getOps<sim::SimVPICallDeclOp>())
    calls[call.getSymName()] = call;
  if (statements.empty() && calls.empty())
    return success();
  llvm::DenseMap<std::pair<uint64_t, uint64_t>, uint64_t> caseItems;
  for (auto relation : design.getOps<sim::SimVPIStatementRelationDeclOp>())
    if (relation.getSourceKind() == sim::VPIStatementSourceKind::Statement &&
        relation.getSelector() ==
            static_cast<uint32_t>(reflection::VPIObjectKind::CaseItem))
      caseItems[{relation.getSourceId(), relation.getOrdinal()}] =
          relation.getTargetStatementId();
  VPIExpressionMaterializer materializer(design, descriptors, builder);
  bool invalid = false;
  llvm::DenseMap<Attribute, SmallVector<Attribute>> uses;
  for (auto relation : design.getOps<sim::SimVPIRelationDeclOp>())
    if (relation.getSelector() == static_cast<uint32_t>(Relation::UseRel) &&
        relation.getMode() == sim::VPIRelationMode::Iterate)
      uses[relation.getSource()].push_back(relation.getTarget());
  OpBuilder::InsertionGuard guard(builder);
  builder.setInsertionPointToEnd(&design.getBody().front());
  llvm::DenseSet<uint64_t> visited;
  for (const PreparedUnit &unit : units.units) {
    if (!isa<semantic::SVProceduralBlockSymbolOp,
             semantic::SVSubroutineSymbolOp>(unit.source))
      continue;
    unit.source->walk<WalkOrder::PreOrder>([&](Operation *source) {
      if (source != unit.source && isa<semantic::SVProceduralBlockSymbolOp,
                                       semantic::SVSubroutineSymbolOp>(source))
        return WalkResult::skip();
      if (auto call = dyn_cast<semantic::SVCallExpressionOp>(source)) {
        auto site = sim::get<sim::metadata::VpiCallSite>(call);
        auto declaration =
            site ? calls.lookup(site.getValue()) : sim::SimVPICallDeclOp{};
        using Kind = reflection::VPIObjectKind;
        auto defaulted = call.getDefaultedArguments();
        auto arguments = getChildren(call);
        bool supported =
            declaration &&
            (declaration.getVpiKind() == uint32_t(Kind::FuncCall) ||
             declaration.getVpiKind() == uint32_t(Kind::TaskCall)) &&
            declaration.getCalleeCodeUnitId() && !call.getHasThisClass() &&
            !call.getHasOutputArguments() && defaulted &&
            defaulted->size() == arguments.size() &&
            call.getArgumentCount() == arguments.size() &&
            llvm::all_of(*defaulted, [](int64_t flag) { return flag == 0; });
        Operation *callee =
            supported ? unitSources.lookup(*declaration.getCalleeCodeUnitId())
                      : nullptr;
        unsigned formalCount = 0;
        if (callee)
          for (Operation *child : getChildren(callee))
            if (auto formal =
                    dyn_cast<semantic::SVFormalArgumentSymbolOp>(child)) {
              ++formalCount;
              supported &=
                  formal.getDirection() == semantic::SVArgumentDirection::In;
            }
        supported &= callee && formalCount == arguments.size();
        if (supported) {
          auto owner = sim::VPIObjectRefAttr::get(builder.getContext(), site);
          auto group = materializer.resolveGroup(
              arguments, owner, declaration.getVpiKind(),
              declaration.getScopeId(), uint32_t(Relation::ArgumentRel));
          if (failed(group))
            invalid = true;
          else if (*group)
            for (auto [ordinal, target] : llvm::enumerate(**group)) {
              auto location = getSemanticLocation(arguments[ordinal]);
              sim::SimVPIRelationDeclOp::create(
                  builder, location, owner, uint32_t(Relation::ArgumentRel),
                  sim::VPIRelationMode::Iterate, ordinal, target.reference);
              const auto *edge = reflection::findVPITraversal(
                  target.kind, uint32_t(Relation::UseRel), Mode::Iterate);
              if (!edge || !reflection::vpiObjectSetContains(
                               edge->targets, declaration.getVpiKind()))
                continue;
              auto &targets = uses[target.reference];
              if (llvm::is_contained(targets, owner))
                continue;
              sim::SimVPIRelationDeclOp::create(
                  builder, location, target.reference,
                  uint32_t(Relation::UseRel), sim::VPIRelationMode::Iterate,
                  targets.size(), owner);
              targets.push_back(owner);
            }
        }
      }
      auto identity = sim::get<sim::metadata::VpiStatementId>(source);
      if (!identity)
        return WalkResult::advance();
      uint64_t id = identity.getValue().getZExtValue();
      auto statement = statements.lookup(id);
      if (!statement || !visited.insert(id).second)
        return WalkResult::advance();
      auto sourceRef = sim::VPIObjectRefAttr::get(
          builder.getContext(), sim::VPIObjectRefKind::Statement, identity);
      auto emit = [&](Relation selector, Operation *expression) {
        auto resolved = materializer.resolve(
            expression, sourceRef, statement.getVpiKind(),
            statement.getScopeId(), static_cast<uint32_t>(selector));
        if (failed(resolved)) {
          invalid = true;
          return;
        }
        auto target = *resolved;
        const auto *edge = reflection::findVPITraversal(
            statement.getVpiKind(), static_cast<uint32_t>(selector),
            Mode::Handle);
        if (!target || !edge || edge->statementContainment ||
            edge->automaticRelation != reflection::VPIAutomaticRelation::None ||
            !reflection::vpiObjectSetContains(edge->targets, target->kind))
          return;
        sim::SimVPIRelationDeclOp::create(
            builder, getSemanticLocation(expression), sourceRef,
            static_cast<uint32_t>(selector), sim::VPIRelationMode::Handle, 0,
            target->reference);
        const auto *use = reflection::findVPITraversal(
            target->kind, static_cast<uint32_t>(Relation::UseRel),
            Mode::Iterate);
        if (!use || !reflection::vpiObjectSetContains(use->targets,
                                                      statement.getVpiKind()))
          return;
        auto &targets = uses[target->reference];
        if (llvm::is_contained(targets, sourceRef))
          return;
        sim::SimVPIRelationDeclOp::create(
            builder, getSemanticLocation(expression), target->reference,
            static_cast<uint32_t>(Relation::UseRel),
            sim::VPIRelationMode::Iterate, targets.size(), sourceRef);
        targets.push_back(sourceRef);
      };
      auto children = getChildren(source);
      if (auto caseStatement = dyn_cast<semantic::SVCaseStatementOp>(source)) {
        size_t next = 1;
        for (auto [itemOrdinal, count] :
             llvm::enumerate(caseStatement.getItemLabelCounts())) {
          auto found = caseItems.find({id, itemOrdinal});
          if (found == caseItems.end() || count < 0 ||
              next >= children.size() ||
              static_cast<uint64_t>(count) >= children.size() - next) {
            invalid = true;
            source->emitError(
                "case expression group has no exact retained item");
            return WalkResult::advance();
          }
          auto item = statements.lookup(found->second);
          auto owner = sim::VPIObjectRefAttr::get(
              builder.getContext(), sim::VPIObjectRefKind::Statement,
              builder.getI64IntegerAttr(found->second));
          auto labels = ArrayRef(children).slice(next, count);
          auto group = materializer.resolveGroup(
              labels, owner, item.getVpiKind(), item.getScopeId(),
              static_cast<uint32_t>(Relation::ExprRel));
          if (failed(group))
            invalid = true;
          else if (*group)
            for (auto [ordinal, target] : llvm::enumerate(**group)) {
              auto location = getSemanticLocation(labels[ordinal]);
              sim::SimVPIRelationDeclOp::create(
                  builder, location, owner,
                  static_cast<uint32_t>(Relation::ExprRel),
                  sim::VPIRelationMode::Iterate, ordinal, target.reference);
              const auto *use = reflection::findVPITraversal(
                  target.kind, static_cast<uint32_t>(Relation::UseRel),
                  Mode::Iterate);
              if (!use || !reflection::vpiObjectSetContains(
                              use->targets, statement.getVpiKind()))
                continue;
              auto &targets = uses[target.reference];
              if (llvm::is_contained(targets, sourceRef))
                continue;
              sim::SimVPIRelationDeclOp::create(
                  builder, location, target.reference,
                  static_cast<uint32_t>(Relation::UseRel),
                  sim::VPIRelationMode::Iterate, targets.size(), sourceRef);
              targets.push_back(sourceRef);
            }
          next += count + 1;
        }
      }
      if (statement.getVpiKind() ==
          static_cast<uint32_t>(reflection::VPIObjectKind::EventControl)) {
        Operation *control = source;
        if (isa<semantic::SVTimedStatementOp>(source) && children.size() == 2)
          control = children.front();
        emit(Relation::ConditionRel, control);
        return WalkResult::advance();
      }
      if (isa<semantic::SVExpressionStatementOp>(source) &&
          children.size() == 1 &&
          isa<semantic::SVAssignmentExpressionOp>(children.front())) {
        source = children.front();
        children = getChildren(source);
      }
      if (auto assignment =
              dyn_cast<semantic::SVAssignmentExpressionOp>(source)) {
        size_t prefix = assignment.getHasTimingControl() ? 1 : 0;
        if (children.size() == prefix + 2) {
          emit(Relation::LhsRel, children[prefix]);
          emit(Relation::RhsRel, children[prefix + 1]);
        }
      } else if (auto conditional =
                     dyn_cast<semantic::SVConditionalStatementOp>(source)) {
        if (conditional.getConditionCount() == 1 &&
            conditional.getConditionPatternFlags().front() == 0)
          emit(Relation::ConditionRel, children.front());
      } else if (isa<semantic::SVCaseStatementOp,
                     semantic::SVPatternCaseStatementOp,
                     semantic::SVWhileLoopStatementOp,
                     semantic::SVRepeatLoopStatementOp,
                     semantic::SVWaitStatementOp,
                     semantic::SVReturnStatementOp>(source)) {
        if (!children.empty())
          emit(Relation::ConditionRel, children.front());
      } else if (isa<semantic::SVDoWhileLoopStatementOp>(source)) {
        if (children.size() == 2)
          emit(Relation::ConditionRel, children.front());
      } else if (auto loop = dyn_cast<semantic::SVForLoopStatementOp>(source)) {
        if (loop.getHasCondition())
          emit(Relation::ConditionRel, children[loop.getInitializerCount()]);
      }
      return WalkResult::advance();
    });
  }
  return failure(invalid);
}
std::string getExplicitDelayedSignalPath(StringRef sourcePath) {
  return (Twine("__talos_negative_timing_explicit|") + sourcePath).str();
}

LogicalResult
synthesizeExplicitDelayedDrivers(semantic::SVRootSymbolOp root, Builder &builder,
                                 llvm::StringSet<> &delayedSources) {
  SmallVector<semantic::SVSystemTimingCheckSymbolOp> checks;
  int64_t nextNodeId = 0;
  root->walk([&](Operation *op) {
    if (auto id = op->getAttrOfType<IntegerAttr>("node_id"))
      nextNodeId = std::max(nextNodeId, id.getInt() + 1);
    if (auto check = dyn_cast<semantic::SVSystemTimingCheckSymbolOp>(op);
        check && check->hasAttr("talos.negative_timing_check") &&
        check->hasAttr("talos.delayed_signal_args"))
      checks.push_back(check);
  });
  auto cloneWithFreshNodes = [&](Operation *source) {
    Operation *copy = source->clone();
    copy->walk([&](Operation *nested) {
      if (nested->hasAttr("node_id"))
        nested->setAttr("node_id", builder.getI64IntegerAttr(nextNodeId++));
    });
    return copy;
  };
  unsigned nextDriver = 0;
  for (semantic::SVSystemTimingCheckSymbolOp check : checks) {
    auto children = check->getAttrOfType<DenseI64ArrayAttr>(
        "timing_check_arg_expression_children");
    SmallVector<Operation *> roots = getChildren(check);
    for (auto [original, delayed] : {std::pair{0u, 7u}, std::pair{1u, 8u}}) {
      if (!children || delayed >= children.size() || children[delayed] < 0)
        continue;
      Operation *source = roots[children[original]];
      while (isa<semantic::SVConversionExpressionOp>(source))
        source = getChildren(source).front();
      auto assignment =
          dyn_cast<semantic::SVAssignmentExpressionOp>(roots[children[delayed]]);
      SmallVector<Operation *> sides =
          assignment ? getChildren(assignment) : SmallVector<Operation *>{};
      auto path = source->getAttrOfType<StringAttr>("referenced_path");
      auto sourceType = source->getAttrOfType<TypeAttr>("semantic_type");
      auto targetType = sides.size() == 2 ? sides.front()->getAttrOfType<TypeAttr>(
                                                "semantic_type")
                                          : TypeAttr{};
      if (!path || !sourceType || !targetType ||
          getSemanticPackedWidth(sourceType.getValue()) !=
              getSemanticPackedWidth(targetType.getValue()) ||
          !getSemanticPackedWidth(sourceType.getValue()))
        return emitError(getSemanticLocation(check))
               << "IEEE 1800-2023 31.9.1 delayed signal must have the width of "
                  "the signal it delays, which must be named directly";
      delayedSources.insert(path.getValue());
      // The driver reads a descriptor that preparation binds to the delayed
      // copy of the source once the delays are solved.
      Operation *driven = cloneWithFreshNodes(assignment);
      SmallVector<Operation *> drivenSides = getChildren(driven);
      Operation *read = cloneWithFreshNodes(source);
      read->setAttr("referenced_path", builder.getStringAttr(
                                           getExplicitDelayedSignalPath(
                                               path.getValue())));
      drivenSides[1]->getBlock()->getOperations().insert(
          drivenSides[1]->getIterator(), read);
      drivenSides[1]->erase();
      OperationState state(check.getLoc(),
                           semantic::SVContinuousAssignSymbolOp::getOperationName());
      for (NamedAttribute attribute : check->getAttrs()) {
        StringRef name = attribute.getName().getValue();
        if (name == "hierarchical_name" || name == "original_source_range" ||
            name.starts_with("source_"))
          state.addAttribute(attribute.getName(), attribute.getValue());
      }
      state.addAttribute(
          SymbolTable::getSymbolAttrName(),
          builder.getStringAttr((Twine("__talos_delayed_signal_driver_") +
                                 Twine(nextDriver++))
                                    .str()));
      state.addAttribute("node_id", builder.getI64IntegerAttr(nextNodeId++));
      Block *body = new Block();
      state.addRegion()->push_back(body);
      body->push_back(driven);
      check->getBlock()->getOperations().insertAfter(check->getIterator(),
                                                     Operation::create(state));
    }
    check->removeAttr("talos.delayed_signal_args");
  }
  return success();
}

/// The event control of the clock in force at `operation` inside `assertion`:
/// an enclosing clocking of the property, then the procedural context, then the
/// default clocking (IEEE 1800-2023 16.13.3).
static Operation *
findAssertionClockFlow(Operation *operation,
                       semantic::SVConcurrentAssertionStatementOp assertion) {
  for (Operation *cursor = operation; cursor && cursor != assertion.getOperation();
       cursor = cursor->getParentOp())
    if (isa<semantic::SVClockingAssertionExprOp>(cursor))
      return getChildren(cursor).front();
  SmallVector<Operation *> children = getChildren(assertion);
  size_t prefix = 0;
  if (assertion.getHasDefaultDisable() && prefix < children.size())
    ++prefix;
  if (assertion.getHasContextualClock().value_or(false) &&
      prefix < children.size())
    return children[prefix];
  if (assertion.getDefaultClockingSymbolAttr() && prefix < children.size())
    return children[prefix];
  return nullptr;
}

/// Whether two event controls name the same event.
static bool sameClockEvent(Operation *left, Operation *right) {
  if (left->getName() != right->getName())
    return false;
  for (StringRef name :
       {"referenced_path", "edge_kind", "has_iff", "operator_kind",
        "constant_value", "callee_name", "selection_kind"})
    if (left->getAttr(name) != right->getAttr(name))
      return false;
  SmallVector<Operation *> leftChildren = getChildren(left);
  SmallVector<Operation *> rightChildren = getChildren(right);
  if (leftChildren.size() != rightChildren.size())
    return false;
  for (auto [leftChild, rightChild] :
       llvm::zip_equal(leftChildren, rightChildren))
    if (!sameClockEvent(leftChild, rightChild))
      return false;
  return true;
}

/// The number of children of a concurrent assertion ahead of its property.
static size_t
assertionPropertyIndex(semantic::SVConcurrentAssertionStatementOp assertion) {
  return static_cast<size_t>(assertion.getHasDefaultDisable()) +
         static_cast<size_t>(
             assertion.getHasContextualClock().value_or(false)) +
         static_cast<size_t>(
             static_cast<bool>(assertion.getDefaultClockingSymbolAttr()));
}

/// The event expression a procedure infers as the clock of its assertions
/// (IEEE 1800-2023 16.14.6), or null for the default clocking to apply. Terms
/// are compared by variable, not by the bits they select.
static Operation *
inferProcedureClock(semantic::SVProceduralBlockSymbolOp procedure,
                    semantic::SVTimedStatementOp timed) {
  // a), b): exactly one event control, and no blocking timing control.
  bool anotherControl =
      procedure
          ->walk([&](Operation *nested) {
            return nested != timed.getOperation() &&
                           isa<semantic::SVTimedStatementOp,
                               semantic::SVWaitStatementOp,
                               semantic::SVWaitOrderStatementOp,
                               semantic::SVWaitForkStatementOp>(nested)
                       ? WalkResult::interrupt()
                       : WalkResult::advance();
          })
          .wasInterrupted();
  if (anotherControl)
    return nullptr;
  Operation *control = getChildren(timed).front();
  SmallVector<Operation *> events;
  if (isa<semantic::SVEventListControlOp>(control))
    events = getChildren(control);
  else if (isa<semantic::SVSignalEventControlOp>(control))
    events.push_back(control);
  // c) 2): what the body uses, other than as a clocking event or within
  // assertion statements.
  llvm::StringSet<> used;
  procedure->walk<WalkOrder::PreOrder>([&](Operation *nested) {
    if (nested == control ||
        isa<semantic::SVConcurrentAssertionStatementOp,
            semantic::SVImmediateAssertionStatementOp>(nested))
      return WalkResult::skip();
    if (auto path = nested->getAttrOfType<StringAttr>("referenced_path"))
      used.insert(path.getValue());
    return WalkResult::advance();
  });
  // c): the one event expression of the allowed forms.
  Operation *inferred = nullptr;
  for (Operation *event : events) {
    auto signal = dyn_cast<semantic::SVSignalEventControlOp>(event);
    SmallVector<Operation *> operands =
        signal ? getChildren(signal) : SmallVector<Operation *>{};
    if (operands.empty())
      continue;
    Operation *expression = operands.front();
    bool isUsed = expression
                      ->walk([&](Operation *term) {
                        auto path =
                            term->getAttrOfType<StringAttr>("referenced_path");
                        return path && used.contains(path.getValue())
                                   ? WalkResult::interrupt()
                                   : WalkResult::advance();
                      })
                      .wasInterrupted();
    bool allowed = false;
    if (signal.getEdgeKind() != semantic::EdgeKind::Change) {
      allowed = !isUsed;
    } else if (!signal.getHasIff()) {
      auto type = expression->getAttrOfType<TypeAttr>("semantic_type");
      allowed = expression->hasAttr("clocking_block_event") ||
                (type && isa<semantic::EventType>(type.getValue()) && !isUsed);
    }
    if (!allowed)
      continue;
    if (inferred)
      return nullptr;
    inferred = event;
  }
  return inferred;
}

/// The procedural checker statements of the design with the instance bodies
/// they name, and a node id above all those in use.
struct ProceduralCheckerSites {
  SmallVector<semantic::SVProceduralCheckerStatementOp> statements;
  llvm::StringMap<semantic::SVCheckerInstanceBodySymbolOp> bodies;
  int64_t nextNodeId = 0;
};

static ProceduralCheckerSites
collectProceduralCheckerSites(semantic::SVRootSymbolOp root) {
  ProceduralCheckerSites sites;
  root->walk([&](Operation *op) {
    if (auto id = op->getAttrOfType<IntegerAttr>("node_id"))
      sites.nextNodeId = std::max(sites.nextNodeId, id.getInt() + 1);
    if (auto statement = dyn_cast<semantic::SVProceduralCheckerStatementOp>(op))
      sites.statements.push_back(statement);
    else if (auto body = dyn_cast<semantic::SVCheckerInstanceBodySymbolOp>(op);
             body && body.getIsProcedural())
      sites.bodies[*body.getHierarchicalName()] = body;
  });
  return sites;
}

void bindProceduralCheckerClocks(semantic::SVRootSymbolOp root,
                                 Builder &builder) {
  ProceduralCheckerSites sites = collectProceduralCheckerSites(root);
  auto bindClock = [&](semantic::SVConcurrentAssertionStatementOp assertion,
                       Operation *source) {
    Operation *clock = source->clone();
    clock->walk([&](Operation *nested) {
      if (nested->hasAttr("node_id"))
        nested->setAttr("node_id",
                        builder.getI64IntegerAttr(sites.nextNodeId++));
    });
    // After a default disable, ahead of any default clocking.
    Block &children = assertion->getRegion(0).front();
    auto position = children.begin();
    if (assertion.getHasDefaultDisable())
      ++position;
    children.getOperations().insert(position, clock);
    assertion->setAttr("has_contextual_clock", builder.getBoolAttr(true));
  };
  for (semantic::SVProceduralCheckerStatementOp statement : sites.statements) {
    SmallVector<Operation *> clocks = getChildren(statement);
    for (StringRef path :
         statement.getInstancePaths().getAsValueRange<StringAttr>()) {
      auto body = sites.bodies.find(path);
      if (body == sites.bodies.end())
        continue;
      body->second->walk([&](semantic::SVProceduralBlockSymbolOp procedure) {
        // An assertion in a procedure of the checker is procedural already,
        // with the context of that procedure (17.3). The frontend's analysis of
        // procedures does not reach into a procedural scope, so it is recorded
        // here. Any other assertion takes the context of the instantiation.
        Operation *clock = clocks.empty() ? nullptr : clocks.front();
        // The event control of a procedure of the checker.
        Operation *sensitivity = nullptr;
        bool ownProcedure = !procedure->hasAttr("is_from_assertion");
        if (ownProcedure) {
          SmallVector<Operation *> statements = getChildren(procedure);
          auto timed =
              statements.empty()
                  ? semantic::SVTimedStatementOp{}
                  : dyn_cast<semantic::SVTimedStatementOp>(statements.front());
          clock = timed ? getChildren(timed).front() : nullptr;
          // A formal defaulted to $inferred_clock names the instantiation's
          // clock here too (16.14.7, 17.4).
          SmallVector<Operation *> events =
              clock ? getChildren(clock) : SmallVector<Operation *>{};
          auto query =
              events.empty()
                  ? semantic::SVCallExpressionOp{}
                  : dyn_cast<semantic::SVCallExpressionOp>(events.front());
          if (query && query.getIsSystemCall() &&
              query.getCalleeName() == "$inferred_clock" && !clocks.empty()) {
            Operation *resolved = clocks.front()->clone();
            resolved->walk([&](Operation *nested) {
              if (nested->hasAttr("node_id"))
                nested->setAttr("node_id",
                                builder.getI64IntegerAttr(sites.nextNodeId++));
            });
            clock->getBlock()->getOperations().insert(clock->getIterator(),
                                                      resolved);
            clock->erase();
            clock = resolved;
          }
          sensitivity = clock;
          clock = timed ? inferProcedureClock(procedure, timed) : nullptr;
        }
        procedure->walk(
            [&](semantic::SVConcurrentAssertionStatementOp assertion) {
              if (assertion.getHasContextualClock().value_or(false))
                return;
              if (clock)
                bindClock(assertion, clock);
              if (!ownProcedure)
                return;
              assertion->setAttr("is_procedural", builder.getBoolAttr(true));
              SmallVector<Operation *> children = getChildren(assertion);
              size_t index = assertionPropertyIndex(assertion);
              if (!clock || !sameClockEvent(sensitivity, clock) ||
                  index >= children.size())
                return;
              Operation *leading =
                  findAssertionClockFlow(children[index], assertion);
              if (leading && sameClockEvent(leading, clock))
                assertion->setAttr("starts_on_current_clock",
                                   builder.getBoolAttr(true));
            });
      });
    }
  }
}

void synthesizeProceduralCheckers(semantic::SVRootSymbolOp root,
                                  llvm::StringMap<Operation *> &symbols,
                                  Builder &builder) {
  ProceduralCheckerSites sites = collectProceduralCheckerSites(root);
  for (semantic::SVProceduralCheckerStatementOp statement : sites.statements) {
    OperationState state(statement.getLoc(),
                         semantic::SVStatementListOp::getOperationName());
    state.addAttribute("node_id",
                       builder.getI64IntegerAttr(sites.nextNodeId++));
    Block *list = new Block();
    state.addRegion()->push_back(list);
    SmallVector<Operation *> clocks = getChildren(statement);
    for (StringRef path :
         statement.getInstancePaths().getAsValueRange<StringAttr>()) {
      auto body = sites.bodies.find(path);
      if (body == sites.bodies.end())
        continue;
      // A child checker's static assertions are treated as if instantiated in
      // this one, so they move here too.
      SmallVector<semantic::SVProceduralBlockSymbolOp> assertions;
      body->second->walk([&](semantic::SVProceduralBlockSymbolOp procedure) {
        if (procedure->hasAttr("is_from_assertion"))
          assertions.push_back(procedure);
      });
      for (semantic::SVProceduralBlockSymbolOp procedure : assertions) {
        Operation *moved = getChildren(procedure).front();
        moved->walk([&](semantic::SVConcurrentAssertionStatementOp assertion) {
          assertion->setAttr("is_procedural", builder.getBoolAttr(true));
          // 16.14.6.2: an assertion on the clock that resumed its process
          // starts on this tick. The clock here is the one bound above, unless
          // the assertion's own leading clock differs.
          if (!statement->hasAttr("starts_on_current_clock") || clocks.empty())
            return;
          SmallVector<Operation *> children = getChildren(assertion);
          size_t index = assertionPropertyIndex(assertion);
          if (index >= children.size())
            return;
          Operation *leading =
              findAssertionClockFlow(children[index], assertion);
          if (leading && sameClockEvent(leading, clocks.front()))
            assertion->setAttr("starts_on_current_clock",
                               builder.getBoolAttr(true));
        });
        moved->moveBefore(list, list->end());
        if (std::optional<StringRef> name = procedure.getSymName())
          symbols.erase(*name);
        procedure.erase();
      }
    }
    OpBuilder replacement(statement);
    replacement.insert(Operation::create(state));
    statement.erase();
  }
}

LogicalResult synthesizeFreeCheckerVariables(semantic::SVRootSymbolOp root,
                                             Builder &builder) {
  SmallVector<semantic::SVCheckerInstanceBodySymbolOp> bodies;
  int64_t nextNodeId = 0;
  root->walk([&](Operation *op) {
    if (auto id = op->getAttrOfType<IntegerAttr>("node_id"))
      nextNodeId = std::max(nextNodeId, id.getInt() + 1);
    if (auto body = dyn_cast<semantic::SVCheckerInstanceBodySymbolOp>(op))
      bodies.push_back(body);
  });
  auto cloneWithFreshNodes = [&](Operation *source) {
    Operation *copy = source->clone();
    copy->walk([&](Operation *nested) {
      if (nested->hasAttr("node_id"))
        nested->setAttr("node_id", builder.getI64IntegerAttr(nextNodeId++));
    });
    return copy;
  };
  MLIRContext *context = root.getContext();
  auto makeCall = [&](Location location, StringRef name, Type type,
                      ArrayRef<Operation *> children) {
    OperationState state(location,
                         semantic::SVCallExpressionOp::getOperationName());
    state.addAttribute("argument_count",
                       builder.getI64IntegerAttr(children.size()));
    state.addAttribute("callee_name", builder.getStringAttr(name));
    state.addAttribute("constraint_restrictions", builder.getArrayAttr({}));
    state.addAttribute(
        "defaulted_arguments",
        builder.getDenseI64ArrayAttr(SmallVector<int64_t>(children.size(), 0)));
    for (StringRef flag : {"has_inline_constraints", "has_iterator_expression",
                           "has_output_arguments", "has_this_class",
                           "is_signed", "is_super_class"})
      state.addAttribute(flag, builder.getBoolAttr(false));
    state.addAttribute("is_system_call", builder.getBoolAttr(true));
    state.addAttribute("node_id", builder.getI64IntegerAttr(nextNodeId++));
    state.addAttribute("semantic_type", TypeAttr::get(type));
    state.addAttribute("subroutine_kind",
                       builder.getI32IntegerAttr(static_cast<int32_t>(
                           semantic::SVSubroutineKind::Task)));
    Block *body = new Block();
    state.addRegion()->push_back(body);
    for (Operation *child : children)
      body->push_back(child);
    return Operation::create(state);
  };
  auto makeNode = [&](Location location, StringRef name,
                      ArrayRef<NamedAttribute> attributes,
                      ArrayRef<Operation *> children) {
    OperationState state(location, name);
    state.addAttribute("node_id", builder.getI64IntegerAttr(nextNodeId++));
    state.addAttributes(attributes);
    Block *body = new Block();
    state.addRegion()->push_back(body);
    for (Operation *child : children)
      body->push_back(child);
    return Operation::create(state);
  };

  // Activity belongs to the variable, wherever it is assigned or read: an
  // assume statement of a child checker can read a variable of its parent
  // through a formal's actual argument (17.7.2).
  llvm::StringSet<> assigned;
  std::function<void(Operation *)> collectTargets = [&](Operation *target) {
    if (auto path = target->getAttrOfType<StringAttr>("referenced_path")) {
      assigned.insert(path.getValue());
      return;
    }
    SmallVector<Operation *> nested = getChildren(target);
    if (isa<semantic::SVConcatenationExpressionOp,
            semantic::SVStreamingConcatenationExpressionOp>(target)) {
      for (Operation *part : nested)
        collectTargets(part);
    } else if (!nested.empty()) {
      collectTargets(nested.front());
    }
  };
  for (semantic::SVCheckerInstanceBodySymbolOp body : bodies)
    body->walk([&](semantic::SVAssignmentExpressionOp assignment) {
      SmallVector<Operation *> sides = getChildren(assignment);
      if (!sides.empty())
        collectTargets(sides.front());
    });
  // "All free checker variables ... are initialized with unconstrained random
  // values unless explicitly initialized in their declaration"; those that are
  // not const and not on the left-hand side of an assignment are active.
  llvm::StringSet<> active;
  llvm::StringSet<> initialized;
  DenseMap<Operation *, SmallVector<StringRef>> bodyActive;
  for (semantic::SVCheckerInstanceBodySymbolOp body : bodies)
    for (Operation *member : getChildren(body)) {
      auto variable = dyn_cast<semantic::SVVariableSymbolOp>(member);
      if (!variable || !variable.getIsCheckerFreeVariable())
        continue;
      StringRef path =
          variable->getAttrOfType<StringAttr>("hierarchical_name").getValue();
      if (getChildren(variable).empty()) {
        Region &initializer = variable->getRegion(0);
        if (initializer.empty())
          initializer.emplaceBlock();
        initializer.front().push_back(makeCall(
            variable.getLoc(), "$talos_free_random",
            variable->getAttrOfType<TypeAttr>("semantic_type").getValue(), {}));
      } else {
        initialized.insert(path);
      }
      if (!assigned.contains(path) && !variable->hasAttr("is_const") &&
          active.insert(path).second)
        bodyActive[body].push_back(path);
    }
  if (active.empty())
    return success();
  // An actual argument of a procedural checker instance can read one, and a
  // solve has no process with its value.
  llvm::StringSet<> automaticVariables;
  root->walk([&](semantic::SVVariableSymbolOp variable) {
    if (variable.getLifetime() == semantic::SVVariableLifetime::Automatic)
      if (std::optional<StringRef> path = variable.getHierarchicalName())
        automaticVariables.insert(*path);
  });

  // "A sampled value of an active checker variable is defined as its current
  // value", so what a solve chooses is what assertions read.
  llvm::StringMap<Operation *> activeReads;
  for (semantic::SVCheckerInstanceBodySymbolOp body : bodies)
    body->walk([&](semantic::SVNamedValueExpressionOp read) {
      if (active.contains(read.getReferencedPath())) {
        read->setAttr("talos.current_sampled_value", builder.getUnitAttr());
        activeReads.try_emplace(read.getReferencedPath(), read);
      }
    });

  // Formals of a property instance and local variables have no value outside
  // the assertion, and the constraint language has no sampled value functions,
  // and the runtime solver no X or Z constants, so only plain operators over
  // design state reach the solver.
  auto solvable = [](Operation *expression) {
    return !expression
                ->walk([](Operation *nested) {
                  bool supported =
                      isa<semantic::SVNamedValueExpressionOp,
                          semantic::SVHierarchicalValueExpressionOp,
                          semantic::SVIntegerLiteralOp,
                          semantic::SVUnbasedUnsizedIntegerLiteralOp,
                          semantic::SVUnaryExpressionOp,
                          semantic::SVBinaryExpressionOp,
                          semantic::SVConditionalExpressionOp,
                          semantic::SVInsideExpressionOp,
                          semantic::SVConcatenationExpressionOp,
                          semantic::SVReplicationExpressionOp,
                          semantic::SVElementSelectExpressionOp,
                          semantic::SVRangeSelectExpressionOp,
                          semantic::SVMemberAccessExpressionOp,
                          semantic::SVConversionExpressionOp,
                          semantic::SVValueRangeExpressionOp>(nested);
                  if (std::optional<StringRef> spelling =
                          getConstantSpelling(nested);
                      spelling &&
                      spelling->find_first_of("xXzZ?") != StringRef::npos)
                    supported = false;
                  if (isa<semantic::SVInsideExpressionOp>(nested))
                    for (Operation *operand : getChildren(nested)) {
                      auto type =
                          operand->getAttrOfType<TypeAttr>("semantic_type");
                      auto aggregate =
                          type ? dyn_cast<semantic::SourceAggregateType>(
                                     type.getValue())
                               : semantic::SourceAggregateType{};
                      if (type && (isa<semantic::RangedUnpackedArrayType,
                                       semantic::QueueType>(type.getValue()) ||
                                   (aggregate && !aggregate.getIsPacked())))
                        supported = false;
                    }
                  return supported ? WalkResult::advance()
                                   : WalkResult::interrupt();
                })
                .wasInterrupted();
  };
  auto booleanOf = [&](Operation *operation) -> Operation * {
    while (true) {
      if (auto instance =
              dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation)) {
        if (!instance.getHasExpandedBody() ||
            instance.getArgumentCount() != 0 ||
            instance.getLocalVariableCount() != 0)
          return nullptr;
        operation = getChildren(instance).front();
        continue;
      }
      auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(operation);
      if (!simple || simple.getHasRepetition())
        return nullptr;
      SmallVector<Operation *> children = getChildren(simple);
      if (children.size() != 1)
        return nullptr;
      if (isa<semantic::SVAssertionInstanceExpressionOp>(children.front())) {
        operation = children.front();
        continue;
      }
      return solvable(children.front()) ? children.front() : nullptr;
    }
  };

  unsigned nextSolve = 0;
  for (semantic::SVCheckerInstanceBodySymbolOp body : bodies) {
    auto own = bodyActive.find(body);
    if (own == bodyActive.end())
      continue;
    llvm::StringSet<> ownActive;
    for (StringRef path : own->second)
      ownActive.insert(path);

    // The candidates for the assume set: assume statements of this checker and
    // its children without a const cast or automatic value among the actual
    // arguments. Any other form is still checked, as there is "no requirement
    // that a solution be found if it exists".
    struct Constraint {
      Operation *antecedent;
      Operation *consequent;
      bool previousTick;
      // A disable iff condition turns the constraint off while it holds
      // (16.12).
      SmallVector<Operation *> disables;
    };
    struct ClockGroup {
      Operation *clock;
      SmallVector<Constraint> constraints;
      // What the assumptions the solver cannot read refer to.
      llvm::StringSet<> checkedOnly;
    };
    SmallVector<ClockGroup> groups;
    body->walk([&](semantic::SVConcurrentAssertionStatementOp assertion) {
      if (assertion.getAssertionKind() != semantic::SVAssertionKind::Assume)
        return;
      bool constCast = false;
      assertion->walk([&](Operation *nested) {
        if (auto cast = nested->getAttrOfType<BoolAttr>("is_const_cast");
            cast && cast.getValue())
          constCast = true;
        auto read = dyn_cast<semantic::SVNamedValueExpressionOp>(nested);
        if (read && automaticVariables.contains(read.getReferencedPath()))
          constCast = true;
      });
      if (constCast)
        return;
      SmallVector<Operation *> children = getChildren(assertion);
      size_t index = assertionPropertyIndex(assertion);
      if (index >= children.size())
        return;
      SmallVector<Operation *> disables;
      if (assertion.getHasDefaultDisable())
        disables.push_back(children.front());
      Operation *property = children[index];
      while (true) {
        if (auto instance =
                dyn_cast<semantic::SVAssertionInstanceExpressionOp>(property)) {
          if (!instance.getHasExpandedBody() ||
              instance.getArgumentCount() != 0 ||
              instance.getLocalVariableCount() != 0)
            break;
          property = getChildren(instance).front();
        } else if (isa<semantic::SVClockingAssertionExprOp>(property)) {
          property = getChildren(property).back();
        } else if (isa<semantic::SVDisableIffAssertionExprOp>(property)) {
          disables.push_back(getChildren(property).front());
          property = getChildren(property).back();
        } else if (auto simple =
                       dyn_cast<semantic::SVSimpleAssertionExprOp>(property);
                   simple && !simple.getHasRepetition() &&
                   getChildren(simple).size() == 1 &&
                   isa<semantic::SVAssertionInstanceExpressionOp>(
                       getChildren(simple).front())) {
          property = getChildren(simple).front();
        } else {
          break;
        }
      }
      if (!llvm::all_of(disables, solvable))
        return;
      Operation *clock = findAssertionClockFlow(property, assertion);
      if (!clock)
        return;
      ClockGroup *group = nullptr;
      for (ClockGroup &candidate : groups)
        if (sameClockEvent(candidate.clock, clock))
          group = &candidate;
      if (!group) {
        groups.push_back({clock, {}});
        group = &groups.back();
      }
      if (Operation *boolean = booleanOf(property)) {
        group->constraints.push_back({nullptr, boolean, false, disables});
      } else if (auto binary =
                     dyn_cast<semantic::SVBinaryAssertionExprOp>(property)) {
        SmallVector<Operation *> operands = getChildren(binary);
        bool overlapped =
            binary.getOperatorKind() ==
            semantic::SVAssertionBinaryOperator::OverlappedImplication;
        bool nonoverlapped =
            binary.getOperatorKind() ==
            semantic::SVAssertionBinaryOperator::NonOverlappedImplication;
        Operation *antecedent =
            operands.size() == 2 ? booleanOf(operands.front()) : nullptr;
        Operation *consequent =
            operands.size() == 2 ? booleanOf(operands.back()) : nullptr;
        if ((overlapped || nonoverlapped) && antecedent && consequent) {
          group->constraints.push_back(
              {antecedent, consequent, nonoverlapped, disables});
          return;
        }
        property->walk([&](semantic::SVNamedValueExpressionOp read) {
          group->checkedOnly.insert(read.getReferencedPath());
        });
      } else {
        property->walk([&](semantic::SVNamedValueExpressionOp read) {
          group->checkedOnly.insert(read.getReferencedPath());
        });
      }
    });

    // The solve runs from the enclosing module, ahead of the checker's Reactive
    // processes and of the Observed region (17.7.2, 17.7.3).
    auto owner = body->getParentOfType<semantic::SVInstanceBodySymbolOp>();
    if (!owner) {
      emitError(getSemanticLocation(body))
          << "IEEE 1800-2023 17.7.2 free checker variables need an enclosing "
             "instance";
      return failure();
    }
    std::string descendants = (*body.getHierarchicalName() + ".").str();
    for (ClockGroup &group : groups) {
      // The assume set of this solve: what reads a variable it solves, where a
      // variable of a child checker read by such an assumption is solved
      // jointly. Every assumption on that variable has to be among them, or
      // this solve would break the ones it does not see. A parent's variable is
      // an input here: the parent solves it with the assumptions this checker
      // does not see.
      llvm::StringSet<> solved = ownActive;
      SmallVector<Constraint *> selected;
      llvm::SmallPtrSet<Constraint *, 8> included;
      auto forEachRead = [](Constraint &constraint,
                            function_ref<void(StringRef)> callback) {
        auto visit = [&](Operation *side) {
          side->walk([&](semantic::SVNamedValueExpressionOp read) {
            callback(read.getReferencedPath());
          });
        };
        if (constraint.antecedent)
          visit(constraint.antecedent);
        visit(constraint.consequent);
        for (Operation *disable : constraint.disables)
          visit(disable);
      };
      for (bool grew = true; grew;) {
        grew = false;
        for (Constraint &constraint : group.constraints) {
          if (included.contains(&constraint))
            continue;
          bool reads = false;
          forEachRead(constraint,
                      [&](StringRef path) { reads |= solved.contains(path); });
          if (!reads)
            continue;
          included.insert(&constraint);
          grew = true;
          forEachRead(constraint, [&](StringRef path) {
            if (active.contains(path) && path.starts_with(descendants))
              solved.insert(path);
          });
        }
      }
      for (Constraint &constraint : group.constraints)
        if (included.contains(&constraint))
          selected.push_back(&constraint);
      if (selected.empty())
        continue;
      Location location = group.clock->getLoc();
      unsigned solveIndex = nextSolve++;
      // A clocking block's event fires in the Observed region, where its inputs
      // are sampled (14.13), too late for a solve: wait on its event expression
      // instead.
      Operation *clock = cloneWithFreshNodes(group.clock);
      SmallVector<Operation *> clockChildren = getChildren(clock);
      if (auto signal = dyn_cast<semantic::SVSignalEventControlOp>(clock);
          signal && clockChildren.size() == 1 &&
          clockChildren.front()->hasAttr("clocking_block_event")) {
        auto reference =
            clockChildren.front()->getAttrOfType<StringAttr>("referenced_path");
        Operation *event = nullptr;
        if (reference)
          root->walk([&](semantic::SVClockingBlockSymbolOp block) {
            if (block.getHierarchicalName() != reference.getValue())
              return WalkResult::advance();
            event = getChildren(block).front();
            return WalkResult::interrupt();
          });
        if (event) {
          clock->erase();
          clock = cloneWithFreshNodes(event);
        }
      }
      // std::randomize(v...) with {c; a -> c; prior -> c;}, then prior = a: `a
      // |=> c` constrains this tick only if `a` held at the previous one, in an
      // attempt that was not disabled there.
      // A variable only assumptions the solver cannot read constrain "may be
      // updated", and keeping it holds them more often than a random draw
      // would.
      llvm::MapVector<StringRef, Operation *> targets;
      for (StringRef path : own->second)
        if (Operation *read = activeReads.lookup(path);
            read && !group.checkedOnly.contains(path))
          targets.try_emplace(path, read);
      Type oneBit = semantic::IntegralType::get(
          context, 1, false, true, 0, 0, semantic::SVIntegralFlavor::Logic);
      auto expressionAttributes = [&](Type type) {
        return SmallVector<NamedAttribute>{
            builder.getNamedAttr("is_signed", builder.getBoolAttr(false)),
            builder.getNamedAttr("semantic_type", TypeAttr::get(type))};
      };
      // Evaluated with current values, as a disable condition is (16.12).
      auto enabled = [&](ArrayRef<Operation *> disables, unsigned index) {
        Operation *condition = cloneWithFreshNodes(disables[index]);
        condition->walk([&](Operation *read) {
          if (isa<semantic::SVNamedValueExpressionOp>(read))
            read->setAttr("talos.current_sampled_value", builder.getUnitAttr());
        });
        SmallVector<NamedAttribute> attributes = expressionAttributes(oneBit);
        attributes.push_back(builder.getNamedAttr(
            "operator_kind", builder.getI32IntegerAttr(static_cast<int32_t>(
                                 semantic::SVUnaryOperator::LogicalNot))));
        return makeNode(location,
                        semantic::SVUnaryExpressionOp::getOperationName(),
                        attributes, {condition});
      };
      SmallVector<Operation *> items;
      SmallVector<Operation *> updates;
      for (auto [index, constraintPointer] : llvm::enumerate(selected)) {
        Constraint &constraint = *constraintPointer;
        forEachRead(constraint, [&](StringRef path) {
          if (solved.contains(path) && !targets.contains(path))
            if (Operation *read = activeReads.lookup(path))
              targets.try_emplace(path, read);
        });
        Operation *item = makeNode(
            location, semantic::SVExpressionConstraintOp::getOperationName(),
            {builder.getNamedAttr("is_soft", builder.getBoolAttr(false))},
            {cloneWithFreshNodes(constraint.consequent)});
        if (constraint.antecedent) {
          Operation *guard = cloneWithFreshNodes(constraint.antecedent);
          if (constraint.previousTick) {
            // Process-local state, bound by the lowering of
            // `$talos_free_solve`: it is no object of the design, so no dump or
            // VPI scan may list it.
            Type type =
                cast<TypeAttr>(constraint.antecedent->getAttr("semantic_type"))
                    .getValue();
            Operation *attempt = guard;
            for (unsigned disable = 0; disable < constraint.disables.size();
                 ++disable) {
              SmallVector<NamedAttribute> attributes =
                  expressionAttributes(oneBit);
              attributes.push_back(builder.getNamedAttr(
                  "operator_kind",
                  builder.getI32IntegerAttr(static_cast<int32_t>(
                      semantic::SVBinaryOperator::LogicalAnd))));
              attempt = makeNode(
                  location, semantic::SVBinaryExpressionOp::getOperationName(),
                  attributes, {enabled(constraint.disables, disable), attempt});
              type = oneBit;
            }
            std::string path = (Twine("$talos_free_prior.") +
                                Twine(solveIndex) + "." + Twine(index))
                                   .str();
            auto makePriorRead = [&]() {
              SmallVector<NamedAttribute> attributes =
                  expressionAttributes(type);
              attributes.push_back(builder.getNamedAttr(
                  "referenced_path", builder.getStringAttr(path)));
              attributes.push_back(builder.getNamedAttr(
                  "referenced_symbol", FlatSymbolRefAttr::get(context, path)));
              return makeNode(
                  location,
                  semantic::SVNamedValueExpressionOp::getOperationName(),
                  attributes, {});
            };
            SmallVector<NamedAttribute> attributes = expressionAttributes(type);
            attributes.push_back(builder.getNamedAttr(
                "assignment_kind", builder.getI32IntegerAttr(0)));
            updates.push_back(
                makeNode(location,
                         semantic::SVAssignmentExpressionOp::getOperationName(),
                         attributes, {makePriorRead(), attempt}));
            guard = makePriorRead();
          }
          item = makeNode(
              location, semantic::SVImplicationConstraintOp::getOperationName(),
              {}, {guard, item});
        }
        for (unsigned disable = 0; disable < constraint.disables.size();
             ++disable)
          item = makeNode(
              location, semantic::SVImplicationConstraintOp::getOperationName(),
              {}, {enabled(constraint.disables, disable), item});
        items.push_back(item);
      }
      auto makeRandomize = [&](ArrayRef<Operation *> selected,
                               ArrayRef<Operation *> constraints) {
        SmallVector<Operation *> randomizeChildren{makeNode(
            location, semantic::SVConstraintListOp::getOperationName(),
            {builder.getNamedAttr(
                "item_count", builder.getI64IntegerAttr(constraints.size()))},
            constraints)};
        for (Operation *read : selected) {
          Operation *target = cloneWithFreshNodes(read);
          Attribute type = target->getAttr("semantic_type");
          randomizeChildren.push_back(makeNode(
              location, semantic::SVAssignmentExpressionOp::getOperationName(),
              {builder.getNamedAttr("assignment_kind",
                                    builder.getI32IntegerAttr(0)),
               builder.getNamedAttr("is_signed", builder.getBoolAttr(false)),
               builder.getNamedAttr("semantic_type", type)},
              {target,
               makeNode(
                   location,
                   semantic::SVEmptyArgumentExpressionOp::getOperationName(),
                   {builder.getNamedAttr("is_signed",
                                         builder.getBoolAttr(false)),
                    builder.getNamedAttr("semantic_type", type)},
                   {})}));
        }
        Operation *randomize = makeCall(
            location, "randomize",
            semantic::IntegralType::get(context, 32, true, false, 31, 0,
                                        semantic::SVIntegralFlavor::Int),
            randomizeChildren);
        randomize->setAttr("argument_count",
                           builder.getI64IntegerAttr(selected.size()));
        randomize->setAttr("defaulted_arguments",
                           builder.getDenseI64ArrayAttr(
                               SmallVector<int64_t>(selected.size(), 0)));
        randomize->setAttr("has_inline_constraints", builder.getBoolAttr(true));
        randomize->setAttr("subroutine_kind", builder.getI32IntegerAttr(0));
        return randomize;
      };
      // 17.7: an initialized variable has the value of its initialization in
      // the first time step, and a later one is free to change it. There it is
      // an input to the solve of the others.
      SmallVector<Operation *> allTargets;
      SmallVector<Operation *> firstStepTargets;
      for (const auto &entry : targets) {
        allTargets.push_back(entry.second);
        if (!initialized.contains(entry.first))
          firstStepTargets.push_back(entry.second);
      }
      bool holdsFirstStep = firstStepTargets.size() != allTargets.size();
      SmallVector<Operation *> arguments;
      if (holdsFirstStep && !firstStepTargets.empty()) {
        SmallVector<Operation *> firstStepItems;
        for (Operation *item : items)
          firstStepItems.push_back(cloneWithFreshNodes(item));
        arguments.push_back(makeRandomize(allTargets, items));
        arguments.push_back(makeRandomize(firstStepTargets, firstStepItems));
      } else {
        arguments.push_back(makeRandomize(allTargets, items));
      }
      llvm::append_range(arguments, updates);
      Operation *solve = makeCall(location, "$talos_free_solve",
                                  semantic::VoidType::get(context), arguments);
      if (holdsFirstStep)
        solve->setAttr("talos.free_solve_first_step_solves",
                       builder.getI64IntegerAttr(!firstStepTargets.empty()));
      Operation *statement = makeNode(
          location, semantic::SVExpressionStatementOp::getOperationName(), {},
          {solve});
      Operation *timed =
          makeNode(location, semantic::SVTimedStatementOp::getOperationName(),
                   {}, {clock, statement});
      SmallVector<NamedAttribute> blockAttributes{
          builder.getNamedAttr(
              SymbolTable::getSymbolAttrName(),
              builder.getStringAttr(
                  (Twine("__talos_free_solve_") + Twine(solveIndex)).str())),
          builder.getNamedAttr("procedure_kind",
                               builder.getI32IntegerAttr(static_cast<int32_t>(
                                   semantic::SVProceduralBlockKind::Always))),
          builder.getNamedAttr("talos.free_solve_process",
                               builder.getUnitAttr())};
      for (StringRef name :
           {"hierarchical_name", "time_precision_fs", "time_unit_fs"})
        if (Attribute value = owner->getAttr(name))
          blockAttributes.push_back(builder.getNamedAttr(name, value));
      owner->getRegion(0).front().push_back(makeNode(
          location, semantic::SVProceduralBlockSymbolOp::getOperationName(),
          blockAttributes, {timed}));
    }
  }
  return success();
}

void rewriteTriggeredLocalOutputs(semantic::SVRootSymbolOp root,
                                  Builder &builder) {
  SmallVector<semantic::SVCallExpressionOp> calls;
  int64_t nextNodeId = 0;
  root->walk([&](Operation *op) {
    if (auto id = op->getAttrOfType<IntegerAttr>("node_id"))
      nextNodeId = std::max(nextNodeId, id.getInt() + 1);
    if (auto call = dyn_cast<semantic::SVCallExpressionOp>(op);
        call && call.getIsSystemCall() && call.getCalleeName() == "triggered" &&
        call.getArgumentCount() == 1)
      if (auto instance = dyn_cast<semantic::SVAssertionInstanceExpressionOp>(
              getChildren(call).front());
          instance && instance.getLocalVariableCount() != 0 &&
          instance.getHasExpandedBody())
        calls.push_back(call);
  });
  auto freshNodes = [&](Operation *copy) {
    copy->walk([&](Operation *nested) {
      if (nested->hasAttr("node_id"))
        nested->setAttr("node_id", builder.getI64IntegerAttr(nextNodeId++));
    });
    return copy;
  };
  for (semantic::SVCallExpressionOp call : calls) {
    auto instance = cast<semantic::SVAssertionInstanceExpressionOp>(
        getChildren(call).front());
    auto assertion =
        call->getParentOfType<semantic::SVConcurrentAssertionStatementOp>();
    // Only a maximal Boolean lets anything flow out, and there the outputs are
    // sampled on the clock of the enclosing assertion.
    auto parent =
        dyn_cast<semantic::SVSimpleAssertionExprOp>(call->getParentOp());
    if (!parent || parent.getHasRepetition())
      continue;
    SmallVector<Operation *> instanceChildren = getChildren(instance);
    if (instanceChildren.size() != 1 + instance.getArgumentCount())
      continue;
    Operation *body = instanceChildren.front();
    Operation *sequence = body;
    Operation *sourceClock = nullptr;
    if (isa<semantic::SVClockingAssertionExprOp>(body)) {
      SmallVector<Operation *> clocked = getChildren(body);
      sourceClock = clocked.front();
      sequence = clocked.back();
    }
    // A property declaration's own copy is never lowered, but is rejected if it
    // keeps its local variables, so only an assertion's needs its clock
    // checked.
    if (assertion) {
      Operation *clock = findAssertionClockFlow(call, assertion);
      if (!clock || (sourceClock && !sameClockEvent(sourceClock, clock)))
        continue;
    }
    // Each element with its distance from the end point.
    SmallVector<std::pair<Operation *, int64_t>> elements;
    if (auto concat = dyn_cast<semantic::SVSequenceConcatExprOp>(sequence)) {
      SmallVector<Operation *> parts = getChildren(concat);
      ArrayAttr delays = concat.getDelays();
      if (delays.size() != parts.size())
        continue;
      int64_t distance = 0;
      bool fixedLength = true;
      for (int64_t index = parts.size() - 1; index >= 0; --index) {
        elements.emplace_back(parts[index], distance);
        auto delay = dyn_cast<DictionaryAttr>(delays[index]);
        auto minimum = delay ? delay.getAs<IntegerAttr>("min") : IntegerAttr{};
        auto maximum = delay ? delay.getAs<IntegerAttr>("max") : IntegerAttr{};
        auto unbounded =
            delay ? delay.getAs<BoolAttr>("is_unbounded") : BoolAttr{};
        if (!minimum || !maximum || minimum != maximum ||
            (unbounded && unbounded.getValue())) {
          fixedLength = false;
          break;
        }
        // The delay ahead of the first element only offsets where it starts.
        if (index != 0)
          distance += minimum.getInt();
      }
      if (!fixedLength)
        continue;
    } else {
      elements.emplace_back(sequence, 0);
    }
    // The assignments, which must set each local output once from design state.
    llvm::StringMap<Operation *> actuals;
    for (auto [formal, actual] : llvm::zip_equal(
             instance.getArgumentFormalPaths().getAsValueRange<StringAttr>(),
             ArrayRef(instanceChildren).drop_front()))
      actuals[formal] = actual;
    llvm::StringSet<> locals;
    for (StringRef path :
         instance.getLocalVariablePaths().getAsValueRange<StringAttr>())
      locals.insert(path);
    struct Flow {
      Operation *assignment;
      Operation *actual;
      int64_t distance;
    };
    SmallVector<Flow> flows;
    llvm::StringSet<> assigned;
    bool supported = true;
    for (auto [element, distance] : elements) {
      auto matched = dyn_cast<semantic::SVSequenceWithMatchExprOp>(element);
      if (matched && matched.getHasRepetition())
        supported = false;
      if (auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(element);
          !matched && (!simple || simple.getHasRepetition()))
        supported = false;
      if (!supported || !matched)
        continue;
      for (Operation *item : ArrayRef(getChildren(matched)).drop_front()) {
        auto assignment = dyn_cast<semantic::SVAssignmentExpressionOp>(item);
        SmallVector<Operation *> sides =
            assignment ? getChildren(assignment) : SmallVector<Operation *>{};
        auto target =
            sides.size() == 2
                ? dyn_cast<semantic::SVNamedValueExpressionOp>(sides.front())
                : semantic::SVNamedValueExpressionOp{};
        Operation *actual =
            target ? actuals.lookup(target.getReferencedPath()) : nullptr;
        if (!actual || assignment.getOperatorKind() ||
            !assigned.insert(target.getReferencedPath()).second) {
          supported = false;
          break;
        }
        flows.push_back({assignment, actual, distance});
      }
    }
    // A read of a local anywhere but on the left-hand side of those assignments
    // would need its value inside the source sequence.
    llvm::DenseSet<Operation *> targets;
    for (const Flow &flow : flows)
      targets.insert(getChildren(flow.assignment).front());
    body->walk([&](semantic::SVNamedValueExpressionOp read) {
      if (locals.contains(read.getReferencedPath()) &&
          !targets.contains(read.getOperation()))
        supported = false;
    });
    if (!supported || flows.empty())
      continue;

    Location location = call.getLoc();
    auto makeOp = [&](StringRef name, ArrayRef<NamedAttribute> attributes,
                      ArrayRef<Operation *> children) {
      OperationState state(location, name);
      state.addAttribute("node_id", builder.getI64IntegerAttr(nextNodeId++));
      state.addAttributes(attributes);
      Block *block = new Block();
      state.addRegion()->push_back(block);
      for (Operation *child : children)
        block->push_back(child);
      return Operation::create(state);
    };
    // Each item `V = $past(expression, k)`, or the expression when k is zero.
    SmallVector<Operation *> items;
    for (const Flow &flow : flows) {
      Operation *item = freshNodes(flow.assignment->clone());
      SmallVector<Operation *> sides = getChildren(item);
      Block *block = sides.front()->getBlock();
      Operation *value = sides.back();
      if (flow.distance != 0) {
        Attribute type = value->getAttr("semantic_type");
        Attribute isSigned = value->getAttr("is_signed");
        Operation *depth = makeOp(
            semantic::SVIntegerLiteralOp::getOperationName(),
            {builder.getNamedAttr(
                 "constant_value",
                 builder.getStringAttr(Twine(flow.distance).str())),
             builder.getNamedAttr("is_declared_unsized",
                                  builder.getBoolAttr(true)),
             builder.getNamedAttr("is_signed", builder.getBoolAttr(true)),
             builder.getNamedAttr("semantic_type",
                                  TypeAttr::get(semantic::IntegralType::get(
                                      builder.getContext(), 32, true, false, 31,
                                      0, semantic::SVIntegralFlavor::Int)))},
            {});
        value->remove();
        Operation *past = cast<semantic::SVCallExpressionOp>(call->clone());
        for (Operation *child : getChildren(past))
          child->erase();
        past->removeAttr("is_builtin_method");
        past->setAttr("callee_name", builder.getStringAttr("$past"));
        past->setAttr("argument_count", builder.getI64IntegerAttr(2));
        past->setAttr("defaulted_arguments",
                      builder.getDenseI64ArrayAttr({0, 0}));
        past->setAttr("semantic_type", type);
        past->setAttr("is_signed", isSigned);
        past->setAttr("node_id", builder.getI64IntegerAttr(nextNodeId++));
        Block &arguments = past->getRegion(0).front();
        arguments.push_back(value);
        arguments.push_back(depth);
        block->push_back(past);
      }
      sides.front()->erase();
      block->push_front(freshNodes(flow.actual->clone()));
      items.push_back(item);
    }

    // The instance loses its local variables and match items, which leaves the
    // end points it would have had.
    for (auto [element, distance] : elements) {
      if (auto matched =
              dyn_cast<semantic::SVSequenceWithMatchExprOp>(element)) {
        Operation *inner = getChildren(matched).front();
        inner->moveBefore(matched);
        matched.erase();
      }
    }
    instance->setAttr("local_variable_count", builder.getI64IntegerAttr(0));
    instance->setAttr("local_variable_has_initializer",
                      builder.getDenseI64ArrayAttr({}));
    instance->setAttr("local_variable_paths", builder.getArrayAttr({}));
    instance->setAttr("local_variable_symbols", builder.getArrayAttr({}));

    // `(T.triggered, items...)`, at the place of the Boolean.
    Operation *anchor = parent.getOperation();
    Block *owner = anchor->getBlock();
    Block::iterator position = std::next(anchor->getIterator());
    anchor->remove();
    SmallVector<Operation *> children{anchor};
    llvm::append_range(children, items);
    Operation *replacement = makeOp(
        semantic::SVSequenceWithMatchExprOp::getOperationName(),
        {builder.getNamedAttr("has_repetition", builder.getBoolAttr(false)),
         builder.getNamedAttr("match_item_count",
                              builder.getI64IntegerAttr(items.size())),
         builder.getNamedAttr("repetition_is_unbounded",
                              builder.getBoolAttr(false))},
        children);
    owner->getOperations().insert(position, replacement);
  }
}

LogicalResult synthesizeMatchedTrackers(semantic::SVRootSymbolOp root,
                                        Builder &builder, unsigned &trackers) {
  SmallVector<semantic::SVCallExpressionOp> calls;
  int64_t nextNodeId = 0;
  root->walk([&](Operation *op) {
    if (auto id = op->getAttrOfType<IntegerAttr>("node_id"))
      nextNodeId = std::max(nextNodeId, id.getInt() + 1);
    if (auto call = dyn_cast<semantic::SVCallExpressionOp>(op);
        call && call.getIsSystemCall() && call.getCalleeName() == "matched")
      calls.push_back(call);
  });
  auto cloneWithFreshNodes = [&](Operation *source) {
    Operation *copy = source->clone();
    copy->walk([&](Operation *nested) {
      if (nested->hasAttr("node_id"))
        nested->setAttr("node_id", builder.getI64IntegerAttr(nextNodeId++));
    });
    return copy;
  };
  for (semantic::SVCallExpressionOp call : calls) {
    auto assertion =
        call->getParentOfType<semantic::SVConcurrentAssertionStatementOp>();
    Operation *clock =
        assertion ? findAssertionClockFlow(call, assertion) : nullptr;
    if (!clock)
      return emitError(getSemanticLocation(call))
             << "IEEE 1800-2023 16.13.6 the sequence method matched can only be "
                "used in a clocked sequence expression";
    SmallVector<Operation *> children = getChildren(call);
    auto instance = children.size() == 1
                        ? dyn_cast<semantic::SVAssertionInstanceExpressionOp>(
                              children.front())
                        : semantic::SVAssertionInstanceExpressionOp{};
    if (!instance)
      return emitError(getSemanticLocation(call))
             << "IEEE 1800-2023 16.13.6 the operand of matched must be a "
                "sequence instance";
    // The process goes next to the module item holding the assertion.
    Operation *anchor = call;
    while (anchor->getParentOp() &&
           !isa<semantic::SVInstanceBodySymbolOp>(anchor->getParentOp()))
      anchor = anchor->getParentOp();
    Attribute index = builder.getI64IntegerAttr(trackers);
    auto makeProcess = [&](Operation *event, StringRef task) {
      // Each is `always @(event) task;`, which the call itself is the model of.
      Location location = call.getLoc();
      Operation *record = cloneWithFreshNodes(call);
      for (Operation *child : getChildren(record))
        child->erase();
      record->setAttr("callee_name", builder.getStringAttr(task));
      record->setAttr("argument_count", builder.getI64IntegerAttr(0));
      record->setAttr("defaulted_arguments", builder.getDenseI64ArrayAttr({}));
      record->setAttr("talos.matched_index", index);
      record->setAttr("is_void_casted", builder.getUnitAttr());
      SmallVector<NamedAttribute> common;
      for (NamedAttribute attribute : call->getAttrs()) {
        StringRef name = attribute.getName().getValue();
        if (name == "original_source_range" || name.starts_with("source_"))
          common.push_back(attribute);
      }
      auto makeOp = [&](StringRef name, ArrayRef<NamedAttribute> extra,
                        ArrayRef<Operation *> nested) {
        OperationState state(location, name);
        state.addAttributes(common);
        state.addAttribute("node_id", builder.getI64IntegerAttr(nextNodeId++));
        state.addAttributes(extra);
        Block *body = new Block();
        state.addRegion()->push_back(body);
        for (Operation *child : nested)
          body->push_back(child);
        return Operation::create(state);
      };
      Operation *statement = makeOp(
          semantic::SVExpressionStatementOp::getOperationName(), {}, {record});
      Operation *timed = makeOp(semantic::SVTimedStatementOp::getOperationName(),
                                {}, {event, statement});
      SmallVector<NamedAttribute> blockAttributes{
          builder.getNamedAttr(
              SymbolTable::getSymbolAttrName(),
              builder.getStringAttr((Twine("__talos_matched_") + task.drop_front() +
                                     "_" + Twine(trackers))
                                        .str())),
          builder.getNamedAttr("procedure_kind",
                               builder.getI32IntegerAttr(static_cast<int32_t>(
                                   semantic::SVProceduralBlockKind::Always)))};
      if (Attribute name = anchor->getAttr("hierarchical_name"))
        blockAttributes.push_back(builder.getNamedAttr("hierarchical_name", name));
      Operation *block =
          makeOp(semantic::SVProceduralBlockSymbolOp::getOperationName(),
                 blockAttributes, {timed});
      anchor->getBlock()->getOperations().insertAfter(anchor->getIterator(),
                                                      block);
    };
    // The source's end points, as `always @(sequence_instance)` (9.4.2.4).
    Operation *sourceEvent = cloneWithFreshNodes(clock);
    SmallVector<Operation *> sourceChildren = getChildren(sourceEvent);
    sourceEvent->removeAttr("has_iff");
    sourceEvent->setAttr("has_iff", builder.getBoolAttr(false));
    sourceEvent->setAttr("edge_kind", builder.getI32IntegerAttr(0));
    if (!isa<semantic::SVSignalEventControlOp>(sourceEvent))
      return emitError(getSemanticLocation(call))
             << "the sequence method matched needs a single signal event as its "
                "clock";
    for (Operation *child : sourceChildren)
      child->erase();
    sourceEvent->getRegion(0).front().push_back(cloneWithFreshNodes(instance));
    makeProcess(sourceEvent, "$talos_matched_source");
    makeProcess(cloneWithFreshNodes(clock), "$talos_matched_tick");
    // The value only reads what those two record.
    children.front()->erase();
    call->setAttr("argument_count", builder.getI64IntegerAttr(0));
    call->setAttr("defaulted_arguments", builder.getDenseI64ArrayAttr({}));
    call->setAttr("talos.matched_index", index);
    ++trackers;
  }
  return success();
}

LogicalResult resolveInferredAssertionQueries(semantic::SVRootSymbolOp root,
                                              Builder &builder) {
  bool invalid = false;
  // Observers of an event are keyed by its node, so a copy needs its own.
  std::optional<int64_t> nextNodeId;
  auto cloneWithFreshNodes = [&](Operation *source) {
    if (!nextNodeId) {
      nextNodeId = 0;
      root->walk([&](Operation *nested) {
        if (auto id = nested->getAttrOfType<IntegerAttr>("node_id"))
          *nextNodeId = std::max(*nextNodeId, id.getInt() + 1);
      });
    }
    Operation *copy = source->clone();
    copy->walk([&](Operation *nested) {
      if (nested->hasAttr("node_id"))
        nested->setAttr("node_id", builder.getI64IntegerAttr((*nextNodeId)++));
    });
    return copy;
  };
  root->walk([&](semantic::SVConcurrentAssertionStatementOp assertion) {
    SmallVector<Operation *> children = getChildren(assertion);
    size_t prefix = 0;
    Operation *disable = nullptr, *contextual = nullptr, *defaultClock = nullptr;
    if (assertion.getHasDefaultDisable() && prefix < children.size())
      disable = children[prefix++];
    if (assertion.getHasContextualClock().value_or(false) &&
        prefix < children.size())
      contextual = children[prefix++];
    if (assertion.getDefaultClockingSymbolAttr() && prefix < children.size())
      defaultClock = children[prefix++];
    if (prefix >= children.size())
      return;
    // Outermost first: an inner query may copy an enclosing resolved clock.
    SmallVector<semantic::SVCallExpressionOp> queries;
    children[prefix]->walk<WalkOrder::PreOrder>(
        [&](semantic::SVCallExpressionOp call) {
      if (call.getIsSystemCall() &&
          (call.getCalleeName() == "$inferred_clock" ||
           call.getCalleeName() == "$inferred_disable"))
        queries.push_back(call);
    });
    for (semantic::SVCallExpressionOp query : queries) {
      if (query.getCalleeName() == "$inferred_disable") {
        Operation *replacement = nullptr;
        if (disable) {
          replacement = cloneWithFreshNodes(disable);
        } else {
          OperationState literal(
              query.getLoc(), semantic::SVIntegerLiteralOp::getOperationName());
          literal.addAttribute("node_id", query->getAttr("node_id"));
          literal.addAttribute("semantic_type", query->getAttr("semantic_type"));
          literal.addAttribute("is_signed", builder.getBoolAttr(false));
          literal.addAttribute("constant_value", builder.getStringAttr("0"));
          literal.addRegion()->push_back(new Block());
          replacement = Operation::create(literal);
        }
        query->getBlock()->getOperations().insert(query->getIterator(),
                                                  replacement);
        query->erase();
        continue;
      }
      auto event = dyn_cast_or_null<semantic::SVSignalEventControlOp>(
          query->getParentOp());
      if (!event) {
        emitError(getSemanticLocation(query))
            << "$inferred_clock must be the whole clocking event of a property "
               "or sequence (IEEE 1800-2023 16.14.7)";
        invalid = true;
        continue;
      }
      // An enclosing clocking of the property flows here (16.13.3) ahead of
      // the procedural context and the default clocking.
      Operation *source = nullptr;
      Operation *clocked = event->getParentOp();
      for (Operation *cursor = clocked ? clocked->getParentOp() : nullptr;
           cursor && cursor != assertion.getOperation();
           cursor = cursor->getParentOp())
        if (isa<semantic::SVClockingAssertionExprOp>(cursor)) {
          source = getChildren(cursor).front();
          break;
        }
      if (!source)
        source = contextual ? contextual : defaultClock;
      if (!source) {
        emitError(getSemanticLocation(query))
            << "$inferred_clock has no current resolved event expression "
               "(IEEE 1800-2023 16.14.7)";
        invalid = true;
        continue;
      }
      event->getBlock()->getOperations().insert(event->getIterator(),
                                                cloneWithFreshNodes(source));
      event->erase();
    }
  });
  return failure(invalid);
}

LogicalResult rebindVirtualInterfaceCallDefaults(
    semantic::SVRootSymbolOp root, const llvm::StringMap<Operation *> &symbols,
    Builder &builder) {
  bool invalid = false;
  root->walk([&](semantic::SVCallExpressionOp call) {
    if (call.getIsSystemCall() || !call.getHasThisClass())
      return;
    std::optional<ArrayRef<int64_t>> defaulted = call.getDefaultedArguments();
    SmallVector<Operation *> children = getChildren(call);
    if (!defaulted || children.size() != defaulted->size() + 1)
      return;
    Operation *receiver = children.front();
    auto type = receiver->getAttrOfType<TypeAttr>("semantic_type");
    if (!type || !isa<semantic::VirtualInterfaceType>(type.getValue()))
      return;
    for (auto [isDefaulted, argument] :
         llvm::zip_equal(*defaulted, ArrayRef(children).drop_front())) {
      if (!isDefaulted)
        continue;
      SmallVector<semantic::SVNamedValueExpressionOp> reads;
      argument->walk([&](semantic::SVNamedValueExpressionOp read) {
        auto symbol = symbols.find(read.getReferencedSymbolAttr()
                                       ? read.getReferencedSymbolAttr()
                                             .getLeafReference()
                                             .getValue()
                                       : StringRef());
        if (symbol != symbols.end() &&
            isCompileTimeOnlyInstanceMember(symbol->second))
          reads.push_back(read);
      });
      if (reads.empty())
        continue;
      bool receiverHasCall = false;
      receiver->walk(
          [&](semantic::SVCallExpressionOp) { receiverHasCall = true; });
      if (receiverHasCall) {
        emitError(getSemanticLocation(call))
            << "a default argument reading interface state requires a virtual "
               "interface receiver without calls, which it evaluates again";
        invalid = true;
        continue;
      }
      for (semantic::SVNamedValueExpressionOp read : reads) {
        Operation *member =
            symbols.find(read.getReferencedSymbolAttr().getLeafReference())
                ->second;
        OperationState state(
            read.getLoc(),
            semantic::SVMemberAccessExpressionOp::getOperationName());
        state.addAttributes(read->getAttrs());
        state.addAttribute("member_name",
                           builder.getStringAttr(getDebugName(member)));
        Block *body = new Block();
        state.addRegion()->push_back(body);
        body->push_back(receiver->clone());
        read->getBlock()->getOperations().insert(read->getIterator(),
                                                 Operation::create(state));
        read->erase();
      }
    }
  });
  return failure(invalid);
}

} // namespace talos::simlowering
