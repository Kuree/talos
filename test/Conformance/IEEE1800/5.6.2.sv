// CLAUSE: Keywords are lowercase and an escape makes a plain identifier; a keyword as a name is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.6.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: expected a declaration name
// CHECK: 1 2 3 4{{$}}

// 5.6.2: three different names built from the keyword wire, and one more escaped keyword.
module top;
  int WIRE = 1;
  int Wire = 2;
  int \wire = 3;
  int \module = 4;
  initial begin
    $display("%0d %0d %0d %0d", WIRE, Wire, \wire , \module );
    $finish;
  end
endmodule
