// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null
// RUN: talos -DSEQUENCE -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=SEQUENCE
// RUN: talos -DBRANCH_THEN_SEQUENCE -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=BRANCH
// RUN: talos -DLOOP -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=LOOP
// RUN: talos -DTHIS_TWICE -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=THIS

// IEEE 1800-2023 8.19: an instance constant is assigned once, in the class
// constructor. Assignments along one path add, branches take the maximum and a
// loop body counts twice, so one assignment per branch is legal.
class C;
  const int v;
  const int w;
  function new(int n);
`ifdef SEQUENCE
    v = 1;
    // SEQUENCE: error: instance constant 'C::v' can be assigned more than once in the constructor
    v = 2;
    w = 1;
`elsif BRANCH_THEN_SEQUENCE
    if (n > 0) v = 1; else v = 2;
    // BRANCH: error: instance constant 'C::v' can be assigned more than once in the constructor
    v = 3;
    w = 1;
`elsif LOOP
    // LOOP: error: instance constant 'C::v' can be assigned more than once in the constructor
    for (int i = 0; i < 1; i++) v = i;
    w = 1;
`elsif THIS_TWICE
    v = 1;
    // THIS: error: instance constant 'C::v' can be assigned more than once in the constructor
    this.v = 2;
    w = 1;
`else
    if (n > 0) v = 1; else v = 2;
    case (n) 0: w = 1; 1, 2: w = 2; default: w = 3; endcase
`endif
  endfunction
endclass
module top;
endmodule
