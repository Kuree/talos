// CLAUSE: Built-in utilities
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins clause 20 samples: bit-vector system functions return computed values and $finish stops the later process.
// CHECK: A clog2=10 ones=4 onehot=1 unk=1
// CHECK-NOT: LATE

module top;
  logic [7:0] v = 8'b0110_1100;  logic [3:0] u = 4'b10x0;
  initial begin
    $display("A clog2=%0d ones=%0d onehot=%b unk=%b", $clog2(1000), $countones(v), $onehot(8'b0001_0000), $isunknown(u));
    #3 $finish;
  end
  initial begin #7; $display("LATE"); end
endmodule
