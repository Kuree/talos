// CLAUSE: Continuous, blocking, nonblocking, procedural continuous and force assignments
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: nonblocking assignments to elements of dynamically sized arrays are not allowed
// CHECK: assign 0{{$}}
// CHECK-NEXT: assign 1{{$}}
// CHECK-NEXT: forced 0{{$}}
// CHECK-NEXT: released 1{{$}}
// CHECK-NEXT: blocking 1 1{{$}}
// CHECK-NEXT: nba before 1 1{{$}}
// CHECK-NEXT: nba after 0 1{{$}}
// CHECK-NEXT: proc assign 1{{$}}
// CHECK-NEXT: proc assign 0{{$}}
// CHECK-NEXT: deassigned 0{{$}}

// Clause 10: one sample of each assignment form, read back after every step.
module top;
  logic v = 0, x = 0, y = 1, pv = 0;
  wire w;
  assign w = v;
  initial begin
    #1 $display("assign %b", w);
    v = 1; #1 $display("assign %b", w);
    force w = 0; #1 $display("forced %b", w);
    release w;   #1 $display("released %b", w);
    x = 1; y = x; $display("blocking %b %b", x, y);
    x <= 0; y <= x; $display("nba before %b %b", x, y);
    #1 $display("nba after %b %b", x, y);
    assign pv = y; #1 $display("proc assign %b", pv);
    y = 0;         #1 $display("proc assign %b", pv);
    deassign pv;
    y = 1;         #1 $display("deassigned %b", pv);
    $finish;
  end
endmodule
