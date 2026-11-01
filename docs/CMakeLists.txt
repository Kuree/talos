if(CMAKE_CROSSCOMPILING)
  return()
endif()

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(TALOS_DOCS_OUTPUT_DIR "${PROJECT_SOURCE_DIR}/docs/reference" CACHE PATH
    "Generated Markdown reference documentation")

add_custom_target(talos-docs
  COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/utils/docs/generate.py"
    --source "${PROJECT_SOURCE_DIR}"
    --build "${PROJECT_BINARY_DIR}"
    --sdk "${TALOS_LLVM_DIST_DIR}"
    --output "${TALOS_DOCS_OUTPUT_DIR}"
    --conformance-report "${TALOS_CONFORMANCE_OUTPUT_DIR}/results.json"
    --tool "talos=$<TARGET_FILE:talos>"
    --tool "talos-cov=$<TARGET_FILE:talos-cov>"
  DEPENDS talos talos-cov check-talos-conformance
  COMMENT "Generating Talos tool, dialect, and pass reference documentation"
  VERBATIM)

add_custom_target(talos-docs-site
  COMMAND "${Python3_EXECUTABLE}" -m sphinx -b dirhtml -W --keep-going
    -c "${PROJECT_SOURCE_DIR}/docs"
    "${TALOS_DOCS_OUTPUT_DIR}" "${PROJECT_SOURCE_DIR}/docs/_site"
  DEPENDS talos-docs
  COMMENT "Building the Talos documentation website (requires docs/requirements.txt)"
  VERBATIM)
