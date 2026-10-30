add_mlir_library(TalosUPFIR UPFDialect.cpp
  DEPENDS TalosUPFDialectIncGen TalosUPFOpsIncGen
  LINK_LIBS PUBLIC MLIRIR)
