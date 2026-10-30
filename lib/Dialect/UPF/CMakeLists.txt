add_mlir_library(TalosUPFIR UPFDialect.cpp
  DEPENDS TalosUPFDialectIncGen TalosUPFEnumsIncGen TalosUPFAttrsIncGen TalosUPFOpsIncGen
  LINK_LIBS PUBLIC MLIRIR)
