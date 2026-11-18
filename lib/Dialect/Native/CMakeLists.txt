add_mlir_library(TalosNativeIR
  FallbackReport.cpp
  NativeDialect.cpp

  DEPENDS
  TalosNativeAttrsIncGen
  TalosNativeDialectIncGen

  LINK_LIBS PUBLIC
  MLIRIR
)
