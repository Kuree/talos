// CLAUSE: DPI task disable propagates and a second export from the disabled import is fatal
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/35.9/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %not %t.exe +export-while-disabled
// CHECK: {{^PASS$}}
// CHECK: attempting a second export
// CHECK-NOT: {{^PASS$}}

module top;
  export "DPI-C" task wait_sv;
  task wait_sv; #5; endtask
  import "DPI-C" context task call_c(input bit call_again);
  import "DPI-C" function int status();
  initial begin : owner
    call_c($test$plusargs("export-while-disabled"));
  end
  initial begin
    #1 disable owner;
    #1;
    if (status() != 1) $fatal(1, "disable protocol");
    $display("PASS");
    $finish;
  end
endmodule
