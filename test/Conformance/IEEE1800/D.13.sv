// CLAUSE: $showvars optional interface
// XFAIL: *
// Optional Annex D interface; the compiler does not implement $showvars.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.13: $showvars prints a status line for n (the exact layout is tool specific).
// CHECK: BEGIN
// CHECK: n
// CHECK: END

module top;
  reg [3:0] n = 4'b10x1;
  initial begin
    $display("BEGIN");
    $showvars(n);
    $display("END");
  end
endmodule
