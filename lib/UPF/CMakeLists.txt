add_mlir_library(TalosUPF
  Execute.cpp
  BooleanExpression.cpp
  ControlReference.cpp
  Elaborate.cpp
  DEPENDS SlangOpsIncGen TalosSimulationOpsIncGen TalosUPFOpsIncGen
    TalosUPFAttrsIncGen TalosUPFEnumsIncGen
  LINK_LIBS PUBLIC TalosUPFIR TalosSlangIR TalosSimulationIR
    MLIRArithDialect MLIRControlFlowDialect MLIRIR MLIRPass)
if(TALOS_ENABLE_UPF)
  target_compile_definitions(obj.TalosUPF PRIVATE
    TALOS_ENABLE_UPF=1 TALOS_TCL_LIBRARY_DIR="${TALOS_TCL_LIBRARY_DIR}")
  target_link_libraries(TalosUPF PRIVATE TalosTclCore)
  target_link_libraries(obj.TalosUPF PRIVATE TalosTclCore)
endif()
