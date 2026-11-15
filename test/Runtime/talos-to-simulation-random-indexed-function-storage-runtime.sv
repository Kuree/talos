// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11, 11.5.1, 7.4.3: indexed part-selects "v[i +: 2]"
// and unpacked array slices are function actuals/targets whose
// exact window is ordered before the call. A result constraint that
// contradicts the sampled window fails about half the draws and rolls the
// object back. Unknown or out-of-bounds window indices make randomize() fail.
// CHECK: up window ordered 1
// CHECK-NEXT: array slice ordered 1
// CHECK-NEXT: slice target ordered 1
// CHECK-NEXT: unsigned index ordered 1
// CHECK-NEXT: invalid windows fail 1

function automatic bit lo_clear(bit [1:0] w);
  return !w[0];
endfunction

function automatic bit first_clear(bit w[2]);
  return !w[0];
endfunction

class Up;
  rand bit [7:0] v;
  rand bit x;
  int i = 3;
  constraint c { x == lo_clear(v[i +: 2]); x == 1'b1; }  // window v[4:3]
endclass

class Arr;
  rand bit y[6];
  rand bit x;
  int i = 2;
  constraint c { x == first_clear(y[i +: 2]); x == 1'b1; }  // y[2:3]
endclass

class Tgt;  // the slice is the result target
  rand bit [7:0] v;
  rand bit [1:0] w;
  int i = 4;
  constraint c { v[i +: 2] == {1'b0, lo_clear(w)}; v[5:4] == 2'b01; }
endclass

class Uns;
  rand bit [7:0] v;
  rand bit x;
  bit [3:0] i = 4'd4;  // unsigned index, window v[5:4]
  constraint c { x == lo_clear(v[i +: 2]); x == 1'b1; }
endclass

class Bad;
  rand bit [7:0] v;
  rand bit x;
  logic [3:0] i;
  constraint c { x == lo_clear(v[i +: 2]); }
endclass

module top;
  Up up = new;
  Arr ar = new;
  Tgt tg = new;
  Uns un = new;
  Bad bd = new;
  int ok, failed;
  bit valid;
  bit [7:0] ov;
  bit oy[6];

  initial begin
    valid = 1;
    repeat (256) begin
      ov = up.v;
      if (up.randomize()) begin
        ok++;
        valid &= up.x == 1 && up.v[3] == 0;
      end else begin
        failed++;
        valid &= up.v == ov;
      end
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "up window %0d/%0d", ok, failed);
    $display("up window ordered 1");

    valid = 1; ok = 0; failed = 0;
    repeat (256) begin
      oy = ar.y;
      if (ar.randomize()) begin
        ok++;
        valid &= ar.x == 1 && ar.y[2] == 0;
      end else begin
        failed++;
        valid &= ar.y == oy;
      end
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "array slice %0d/%0d", ok, failed);
    $display("array slice ordered 1");

    // w is solved first; the target window v[5:4] then needs w[0] == 0 and
    // bit 4 == 1, so half of the draws fail.
    valid = 1; ok = 0; failed = 0;
    repeat (256) begin
      if (tg.randomize()) begin
        ok++;
        valid &= tg.v[5:4] == 2'b01 && tg.w[0] == 0;
      end else failed++;
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "slice target %0d/%0d", ok, failed);
    $display("slice target ordered 1");

    valid = 1; ok = 0; failed = 0;
    repeat (256) begin
      if (un.randomize()) begin
        ok++;
        valid &= un.v[4] == 0;
      end else failed++;
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "unsigned index %0d/%0d", ok, failed);
    $display("unsigned index ordered 1");

    valid = 1;
    bd.i = 4'bx001;  // unknown index
    repeat (8) valid &= !bd.randomize();
    bd.i = 4'd7;  // window v[8:7] leaves the vector
    repeat (8) valid &= !bd.randomize();
    bd.i = 4'd6;  // v[7:6] is the last legal window and can succeed
    valid &= bd.randomize() || bd.randomize() || bd.randomize() ||
             bd.randomize() || bd.randomize() || bd.randomize();
    if (!valid) $fatal(1, "invalid windows");
    $display("invalid windows fail 1");
  end
endmodule
