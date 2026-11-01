// CLAUSE: sv_vpi_user.h's assertion callback delivers s_vpi_attempt_info for an attempt in simulation
// XFAIL: *
// The runtime does not provide vpi_register_assertion_cb, which sv_vpi_user.h declares.
// RUN: %clang -c -fPIC %S/Inputs/M.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: success t=1 attempt start t=1
// Annex M declares s_vpi_attempt_info and vpi_register_assertion_cb; 39.4.2 gives the callback's meaning.

module top;
  bit clk;
  check: assert property (@(posedge clk) 1'b1);
  import "DPI-C" context function void probe();
  initial begin
    probe();
    #1 clk = 1;
    #1 $finish;
  end
endmodule
