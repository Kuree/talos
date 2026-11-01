// CLAUSE: Bit-selects and part-selects address by range; out of bounds and X read X; variable width rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.5.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: reference to non-constant variable 'w' is not allowed in a constant expression
// CHECK: in range 1{{$}}
// CHECK-NEXT: out of bounds x 0{{$}}
// CHECK-NEXT: x index x 0{{$}}
// CHECK-NEXT: fixed 0100 00010{{$}}
// CHECK-NEXT: indexed 78 56 12 34 03{{$}}
// CHECK-NEXT: partly out xx00{{$}}
// CHECK-NEXT: fully out xxxx{{$}}
// CHECK-NEXT: x base xx{{$}}
// CHECK-NEXT: write partly out c4{{$}}
// CHECK-NEXT: write fully out c4{{$}}

// 11.5.1: an invalid address reads x for 4-state and 0 for 2-state values; writes affect in-range bits only.
module top;
  logic [7:0] vect = 4;
  bit [7:0] two = 8'hff;
  logic [31:0] a_vect = 32'h12345678;
  logic [0:31] b_vect = 32'h12345678;
  logic [63:0] dword = 64'h0807060504030201;
  logic [3:0] xidx = 'x;
  int addr = 2, sel = 2;
  initial begin
    $display("in range %b", vect[addr]);
    addr = 9;
    $display("out of bounds %b %b", vect[addr], two[addr]);
    $display("x index %b %b", vect[xidx], two[xidx]);
    $display("fixed %b %b", vect[3:0], vect[5:1]);
    $display("indexed %h %h %h %h %h", a_vect[0+:8], a_vect[15-:8], b_vect[0+:8], b_vect[15-:8], dword[8*sel+:8]);
    sel = 6;
    $display("partly out %b", vect[sel+:4]);
    sel = 20;
    $display("fully out %b", vect[sel+:4]);
    $display("x base %b", vect[xidx+:2]);
    sel = 6;
    vect[sel+:4] = 4'hf;
    $display("write partly out %h", vect);
    sel = 20;
    vect[sel+:4] = 4'h0;
    vect[xidx+:2] = 2'b00;
    $display("write fully out %h", vect);
    $finish;
  end
endmodule
