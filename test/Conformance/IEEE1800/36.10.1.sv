// CLAUSE: vpi_chk_error reports an error from the previous routine, with detail, and clears after a good call
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/36.10.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: bad call error=1 level_set=1 message_set=1
// CHECK: good call type=1 error=0
// 36.10.1: it "shall return a nonzero value if an error occurred in the previously called VPI routine".

module top;
  int n = 7;
  import "DPI-C" context function void probe();
  initial begin
    probe();
    $finish;
  end
endmodule
