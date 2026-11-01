// CLAUSE: Coverage API: control and query toggle coverage with the SV_COV constants
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=toggle %s -o %t.exe
// RUN: %t.exe
// CHECK: collected half=1
// CHECK: reset status=1
// CHECK: after reset get=0
// CHECK: recollected half=1
// CHECK: stop status=1
// CHECK: stopped half=1
// CHECK: start status=1
// CHECK: restarted full=1

// 40.3.2.1: reset, stop and start act on what $coverage_get reports. Bit q is fully toggled and r not, so q gives half
// of the maximum under any per-bit count (40.2.2). While stopped, toggling r must not move the number.
module top;
  bit q, r;
  initial begin
    #1 q = 1; #1 q = 0; #1;
    $display("collected half=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,top) * 2 == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    $display("reset status=%0d", $coverage_control(`SV_COV_RESET,`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    $display("after reset get=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    #1 q = 1; #1 q = 0; #1;
    $display("recollected half=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,top) * 2 == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    $display("stop status=%0d", $coverage_control(`SV_COV_STOP,`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    #1 r = 1; #1 r = 0; #1;
    $display("stopped half=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,top) * 2 == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    $display("start status=%0d", $coverage_control(`SV_COV_START,`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    #1 r = 1; #1 r = 0; #1;
    $display("restarted full=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,top) == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
