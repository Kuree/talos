#include "PowerState.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/SetVector.h"
using namespace mlir;
namespace talos {
namespace {
Value integer(OpBuilder &b, Location loc, int64_t value, unsigned width) {
  return arith::ConstantIntOp::create(b, loc, value, width);
}
Value predicate(upf::SupplyExpressionAttr expression, OpBuilder &b,
                Location loc, llvm::function_ref<Value(FlatSymbolRefAttr)> read,
                std::optional<upf::PartialOnTranslation> translation) {
  using O = upf::SupplyExpressionOpcode;
  SmallVector<Value> stack;
  for (auto attr : expression.getTokens()) {
    auto token = cast<upf::SupplyExpressionTokenAttr>(attr);
    O code = token.getOpcode();
    if (code == O::State || code == O::Voltage) {
      Value value = read(token.getSupply());
      if (code == O::State) {
        stack.push_back(interpretedSupplyState(b, loc, value, translation));
      } else {
        // 4.7.2/6.5.4: compare real volts, not a rounded write request.
        // Decode signed32 first (also on wasm32), then divide by exact 1e6.
        // Aggregate equality and explicit .voltage use this identical path.
        value = arith::ShRUIOp::create(b, loc, value, integer(b, loc, 2, 64));
        value = arith::TruncIOp::create(b, loc, b.getI32Type(), value);
        value = sim::SimRealFromIntegerOp::create(b, loc, b.getF64Type(), value,
                                                  true);
        Value scale = arith::ConstantOp::create(b, loc, b.getF64FloatAttr(1e6));
        stack.push_back(arith::DivFOp::create(b, loc, value, scale));
      }
      continue;
    }
    if (code == O::Real) {
      stack.push_back(arith::ConstantOp::create(b, loc, token.getReal()));
      continue;
    }
    if (code == O::StateValue || code == O::Boolean) {
      stack.push_back(arith::ConstantOp::create(b, loc, token.getValue()));
      continue;
    }
    Value right = stack.pop_back_val();
    if (code == O::Not || code == O::BitNot) {
      stack.push_back(
          arith::XOrIOp::create(b, loc, right, integer(b, loc, 1, 1)));
      continue;
    }
    Value left = stack.pop_back_val(), result;
    if (code == O::And || code == O::BitAnd)
      result = arith::AndIOp::create(b, loc, left, right);
    else if (code == O::Or || code == O::BitOr)
      result = arith::OrIOp::create(b, loc, left, right);
    else if (code == O::BitXor)
      result = arith::XOrIOp::create(b, loc, left, right);
    else if (left.getType().isF64()) {
      arith::CmpFPredicate p;
      switch (code) {
      case O::Equal:
        p = arith::CmpFPredicate::OEQ;
        break;
      case O::NotEqual:
        p = arith::CmpFPredicate::ONE;
        break;
      case O::Less:
        p = arith::CmpFPredicate::OLT;
        break;
      case O::LessEqual:
        p = arith::CmpFPredicate::OLE;
        break;
      case O::Greater:
        p = arith::CmpFPredicate::OGT;
        break;
      case O::GreaterEqual:
        p = arith::CmpFPredicate::OGE;
        break;
      default:
        llvm_unreachable("verified supply float comparison");
      }
      result = arith::CmpFOp::create(b, loc, p, left, right);
    } else
      result =
          arith::CmpIOp::create(b, loc,
                                code == O::Equal ? arith::CmpIPredicate::eq
                                                 : arith::CmpIPredicate::ne,
                                left, right);
    stack.push_back(result);
  }
  return stack.back();
}
} // namespace
Value interpretedSupplyState(
    OpBuilder &b, Location loc, Value packed,
    std::optional<upf::PartialOnTranslation> translation) {
  // IEEE 1801-2018 6.47: translate observed state for policy evaluation only.
  // Predicate literals, voltage bits, and the underlying supply stay unchanged.
  Value state = arith::AndIOp::create(b, loc, packed, integer(b, loc, 3, 64));
  state = arith::TruncIOp::create(b, loc, b.getI32Type(), state);
  if (translation) {
    Value partial = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                          state, integer(b, loc, 2, 32));
    Value replacement =
        integer(b, loc, *translation == upf::PartialOnTranslation::FullOn, 32);
    state = arith::SelectOp::create(b, loc, partial, replacement, state);
  }
  return state;
}
SmallVector<FlatSymbolRefAttr> getSupplySetReferences(upf::UPFSupplySetOp set) {
  llvm::SetVector<Attribute> refs;
  bool defaultOn = true;
  if (auto states = set.getStatesAttr())
    for (auto attr : states) {
      auto state = cast<upf::PowerStateAttr>(attr);
      if (!state.getCondition())
        continue;
      if (state.getName().getValue() == "ON")
        defaultOn = false;
      for (auto attr : state.getCondition().getTokens())
        if (auto supply =
                cast<upf::SupplyExpressionTokenAttr>(attr).getSupply())
          refs.insert(supply);
    }
  if (defaultOn)
    for (auto function : set.getRequired())
      refs.insert(cast<FlatSymbolRefAttr>(
          set.getFunctions().get(cast<StringAttr>(function).getValue())));
  SmallVector<FlatSymbolRefAttr> result;
  for (auto ref : refs)
    result.push_back(cast<FlatSymbolRefAttr>(ref));
  return result;
}
SupplyStateEvaluation
evaluateSupplySet(upf::UPFSupplySetOp set, OpBuilder &b, Location loc,
                  llvm::function_ref<Value(FlatSymbolRefAttr)> read) {
  auto translation = upf::getPartialOnTranslation(set);
  auto bit = [&](bool value) { return integer(b, loc, value, 1); };
  auto negate = [&](Value value) -> Value {
    return arith::XOrIOp::create(b, loc, value, bit(true));
  };
  auto condition = [&](upf::PowerStateAttr state) -> Value {
    return state && state.getCondition()
               ? predicate(state.getCondition(), b, loc, read, translation)
               : bit(false);
  };
  upf::PowerStateAttr onState, offState;
  if (auto states = set.getStatesAttr())
    for (auto attr : states) {
      auto state = cast<upf::PowerStateAttr>(attr);
      if (state.getName().getValue() == "ON")
        onState = state;
      if (state.getName().getValue() == "OFF")
        offState = state;
    }
  Value on;
  if (onState && onState.getCondition())
    on = condition(onState);
  else {
    // 4.7.4: infer FULL_ON only for an unmodified ON definition.
    on = bit(true);
    for (auto function : set.getRequired()) {
      auto root = cast<FlatSymbolRefAttr>(
          set.getFunctions().get(cast<StringAttr>(function).getValue()));
      Value state = interpretedSupplyState(b, loc, read(root), translation);
      Value full = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                         state, integer(b, loc, 1, 32));
      on = arith::AndIOp::create(b, loc, on, full);
    }
  }
  Value seen = bit(false), normal = bit(false), conflict = bit(false),
        illegal = bit(false);
  auto add = [&](Value active, bool isNormal, bool isIllegal) {
    conflict = arith::OrIOp::create(
        b, loc, conflict, arith::AndIOp::create(b, loc, seen, active));
    seen = arith::OrIOp::create(b, loc, seen, active);
    if (isNormal)
      normal = arith::OrIOp::create(b, loc, normal, active);
    if (isIllegal)
      illegal = arith::OrIOp::create(b, loc, illegal, active);
  };
  add(on, true, onState && onState.getIllegal());
  if (auto states = set.getStatesAttr())
    for (auto attr : states) {
      auto state = cast<upf::PowerStateAttr>(attr);
      auto name = state.getName().getValue();
      if (name == "ON" || name == "OFF")
        continue;
      add(condition(state), state.getSimstate() == upf::Simstate::Normal,
          state.getIllegal());
    }
  // 9.3.2/6.5.6(m): explicit OFF does not remove the fallback. Gaps are
  // still OFF, including under -complete. Illegal rows retain their simstate.
  Value off = arith::OrIOp::create(b, loc, condition(offState), negate(seen));
  add(off, false, offState && offState.getIllegal());
  // 4.7.3: flat fundamental rows are exclusive; corruption precedence
  // between independent sets must not hide an overlap within one set.
  normal = arith::AndIOp::create(b, loc, normal, negate(conflict));
  return {normal, conflict, illegal};
}
} // namespace talos
