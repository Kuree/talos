# Keep bin/ and lib/talos/ together in native archives and in the wheel's
# talos_sv package.
if(EMSCRIPTEN)
  return()
endif()

install(TARGETS talos talos-cov
  RUNTIME DESTINATION bin COMPONENT talos)
install(TARGETS talos-opt talos-translate
  RUNTIME DESTINATION bin COMPONENT talos-dev)
if(WIN32)
  # Stage the selected dependencies directly. An existing build directory may
  # still have obsolete ICU DLLs beside its tools.
  install(CODE "
    execute_process(COMMAND \"${CMAKE_COMMAND}\"
      \"-DSDK=${TALOS_LLVM_DIST_DIR}\"
      \"-DDIRECTORIES=\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/bin\"
      -P \"${PROJECT_SOURCE_DIR}/cmake/StageWindowsDLLs.cmake\"
      COMMAND_ERROR_IS_FATAL ANY)
  " COMPONENT talos)
endif()
install(DIRECTORY "${PROJECT_BINARY_DIR}/lib/talos/include"
  DESTINATION lib/talos COMPONENT talos)
# Dereference only the current content-addressed support tree. Wheels should
# neither retain build-tree symlinks nor package historical staging versions.
install(CODE "
  file(REAL_PATH \"${TALOS_NATIVE_SUPPORT_DIR}\" _talos_install_support)
  file(INSTALL
    DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib/talos/targets/${TALOS_TARGET_TRIPLE}\"
    TYPE DIRECTORY FILES \"\${_talos_install_support}/\")
" COMPONENT talos)
install(FILES "${PROJECT_SOURCE_DIR}/VERSION"
  DESTINATION share/talos COMPONENT talos)
install(FILES "${PROJECT_SOURCE_DIR}/LICENSE"
  DESTINATION share/talos/licenses COMPONENT talos)
install(DIRECTORY "${PROJECT_SOURCE_DIR}/docs/third-party/licenses/"
  DESTINATION share/talos/licenses COMPONENT talos)
if(TALOS_ENABLE_UPF)
  install(DIRECTORY "${TALOS_TCL_LIBRARY_DIR}/"
    DESTINATION lib/talos/tcl9.0 COMPONENT talos
    PATTERN "encoding" EXCLUDE PATTERN "*.enc" EXCLUDE
    PATTERN "cookiejar*" EXCLUDE
    PATTERN "install.tcl" EXCLUDE PATTERN "tclAppInit.c" EXCLUDE)
endif()
set(_talos_llvm_license "${TALOS_LLVM_DIST_DIR}/include/llvm/Support/LICENSE.TXT")
if(NOT EXISTS "${_talos_llvm_license}")
  # Some conda SDKs omit this header-tree copy. The project carries the same
  # Apache-2.0 + LLVM-exception terms; package-specific notices are added too.
  set(_talos_llvm_license "${PROJECT_SOURCE_DIR}/LICENSE")
endif()
install(FILES "${_talos_llvm_license}"
  DESTINATION share/talos/licenses RENAME llvm-LICENSE.TXT COMPONENT talos)

if(SKBUILD AND (WIN32 OR APPLE))
  # Native archives use this same dependency/notice bundling step. For wheels
  # run it inside the install tree before scikit-build creates the archive.
  file(TO_CMAKE_PATH "${Python_EXECUTABLE}" _talos_install_python)
  install(CODE "
    execute_process(COMMAND \"${_talos_install_python}\"
      \"${PROJECT_SOURCE_DIR}/utils/packaging/build_archive.py\"
      --build \"${PROJECT_BINARY_DIR}\" --bundle-only \"\${CMAKE_INSTALL_PREFIX}\"
      COMMAND_ERROR_IS_FATAL ANY)
  " COMPONENT talos)
endif()
