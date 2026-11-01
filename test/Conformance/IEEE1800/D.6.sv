// CLAUSE: $list optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.6: $list prints the source declarations of the named scope (it contains counter).
// CHECK: BEGIN
// CHECK: counter
// CHECK: END

module top;
  int counter;
  initial begin
    $display("BEGIN");
    $list(top);
    $display("END");
  end
endmodule
