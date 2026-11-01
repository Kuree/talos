# Included from docs/: conformance feeds the website, even with the test suites disabled.
set(TALOS_CONFORMANCE_JOBS 4 CACHE STRING "Number of concurrent conformance probes")
set(TALOS_CONFORMANCE_OUTPUT_DIR "${PROJECT_BINARY_DIR}/test/Conformance")
set(_talos_conformance_command
  "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/scripts/check-conformance.py"
  --compiler "$<TARGET_FILE:talos>"
  --clang "${TALOS_LLVM_DIST_DIR}/bin/clang${CMAKE_EXECUTABLE_SUFFIX}"
  --filecheck "$<TARGET_FILE:talos-filecheck>"
  --tests "${PROJECT_SOURCE_DIR}/test/Conformance"
  --output "${TALOS_CONFORMANCE_OUTPUT_DIR}"
  --jobs "${TALOS_CONFORMANCE_JOBS}")
if(APPLE AND TALOS_MACOS_SYSROOT)
  set(_talos_conformance_command
    "${CMAKE_COMMAND}" -E env "SDKROOT=${TALOS_MACOS_SYSROOT}"
    ${_talos_conformance_command})
endif()

# Reports include unsupported features; the check target additionally rejects
# unexpected failures/improvements and passing clauses without a SINCE version.
add_custom_target(talos-conformance
  COMMAND ${_talos_conformance_command}
  DEPENDS talos talos-filecheck
  COMMENT "Recording the Talos IEEE 1800 and IEEE 1801 conformance results"
  USES_TERMINAL VERBATIM)
add_custom_target(check-talos-conformance
  COMMAND ${_talos_conformance_command} --check
  DEPENDS talos talos-filecheck
  COMMENT "Checking the Talos IEEE 1800 and IEEE 1801 conformance results"
  USES_TERMINAL VERBATIM)
set_target_properties(talos-conformance check-talos-conformance PROPERTIES FOLDER "Tests")
unset(_talos_conformance_command)
