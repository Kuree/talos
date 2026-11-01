// CLAUSE: $scope optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.11: after $scope(top.k) the scope listing shows the objects of k (task kt), not those of top.
// CHECK: BEGIN
// CHECK: kt
// CHECK: END

module kid; task kt; endtask endmodule
module top;
  kid k();
  initial begin
    $display("BEGIN");
    $scope(top.k);
    $showscopes(0);
    $display("END");
  end
endmodule
