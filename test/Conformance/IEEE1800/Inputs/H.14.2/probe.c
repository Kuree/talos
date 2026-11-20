#include "svdpi.h"

int exchange(const svOpenArrayHandle b1, const svOpenArrayHandle b2,
             const svOpenArrayHandle b3, const svOpenArrayHandle b4,
             const svOpenArrayHandle l1, const svOpenArrayHandle l2,
             const svOpenArrayHandle l3, const svOpenArrayHandle l4) {
  svBitVec32 bits[4][SV_CANONICAL_SIZE(33)] = {0};
  svLogicVec32 logic[4][SV_CANONICAL_SIZE(33)] = {0};
  svGetBitArrElem1Vec32(bits[0], b1, 2);
  svGetBitArrElem2Vec32(bits[1], b2, 2, -2);
  svGetBitArrElem3Vec32(bits[2], b3, 2, -2, 6);
  svGetBitArrElemVec32(bits[3], b4, 2, -2, 6, 5);
  svGetLogicArrElem1Vec32(logic[0], l1, 2);
  svGetLogicArrElem2Vec32(logic[1], l2, 2, -2);
  svGetLogicArrElem3Vec32(logic[2], l3, 2, -2, 6);
  svGetLogicArrElemVec32(logic[3], l4, 2, -2, 6, 5);
  for (unsigned i = 0; i < 4; ++i) {
    if (bits[i][0] != 0x12345670u + i || (bits[i][1] & 1) != 1 ||
        logic[i][0].c != 0x7654f200u + i || logic[i][0].d != 0x0000f0f0u ||
        (logic[i][1].c & 1) != 0 || (logic[i][1].d & 1) != 1)
      return 0;
    bits[i][0] = 0x89abcdf0u + i;
    bits[i][1] = 0;
    logic[i][0].c = 0x11f02200u + i;
    logic[i][0].d = 0x00ff0000u;
    logic[i][1].c = logic[i][1].d = 1;
  }
  svPutBitArrElem1Vec32(b1, bits[0], 2);
  svPutBitArrElem2Vec32(b2, bits[1], 2, -2);
  svPutBitArrElem3Vec32(b3, bits[2], 2, -2, 6);
  svPutBitArrElemVec32(b4, bits[3], 2, -2, 6, 5);
  svPutLogicArrElem1Vec32(l1, logic[0], 2);
  svPutLogicArrElem2Vec32(l2, logic[1], 2, -2);
  svPutLogicArrElem3Vec32(l3, logic[2], 2, -2, 6);
  svPutLogicArrElemVec32(l4, logic[3], 2, -2, 6, 5);
  return 1;
}
