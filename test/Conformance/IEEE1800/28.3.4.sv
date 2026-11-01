// CLAUSE: primitive array broadcast
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/28.3.4/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 28.3.4: the instance name is optional for a single gate but an array of instances needs one (illegal.sv has an unnamed array).
// DIAG: expected hierarchical instantiation
// CHECK: A y0=0 y1=1 y=1010
// CHECK: B y=zzzz

module top;
  logic a = 1, b = 0, en = 0;  logic [3:0] av = 4'b1010;
  wire y0, y1;  wire [3:0] y;
  and (y0, a, b);                // unnamed single instance: legal
  or g1 (y1, a, b);              // named single instance
  bufif0 g[3:0] (y, av, en);     // an array of instances must be named
  initial begin
    #1; $display("A y0=%b y1=%b y=%b", y0, y1, y);
    en = 1; #1; $display("B y=%b", y);
  end
endmodule
