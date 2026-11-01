// CLAUSE: always_ff updates on its event with nonblocking assignments; a missing event control is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.4/no_event.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.4/two_events.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/9.2.2.4/other_driver.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: always_ff procedure must have one and only one event control
// DIAG: always_ff procedure must have one and only one event control
// DIAG: driven by always_ff procedure cannot be written to by any other process
// CHECK: q=1 x=2 y=1{{$}}
// CHECK-NEXT: q=2 x=1 y=2{{$}}
// CHECK-NEXT: reset q=0{{$}}
// CHECK-NEXT: q=0 x=2 y=1{{$}}
// CHECK-NEXT: q=1 x=1 y=2{{$}}

// 9.2.2.4: the iff term blocks the clock while reset is high, the reset edge still fires, and x and y swap cleanly.
module top;
  logic clock = 0, reset = 0;
  int q = 0, x = 1, y = 2;
  always_ff @(posedge clock iff reset == 0 or posedge reset)
    q <= reset ? 0 : q + 1;
  always_ff @(posedge clock) begin
    x <= y;
    y <= x;
  end
  task edge_();
    #1 clock = 1;
    #1 clock = 0;
    #1 $display("q=%0d x=%0d y=%0d", q, x, y);
  endtask
  initial begin
    edge_();
    edge_();
    reset = 1;
    #1 $display("reset q=%0d", q);
    edge_();
    reset = 0;
    edge_();
    $finish;
  end
endmodule
