add_mlir_library(TalosNativeIR
  FallbackReport.cpp
  NativeDialect.cpp
  NativeRuntimeEntries.cpp

  DEPENDS
  TalosNativeAttrsIncGen
  TalosNativeDialectIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRLLVMDialect
)
