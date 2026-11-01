// CLAUSE: $reset, $reset_count, and $reset_value optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.8: $reset(0,42) returns to time zero with $reset_count()==1 and $reset_value()==42.
// CHECK: FIRST
// CHECK: AFTER count=1 value=42 t=0

module top;
  initial begin
    if ($reset_count() == 0) begin
      $display("FIRST");
      #5 $reset(0, 42);
    end else
      $display("AFTER count=%0d value=%0d t=%0t", $reset_count(), $reset_value(), $time);
  end
endmodule
