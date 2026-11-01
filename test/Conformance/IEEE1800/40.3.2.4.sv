// CLAUSE: $coverage_merge retrieves saved coverage by name, and an unknown name is an error
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=toggle %s -o %t.exe
// RUN: %t.exe
// CHECK: saved half=1
// CHECK: save status=1
// CHECK: reset status=1
// CHECK: after reset get=0
// CHECK: live half=1
// CHECK: merge status=1
// CHECK: union full=1
// CHECK: unknown name=-1

// 40.3.2.4: "loads and merges coverage data". After a reset only r toggles, so the count can reach the maximum only if
// the merge brings q back. "If name does not exist ... an error shall occur", reported as SV_COV_ERROR. The bits are in
// their own instance so that the testbench's variable is not part of the count.
module dut;
  bit q, r;
endmodule
module top;
  dut d();
  initial begin
    #1 d.q = 1; #1 d.q = 0; #1;
    $display("saved half=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) * 2 == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    $display("save status=%0d", $coverage_save(`SV_COV_TOGGLE, "merge_probe"));
    $display("reset status=%0d", $coverage_control(`SV_COV_RESET,`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    $display("after reset get=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    #1 d.r = 1; #1 d.r = 0; #1;
    $display("live half=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) * 2 == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    $display("merge status=%0d", $coverage_merge(`SV_COV_TOGGLE, "merge_probe"));
    $display("union full=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    $display("unknown name=%0d", $coverage_merge(`SV_COV_TOGGLE, "no_such_saved_name"));
    $finish;
  end
endmodule
