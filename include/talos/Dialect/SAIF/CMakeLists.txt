set(LLVM_TARGET_DEFINITIONS SAIFEnums.td)
mlir_tablegen(SAIFEnums.h.inc -gen-enum-decls)
mlir_tablegen(SAIFEnums.cpp.inc -gen-enum-defs)
add_public_tablegen_target(TalosSAIFEnumsIncGen)

set(LLVM_TARGET_DEFINITIONS SAIFAttrs.td)
mlir_tablegen(SAIFAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=saif)
mlir_tablegen(SAIFAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=saif)
add_public_tablegen_target(TalosSAIFAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS SAIFOps.td)
mlir_tablegen(SAIFOps.h.inc -gen-op-decls)
mlir_tablegen(SAIFOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(TalosSAIFOpsIncGen)

set(LLVM_TARGET_DEFINITIONS SAIFDialect.td)
mlir_tablegen(SAIFDialect.h.inc -gen-dialect-decls -dialect=saif)
mlir_tablegen(SAIFDialect.cpp.inc -gen-dialect-defs -dialect=saif)
add_public_tablegen_target(TalosSAIFDialectIncGen)
