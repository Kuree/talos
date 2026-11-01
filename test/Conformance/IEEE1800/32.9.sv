// CLAUSE: $sdf_annotate omits its optional arguments
// XFAIL: *
// Slang v11 rejects the empty optional arguments that Syntax 32-1 allows ("empty argument not allowed").
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: at 6 y=0{{$}}
// CHECK-NEXT: at 9 y=1{{$}}

// 32.9: module_instance, config_file and log_file may each be empty. The file
// raises the path delay from 1 to 3, which the output's transition time shows.
module delayed_cell(input wire a, output wire y);
  timeunit 1ns; timeprecision 1ns;
  assign y = a;
  specify (a => y) = 1; endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  logic a = 0;
  wire y;
  delayed_cell d(a, y);
  initial begin
    $sdf_annotate("delay.sdf", d, , , "MAXIMUM", );
    #5 a = 1;
    #1 $display("at %0t y=%b", $time, y);
    #3 $display("at %0t y=%b", $time, y);
    $finish;
  end
endmodule
