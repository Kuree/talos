// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -c -O3 %t/helper.c -o %t/helper.o
// RUN: talos -O3 --vpi=full --mlir-timing %t/design.sv %t/helper.o -o %t.auto 2> %t.log
// RUN: FileCheck %s --check-prefix=PLAN < %t.log
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t.auto 2> %t.diag | FileCheck %s --check-prefix=OUTPUT
// RUN: FileCheck %s --check-prefix=DIAG < %t.diag

// A context import elsewhere in the design conservatively retains the named
// activation (IEEE 1800-2023 9.6.2, 35.5.3). Its runtime control stack is not a
// closed eval body. Checkpoint that complete activation while an independent
// counter executes in the generated eval loop. A persistent real-valued runtime
// consumer requires a shared calendar. A constant export remains callable from
// the context import (35.5.3), with its ordinary return value (13.4.1). It reads
// a package parameter, matching BP's period-query shape.
// A generic-only fallback is insufficient: require actual eval dispatches and
// runtime checkpoints.
// PLAN-NOT: eval closure rejection
// PLAN-NOT: compiling again
// PLAN: talos native eligibility:
// PLAN-NOT: eval closure rejection
// PLAN-NOT: compiling again
// PLAN: talos eval runtime-calendar eligibility: island=1 exact=1 observers=0 inactive-delay=0 dpi-exports=1 constant-query-exports=1 coverage=0 eligible=1
// PLAN: talos eval executor inventory: tier1={{[1-9][0-9]*}} tier2={{[0-9]+}} runtime_checkpoints={{[1-9][0-9]*}}
// PLAN-NOT: eval closure rejection
// PLAN-NOT: compiling again
// PLAN: talos native LLVM inventory:
// PLAN-NOT: eval closure rejection
// PLAN-NOT: compiling again
// DIAG: aot_checkpoints={{[1-9][0-9]*}}
// DIAG-SAME: eval_dispatches={{[1-9][0-9]*}}
// OUTPUT: q=10 fast=30 seen=10.0 ext=7

//--- design.sv
package retained_control_parameters;
  parameter int period = 10;
endpackage

module retained_control;
  bit clk = 0;
  int q = 0;
  int fast = 0;
  real seen = 0.0;
  export "DPI-C" function query_period;
  function int query_period();
    return retained_control_parameters::period;
  endfunction
  import "DPI-C" context function int read_external();
  always #5 clk = ~clk;
  always @(posedge clk) begin : named_body
    q <= q + 1;
  end
  always @(posedge clk) fast = fast + 3;
  initial forever begin
    @(posedge clk);
    seen += 1.0;
  end
  initial begin
    #101;
    $display("q=%0d fast=%0d seen=%0.1f ext=%0d", q, fast, seen, read_external());
    $finish;
  end
endmodule

//--- helper.c
extern int query_period(void);
int read_external(void) { return query_period() - 3; }
