add_mlir_library(TalosSAIFIR
  SAIFDialect.cpp

  DEPENDS
  TalosSAIFAttrsIncGen
  TalosSAIFDialectIncGen
  TalosSAIFEnumsIncGen
  TalosSAIFOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
)
