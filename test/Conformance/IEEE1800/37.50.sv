// CLAUSE: Concurrent assertion: the actual clocking event whether explicit or inferred, disable condition, property, else statement and cover sequence flag
// XFAIL: *
// assertion inferred, event and property fields report -1 or null
// RUN: %clang -c -fPIC %S/Inputs/37.50/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: top.explicit_a type=vpiAssert full=top.explicit_a inferred=0 event=posedge clk disable=rst property=vpiPropertySpec else=vpiSysTaskCall
// CHECK: top.inferred_a type=vpiAssert full=top.inferred_a inferred=1 event=negedge clk disable=null property=vpiPropertySpec else=null
// CHECK: top.cov_s type=vpiCover cover_sequence=1
// CHECK: top.cov_p type=vpiCover cover_sequence=0

// Detail 1: inferred_a's event is the default clocking's negedge clk, not the explicit posedge clk.
module top;
  logic clk = 0, rst = 0, a = 1, b = 1;
  default clocking cb @(negedge clk);
  endclocking
  explicit_a: assert property (@(posedge clk) disable iff (rst) a |-> b) else $error("failed");
  inferred_a: assert property (a);
  cov_s: cover sequence (@(posedge clk) a);
  cov_p: cover property (@(posedge clk) a);
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
