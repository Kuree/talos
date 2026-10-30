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
#endif
