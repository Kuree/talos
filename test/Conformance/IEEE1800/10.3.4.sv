// CLAUSE: Continuous assignment drive strengths resolve competing drivers; a highz pair is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.3.4/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot combine 'highz0' and 'highz1'
// CHECK: a0 b0 St0 HiZ St0{{$}}
// CHECK-NEXT: a1 b1 St1 Pu1 St1{{$}}
// CHECK-NEXT: a1 b0 StX Pu1 St1{{$}}
// CHECK-NEXT: a0 b1 WeX HiZ St0{{$}}

// 10.3.4: each value drives at its own strength, and the default is (strong1, strong0).
module top;
  logic a = 0, b = 0;
  wire n, plain;
  assign (strong1, weak0) n = a;
  assign (strong0, weak1) n = b;
  wire (pull1, highz0) m = a;
  assign plain = a;
  initial begin
    #1 $display("a0 b0 %v %v %v", n, m, plain);
    a = 1; b = 1; #1 $display("a1 b1 %v %v %v", n, m, plain);
    a = 1; b = 0; #1 $display("a1 b0 %v %v %v", n, m, plain);
    a = 0; b = 1; #1 $display("a0 b1 %v %v %v", n, m, plain);
    $finish;
  end
endmodule
