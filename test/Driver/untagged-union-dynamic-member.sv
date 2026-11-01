// RUN: not %talos -emit-slang %s -o /dev/null 2>&1 | FileCheck %s
// RUN: %talos -DTAGGED -emit-slang %s -o /dev/null

// IEEE 1800-2023 7.3: dynamic types such as string may appear only in tagged
// unions. Slang v11 rejects the others but accepts a string member of an untagged
// union, so the frontend diagnoses it, even in a typedef no declaration uses.
module top;
`ifdef TAGGED
  typedef union tagged { string s; } U;
`else
  // CHECK: error: IEEE 1800-2023 7.3 forbids a string member in an untagged union
  typedef union { string s; } U;
`endif
endmodule
