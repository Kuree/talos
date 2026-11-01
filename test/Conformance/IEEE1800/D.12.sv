// CLAUSE: $showscopes optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.12: $showscopes(0) lists the current level only (kidinst); a nonzero argument also lists objects below it (deepblk).
// CHECK: L0
// CHECK: kidinst
// CHECK-NOT: deepblk
// CHECK: L1
// CHECK: deepblk
// CHECK: END

module kid; task kt; endtask  initial begin : deepblk end endmodule
module top;
  kid kidinst();
  initial begin
    $display("L0");  $showscopes(0);
    $display("L1");  $showscopes(1);
    $display("END");
  end
endmodule
