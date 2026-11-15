//===- SAIFEnums.td - SAIF record kinds ------------------*- tablegen -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFENUMS_TD
#define TALOS_DIALECT_SAIF_SAIFENUMS_TD

include "mlir/IR/EnumAttr.td"

def SAIFHeaderKind : I32EnumAttr<"HeaderKind", "SAIF header kind", [
  I32EnumAttrCase<"Version", 0, "version">,
  I32EnumAttrCase<"Direction", 1, "direction">,
  I32EnumAttrCase<"Design", 2, "design">,
  I32EnumAttrCase<"Date", 3, "date">,
  I32EnumAttrCase<"Vendor", 4, "vendor">,
  I32EnumAttrCase<"ProgramName", 5, "program_name">,
  I32EnumAttrCase<"ProgramVersion", 6, "program_version">,
  I32EnumAttrCase<"Divider", 7, "divider">,
  I32EnumAttrCase<"TimeScale", 8, "timescale">,
  I32EnumAttrCase<"Duration", 9, "duration">
]> { let cppNamespace = "::talos::saif"; }

def SAIFMetricKind : I32EnumAttr<"MetricKind", "SAIF activity metric", [
  I32EnumAttrCase<"T0", 0>, I32EnumAttrCase<"T1", 1>,
  I32EnumAttrCase<"TX", 2>, I32EnumAttrCase<"TZ", 3>,
  I32EnumAttrCase<"TB", 4>, I32EnumAttrCase<"TC", 5>,
  I32EnumAttrCase<"TG", 6>, I32EnumAttrCase<"IG", 7>,
  I32EnumAttrCase<"IK", 8>
]> { let cppNamespace = "::talos::saif"; }

def SAIFEdge : I32EnumAttr<"Edge", "SAIF edge restriction", [
  I32EnumAttrCase<"None", 0, "none">,
  I32EnumAttrCase<"Rise", 1, "rise">,
  I32EnumAttrCase<"Fall", 2, "fall">,
  I32EnumAttrCase<"RiseFall", 3, "rise_fall">
]> { let cppNamespace = "::talos::saif"; }

def SAIFConditionOpcode
    : I32EnumAttr<"ConditionOpcode", "SAIF condition opcode", [
  I32EnumAttrCase<"Pin", 0, "pin">,
  I32EnumAttrCase<"Not", 1, "not">,
  I32EnumAttrCase<"And", 2, "and">,
  I32EnumAttrCase<"Xor", 3, "xor">,
  I32EnumAttrCase<"Or", 4, "or">
]> { let cppNamespace = "::talos::saif"; }

#endif // TALOS_DIALECT_SAIF_SAIFENUMS_TD
