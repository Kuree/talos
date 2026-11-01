// CLAUSE: statement syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 12.3: null and labelled statements are legal statements and do not alter the surrounding flow.
// CHECK: v=20 n=3

module top;
  int v, n;
  initial begin
    v = 1;
    ;                              // null statement
    lbl: v = v + 1;                // labelled statement
    lbl2: begin v = v * 10; end    // labelled block
    if (v == 20) ; else v = 0;     // null if-arm
    for (int i = 0; i < 5; i++) ;  // null loop body
    repeat (3) n++;
    $display("v=%0d n=%0d", v, n);
  end
endmodule
