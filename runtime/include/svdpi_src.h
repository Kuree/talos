/*
 * IEEE 1800-2023 H.14.3: source-level compatibility include file for SV3.1a
 * applications. Talos does not define an array type, as the clause requires.
 */
#ifndef INCLUDED_SVDPI_SRC
#define INCLUDED_SVDPI_SRC

#include "svdpi.h"

#define SV_BIT_PACKED_ARRAY(WIDTH, NAME)                                       \
  struct {                                                                     \
    svBitVec32 __unnamed[SV_CANONICAL_SIZE(WIDTH)];                            \
  } NAME

#define SV_LOGIC_PACKED_ARRAY(WIDTH, NAME)                                     \
  struct {                                                                     \
    svLogicVec32 __unnamed[SV_CANONICAL_SIZE(WIDTH)];                          \
  } NAME

#endif
