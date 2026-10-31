# IEEE 1801-2018 5.1 requires full Tcl >= 8.4 for processing UPF.
# Compiler-only Tcl core. Do not configure Tk, tclsh, contributed packages,
# documentation, or a separate zlib build. Reuse the host zlib package.
set(TALOS_TCL_VERSION "9.0.4")
# Tcl needs these independently of optional Z3, Slang threading, and LLVM's
# optional zlib support. Do not rely on another component to create targets.
find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)
if(TALOS_TCL_INSTALL_DIR)
  set(_talos_tcl_install "${TALOS_TCL_INSTALL_DIR}")
  foreach(artifact include/tcl.h lib/tcl9.0/init.tcl)
    if(NOT EXISTS "${_talos_tcl_install}/${artifact}")
      message(FATAL_ERROR "Static Tcl installation is missing ${artifact}")
    endif()
  endforeach()
  # MSVC static Tcl uses tcl90s.lib; tcl90.lib is a DLL import library and
  # cannot be linked with STATIC_BUILD. MinGW and Unix use libtcl9.0.a.
  set(_talos_tcl_archive "${TALOS_TCL_STATIC_LIBRARY}")
  if(NOT _talos_tcl_archive)
    foreach(name libtcl9.0.a tcl90s.lib)
      if(EXISTS "${_talos_tcl_install}/lib/${name}")
        set(_talos_tcl_archive "${_talos_tcl_install}/lib/${name}")
        break()
      endif()
    endforeach()
  endif()
  if(NOT EXISTS "${_talos_tcl_archive}")
    message(FATAL_ERROR "Static Tcl archive is missing; set "
      "TALOS_TCL_STATIC_LIBRARY to a Tcl 9.0.4 static library (not a DLL import library)")
  endif()
  file(STRINGS "${_talos_tcl_install}/include/tcl.h" _talos_tcl_version
    REGEX "^#[ \t]*define[ \t]+TCL_PATCH_LEVEL[ \t]+\"")
  if(NOT _talos_tcl_version MATCHES "\"9\\.0\\.4\"")
    message(FATAL_ERROR "TALOS_TCL_INSTALL_DIR must contain Tcl 9.0.4")
  endif()
elseif(UNIX AND NOT EMSCRIPTEN AND NOT CMAKE_CROSSCOMPILING)
  include(ExternalProject)
  find_program(_talos_tcl_make NAMES gmake make REQUIRED)
  set(_talos_tcl_install "${PROJECT_BINARY_DIR}/tcl-core")
  set(_talos_tcl_archive "${_talos_tcl_install}/lib/libtcl9.0.a")
  set(_talos_tcl_source)
  if(TALOS_TCL_SOURCE_DIR)
    file(STRINGS "${TALOS_TCL_SOURCE_DIR}/generic/tcl.h" _talos_tcl_version
      REGEX "^#[ \t]*define[ \t]+TCL_PATCH_LEVEL[ \t]+\"")
    if(NOT _talos_tcl_version MATCHES "\"9\\.0\\.4\"")
      message(FATAL_ERROR "TALOS_TCL_SOURCE_DIR must contain Tcl 9.0.4")
    endif()
    set(_talos_tcl_source SOURCE_DIR "${TALOS_TCL_SOURCE_DIR}")
  else()
    set(_talos_tcl_source
      URL "https://codeload.github.com/tcltk/tcl/tar.gz/refs/tags/core-9-0-4"
      URL_HASH SHA256=8c01bac92a9a8ce271b63d3aa28f09cde2c6762d6719ca671cdc8aee25391234
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  endif()
  set(_talos_tcl_cflags "${CMAKE_C_FLAGS} -Os -fPIC -ffunction-sections -fdata-sections")
  if(APPLE)
    if(CMAKE_OSX_SYSROOT)
      string(APPEND _talos_tcl_cflags " -isysroot ${CMAKE_OSX_SYSROOT}")
    endif()
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
      string(APPEND _talos_tcl_cflags " -mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
    endif()
    foreach(architecture IN LISTS CMAKE_OSX_ARCHITECTURES)
      string(APPEND _talos_tcl_cflags " -arch ${architecture}")
    endforeach()
  elseif(CMAKE_SYSROOT)
    string(APPEND _talos_tcl_cflags " --sysroot=${CMAKE_SYSROOT}")
  endif()
  ExternalProject_Add(talos_tcl_core
    ${_talos_tcl_source}
    CONFIGURE_COMMAND "${CMAKE_COMMAND}" -E env
      "CC=${CMAKE_C_COMPILER}" "CFLAGS=${_talos_tcl_cflags}"
      <SOURCE_DIR>/unix/configure --prefix=${_talos_tcl_install}
      --disable-shared --disable-zipfs
    BUILD_COMMAND "${_talos_tcl_make}" -j4 libtcl9.0.a
    INSTALL_COMMAND "${CMAKE_COMMAND}"
      -DSOURCE=<SOURCE_DIR> -DBINARY=<BINARY_DIR> -DDEST=${_talos_tcl_install}
      -P "${PROJECT_SOURCE_DIR}/cmake/InstallTclCore.cmake"
    COMMAND "${_talos_tcl_make}" install-headers
    BUILD_BYPRODUCTS "${_talos_tcl_install}/lib/libtcl9.0.a"
    LOG_CONFIGURE ON LOG_BUILD ON LOG_INSTALL ON)
  ExternalProject_Add_Step(talos_tcl_core stage_scripts
    COMMAND "${CMAKE_COMMAND}"
      -DSOURCE=<SOURCE_DIR> -DBINARY=<BINARY_DIR> -DDEST=${_talos_tcl_install}
      -P "${PROJECT_SOURCE_DIR}/cmake/InstallTclCore.cmake"
    DEPENDEES install
    DEPENDS "${PROJECT_SOURCE_DIR}/cmake/InstallTclCore.cmake")
else()
  message(FATAL_ERROR "UPF needs TALOS_TCL_INSTALL_DIR for this compiler-host toolchain; "
    "or configure with TALOS_ENABLE_UPF=OFF")
endif()
file(MAKE_DIRECTORY "${_talos_tcl_install}/include")
add_library(TalosTclCore STATIC IMPORTED GLOBAL)
set_target_properties(TalosTclCore PROPERTIES
  IMPORTED_LOCATION "${_talos_tcl_archive}"
  INTERFACE_INCLUDE_DIRECTORIES "${_talos_tcl_install}/include")
target_link_libraries(TalosTclCore INTERFACE Threads::Threads ${CMAKE_DL_LIBS} ZLIB::ZLIB)
target_compile_definitions(TalosTclCore INTERFACE STATIC_BUILD)
if(UNIX)
  target_link_libraries(TalosTclCore INTERFACE m)
elseif(WIN32)
  target_link_libraries(TalosTclCore INTERFACE netapi32 user32 userenv ws2_32)
endif()
if(TARGET talos_tcl_core)
  add_dependencies(TalosTclCore talos_tcl_core)
endif()
set(TALOS_TCL_LIBRARY_DIR "${_talos_tcl_install}/lib/tcl9.0")
message(STATUS "UPF embeds static Tcl ${TALOS_TCL_VERSION} core (no Tk or contributed packages)")
