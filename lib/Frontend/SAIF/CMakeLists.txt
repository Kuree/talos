add_mlir_library(TalosSAIFFrontend
  SAIF.cpp
  DEPENDS TalosSAIFOpsIncGen TalosSAIFAttrsIncGen TalosSAIFEnumsIncGen
    TalosSAIFDialectIncGen
  LINK_LIBS PUBLIC TalosSAIFIR MLIRIR MLIRSupport)
