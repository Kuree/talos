// CLAUSE: Toggle coverage control and query over instance and definition scopes (Table 40-2)
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=toggle %s -o %t.exe
// RUN: %t.exe
// CHECK: instance a covered=1 b=0
// CHECK: definition half=1
// CHECK: module excludes below=0
// CHECK: hier includes below=1
// CHECK: check status=1
// CHECK: reset one status=1
// CHECK: after reset a=0
// CHECK: stop definition status=1
// CHECK: stopped a=0 b=1
// CHECK: bad control=-1
// CHECK: bad name=-1
// CHECK: bad name get=-1

// Table 40-1 return values and Table 40-2 scopes: one instance, the named module's instances, and the hierarchy below.
module leaf;
  bit t;
endmodule
module top;
  bit q;
  leaf a(), b();
  initial begin
    #1 a.t = 1; #1 a.t = 0; #1;
    $display("instance a covered=%0d b=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,a) == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,a), $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,b));
    $display("definition half=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,"leaf") * 2 == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,"leaf"));
    $display("module excludes below=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,top));
    $display("hier includes below=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_HIER,top) == $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,a));
    $display("check status=%0d", $coverage_control(`SV_COV_CHECK,`SV_COV_TOGGLE,`SV_COV_HIER,top));
    $display("reset one status=%0d", $coverage_control(`SV_COV_RESET,`SV_COV_TOGGLE,`SV_COV_MODULE,a));
    $display("after reset a=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,a));
    #1 b.t = 1; #1 b.t = 0; #1;
    $display("stop definition status=%0d", $coverage_control(`SV_COV_STOP,`SV_COV_TOGGLE,`SV_COV_MODULE,"leaf"));
    #1 a.t = 1; #1 a.t = 0; #1;
    $display("stopped a=%0d b=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,a), $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,b) == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,b));
    $display("bad control=%0d", $coverage_control(99,`SV_COV_TOGGLE,`SV_COV_MODULE,a));
    $display("bad name=%0d", $coverage_control(`SV_COV_RESET,`SV_COV_TOGGLE,`SV_COV_MODULE,"no_such_module"));
    $display("bad name get=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,"no_such_module"));
    $finish;
  end
endmodule
