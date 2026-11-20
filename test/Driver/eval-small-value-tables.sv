// RUN: talos -O3 --vpi=off --mlir-timing %s -o %t 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off %s -o %t.two && %t.two > %t.two.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 | diff -u %t.two.out -

module top;
  function automatic logic [7:0] eight(logic [7:0] v);
    // Unroll an acyclic bit function. Both physical logic planes are inputs.
`define MIX_BYTE(v) ({v[6:0], v[7]} ^ 8'h35 ^ ((v << 3) & (v >> 2)))
    v = `MIX_BYTE(v);
    v = `MIX_BYTE(v);
    v = `MIX_BYTE(v);
    v = `MIX_BYTE(v);
    v = `MIX_BYTE(v);
    v = `MIX_BYTE(v);
    v = `MIX_BYTE(v);
    return `MIX_BYTE(v);
`undef MIX_BYTE
  endfunction
  initial begin
    int unsigned digest;
    logic [7:0] v;
    digest = 0;
    for (int i = 0; i < 256; i++) begin
      v = eight(i[7:0]);
      digest = (digest * 33) ^ v;
    end
    $display("known %08h", digest);
    v = 8'b0010_x010;
    $display("X %b", eight(v));
    v = 8'b11z0_0001;
    $display("Z %b", eight(v));
  end
endmodule
// PLAN: talos finite value functions: tables={{[1-9][0-9]*}}
// CHECK: known 627e6d00
// CHECK-NEXT: X 10x0x11x
// CHECK-NEXT: Z x1xx0x10
