add_mlir_library(TalosTransforms
  ThreadConstantBranches.cpp

  DEPENDS
  TalosTransformsPassIncGen

  LINK_LIBS PUBLIC
  MLIRControlFlowDialect
  MLIRControlFlowInterfaces
  MLIRIR
  MLIRLLVMDialect
  MLIRPass
  MLIRTransformUtils
)
