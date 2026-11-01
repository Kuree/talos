// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DNOCONCAT %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: talos -emit-slang -DOPERATOR %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: talos -emit-slang -DPROCEDURAL %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: talos -emit-slang -DNOELEMENT %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: talos -emit-slang -DPACKEDBIT %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: talos -emit-slang -DVARIABLE %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: talos -emit-slang -DVECTORNET %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=ERR

// IEEE 1800-2023 D.3: $getpattern may only be used in a continuous assignment
// whose left-hand side is a concatenation of scalar nets, with a memory element
// argument. The other forms below each break one part of that rule.
module top;
  logic [1:0] mem[1:0];
  logic [1:0] whole;
  integer index;
  wire a, b;
  wire [1:0] vector;
`ifdef NOCONCAT
  assign vector = $getpattern(mem[index]);
`elsif OPERATOR
  assign {a, b} = ~$getpattern(mem[index]);
`elsif PROCEDURAL
  logic [1:0] v;
  initial v = $getpattern(mem[index]);
`elsif NOELEMENT
  assign {a, b} = $getpattern(whole);
`elsif PACKEDBIT
  assign {a} = $getpattern(whole[0]);
`elsif VARIABLE
  logic v0, v1;
  assign {v0, v1} = $getpattern(mem[index]);
`elsif VECTORNET
  assign {vector} = $getpattern(mem[index]);
`else
  assign {a, b} = $getpattern(mem[index]);
`endif
endmodule

// The argument is read like any operand: element select on the index.
// CHECK: simulation.ref.array_element
// CHECK: simulation.ref.load
// The pattern keeps its unknown bits: each net takes a four-state extract.
// CHECK: simulation.logic.extract %{{.*}} from 1 : !simulation.logic<2>
// CHECK-NOT: getpattern
// ERR: $getpattern may only be used in a continuous assignment to a concatenation of scalar nets with a memory element as its argument
