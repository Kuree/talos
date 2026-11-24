# Optional host-side accelerator for the finite-wave scheduling planner.
add_library(TalosRankGraph SHARED EXCLUDE_FROM_ALL RankGraph.cpp)
if(TALOS_ENABLE_Z3)
  target_sources(TalosRankGraph PRIVATE RankSMT.cpp)
  add_dependencies(TalosRankGraph talos_z3_project)
  target_link_libraries(TalosRankGraph PRIVATE TalosZ3)
endif()
set_target_properties(TalosRankGraph PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
foreach(script forward_rank.py rank_native.py eval_rank.py verify_heuristic.py)
  configure_file("${PROJECT_SOURCE_DIR}/benchmark/scheduler/${script}" "${script}" COPYONLY)
endforeach()
