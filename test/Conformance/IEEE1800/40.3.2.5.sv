// CLAUSE: $coverage_save does not change coverage, overwrites a name, and reports SV_COV_NOCOV
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=toggle %s -o %t.exe
// RUN: %t.exe
// CHECK: first save=1
// CHECK: state unchanged=1 nonzero=1
// CHECK: collection continues=1
// CHECK: overwrite save=1
// CHECK: merge=1
// CHECK: retrieved latest=1
// CHECK: no such coverage=0

// 40.3.2.5: "Saving coverage shall not have any effect on the state of coverage", "It is not an error to overwrite a
// previously existing name", and SV_COV_NOCOV when "No such coverage is available" (only toggle is instrumented here).
// The count is read in the instance, which excludes the testbench's own variable.
module dut;
  bit q, r;
endmodule
module top;
  dut d();
  int prior;
  initial begin
    #1 d.q = 1; #1 d.q = 0; #1;
    prior = $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d);
    $display("first save=%0d", $coverage_save(`SV_COV_TOGGLE, "save_probe"));
    $display("state unchanged=%0d nonzero=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) == prior, prior > 0);
    #1 d.r = 1; #1 d.r = 0; #1;
    $display("collection continues=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) > prior);
    prior = $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d);
    $display("overwrite save=%0d", $coverage_save(`SV_COV_TOGGLE, "save_probe"));
    void'($coverage_control(`SV_COV_RESET,`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    $display("merge=%0d", $coverage_merge(`SV_COV_TOGGLE, "save_probe"));
    $display("retrieved latest=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) == prior);
    $display("no such coverage=%0d", $coverage_save(`SV_COV_ASSERTION, "save_nocov"));
    $finish;
  end
endmodule
