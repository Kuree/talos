// CLAUSE: $input optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.4: commands in the file run (it displays FROM_CMD) and input then returns to the terminal.
// CHECK: FROM_CMD
// CHECK: AFTER

module top;
  initial begin
    $input("commands.txt");
    $display("AFTER");
  end
endmodule
