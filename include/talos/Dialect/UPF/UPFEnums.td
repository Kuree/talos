#ifndef TALOS_DIALECT_UPF_ENUMS_TD
#define TALOS_DIALECT_UPF_ENUMS_TD
include "mlir/IR/EnumAttr.td"
def UPFControl : I32EnumAttrCase<"Control", 0, "control">;
def UPFConstant : I32EnumAttrCase<"Constant", 1, "constant">;
def UPFNot : I32EnumAttrCase<"Not", 2, "not">;
def UPFBitNot : I32EnumAttrCase<"BitNot", 3, "bit_not">;
def UPFLess : I32EnumAttrCase<"Less", 4, "lt">;
def UPFLessEqual : I32EnumAttrCase<"LessEqual", 5, "le">;
def UPFGreater : I32EnumAttrCase<"Greater", 6, "gt">;
def UPFGreaterEqual : I32EnumAttrCase<"GreaterEqual", 7, "ge">;
def UPFEqual : I32EnumAttrCase<"Equal", 8, "eq">;
def UPFNotEqual : I32EnumAttrCase<"NotEqual", 9, "ne">;
def UPFBitAnd : I32EnumAttrCase<"BitAnd", 10, "bit_and">;
def UPFBitXor : I32EnumAttrCase<"BitXor", 11, "bit_xor">;
def UPFBitOr : I32EnumAttrCase<"BitOr", 12, "bit_or">;
def UPFAnd : I32EnumAttrCase<"And", 13, "and">;
def UPFOr : I32EnumAttrCase<"Or", 14, "or">;
def UPFExpressionOpcode : I32EnumAttr<"ExpressionOpcode", "UPF Boolean operator", [
  UPFControl, UPFConstant, UPFNot, UPFBitNot, UPFLess, UPFLessEqual,
  UPFGreater, UPFGreaterEqual, UPFEqual, UPFNotEqual,
  UPFBitAnd, UPFBitXor, UPFBitOr, UPFAnd, UPFOr
]> { let cppNamespace = "::talos::upf"; }
def UPFSState : I32EnumAttrCase<"State", 0, "state">;
def UPFSVoltage : I32EnumAttrCase<"Voltage", 1, "voltage">;
def UPFSStateValue : I32EnumAttrCase<"StateValue", 2, "state_value">;
def UPFSReal : I32EnumAttrCase<"Real", 3, "real">;
def UPFSBool : I32EnumAttrCase<"Boolean", 4, "bool">;
def UPFSNot : I32EnumAttrCase<"Not", 5, "not">;
def UPFSBitNot : I32EnumAttrCase<"BitNot", 6, "bit_not">;
def UPFSLess : I32EnumAttrCase<"Less", 7, "lt">;
def UPFSLessEqual : I32EnumAttrCase<"LessEqual", 8, "le">;
def UPFSGreater : I32EnumAttrCase<"Greater", 9, "gt">;
def UPFSGreaterEqual : I32EnumAttrCase<"GreaterEqual", 10, "ge">;
def UPFSEqual : I32EnumAttrCase<"Equal", 11, "eq">;
def UPFSNotEqual : I32EnumAttrCase<"NotEqual", 12, "ne">;
def UPFSBitAnd : I32EnumAttrCase<"BitAnd", 13, "bit_and">;
def UPFSBitXor : I32EnumAttrCase<"BitXor", 14, "bit_xor">;
def UPFSBitOr : I32EnumAttrCase<"BitOr", 15, "bit_or">;
def UPFSAnd : I32EnumAttrCase<"And", 16, "and">;
def UPFSOr : I32EnumAttrCase<"Or", 17, "or">;
def UPFSupplyExpressionOpcode : I32EnumAttr<"SupplyExpressionOpcode", "typed supply predicate operation", [
  UPFSState, UPFSVoltage, UPFSStateValue, UPFSReal, UPFSBool, UPFSNot,
  UPFSBitNot, UPFSLess, UPFSLessEqual, UPFSGreater, UPFSGreaterEqual,
  UPFSEqual, UPFSNotEqual, UPFSBitAnd, UPFSBitXor, UPFSBitOr, UPFSAnd, UPFSOr
]> { let cppNamespace = "::talos::upf"; }
def UPFSimUnspecified : I32EnumAttrCase<"Unspecified", 0, "unspecified">;
def UPFSimNormal : I32EnumAttrCase<"Normal", 1, "normal">;
def UPFSimCorrupt : I32EnumAttrCase<"Corrupt", 2, "corrupt">;
def UPFSimNotNormal : I32EnumAttrCase<"NotNormal", 3, "not_normal">;
def UPFSimstate : I32EnumAttr<"Simstate", "supported UPF simulation policy", [
  UPFSimUnspecified, UPFSimNormal, UPFSimCorrupt, UPFSimNotNormal
]> { let cppNamespace = "::talos::upf"; }
def UPFPartialAsOff : I32EnumAttrCase<"Off", 0, "off">;
def UPFPartialAsFull : I32EnumAttrCase<"FullOn", 1, "full_on">;
def UPFPartialOnTranslation : I32EnumAttr<"PartialOnTranslation",
    "IEEE 1801-2018 6.47 partial supply interpretation",
    [UPFPartialAsOff, UPFPartialAsFull]> {
  let cppNamespace = "::talos::upf";
  let genSpecializedAttr = 0;
}
def UPFRetSignal : I32EnumAttrCase<"Signal", 0, "signal">;
def UPFRetInstance : I32EnumAttrCase<"Instance", 1, "instance">;
def UPFRetentionElementKind : I32EnumAttr<"RetentionElementKind",
    "IEEE 1801-2018 5.7.3 retention selection kind", [UPFRetSignal, UPFRetInstance]> {
  let cppNamespace = "::talos::upf";
}
def UPFRetHigh : I32EnumAttrCase<"High", 0, "high">;
def UPFRetLow : I32EnumAttrCase<"Low", 1, "low">;
def UPFRetPosedge : I32EnumAttrCase<"Posedge", 2, "posedge">;
def UPFRetNegedge : I32EnumAttrCase<"Negedge", 3, "negedge">;
def UPFRetentionTriggerKind : I32EnumAttr<"RetentionTriggerKind",
    "IEEE 1801-2018 6.50 retention event sense",
    [UPFRetHigh, UPFRetLow, UPFRetPosedge, UPFRetNegedge]> {
  let cppNamespace = "::talos::upf";
}
#endif
