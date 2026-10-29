// RUN: talos -O3 --forward-copies=off %s -o %t.base && %t.base > %t.base.out
// RUN: FileCheck %s < %t.base.out
// RUN: talos -O3 %s -o %t.native
// RUN: %t.native > %t.native.out
// RUN: diff -u %t.base.out %t.native.out
// RUN: talos -O3 --execution-tier=bytecode %s -o %t.bytecode
// RUN: %t.bytecode > %t.bytecode.out
// RUN: diff -u %t.base.out %t.bytecode.out

// IEEE 1800-2023 6.8: static initializers read declaration defaults before
// continuous assignments begin. The later reader must still see the computed
// value, and forwarding must preserve explicit state-domain conversions.
module forward_storage_expression;
  logic [3:0] init_source = 4'ha;
  logic [3:0] init_sink;
  assign init_sink = init_source ^ 4'hf;
  logic [3:0] captured_default = init_sink;

  logic [7:0] source;
  bit [7:0] bit_source;
  logic [7:0] stored;
  bit [7:0] narrowed;
  logic [7:0] widened;
  assign stored = source ^ 8'h5a;
  assign narrowed = source;
  assign widened = bit_source ^ 8'h3c;
  logic [7:0] result, wide_result;
  bit [3:0] bit_slice;
  always_comb begin
    result = stored;
    bit_slice = narrowed[5:2];
    wide_result = widened;
  end

  logic a, b, c;
  logic selected;
  assign selected = (a && b) || (c && ~b);
  logic selected_result;
  always_comb selected_result = selected;

  // A side effect in a short-circuit arm must remain conditional.
  logic enabled;
  function automatic logic effect();
    $display("effect");
    return 1'b1;
  endfunction
  wire effect_result = enabled && effect();

  logic [7:0] forced;
  assign forced = source ^ 8'h5a;

  initial begin
    source = 8'h00; bit_source = 8'h00;
    a = 0; b = 0; c = 0; enabled = 0;
    #1;
    $display("init=%b/%b data=%h/%h/%h selected=%b effect=%b",
             captured_default, init_sink, result, bit_slice, wide_result,
             selected_result, effect_result);
    source = 8'hff; bit_source = 8'hff;
    a = 1; b = 1; enabled = 1;
    #1;
    $display("data=%h/%h/%h selected=%b effect=%b",
             result, bit_slice, wide_result, selected_result, effect_result);
    source = 8'bxz10_01zx; a = 1'bx; enabled = 1'bx;
    #1;
    $display("data=%b/%b selected=%b effect=%b", result, bit_slice,
             selected_result, effect_result);
    force forced = 8'h11;
    #1;
    $display("forced=%h", forced);
    release forced;
    source = 8'h33;
    #1;
    $display("released=%h", forced);
    $finish;
  end
endmodule

// CHECK: init=xxxx/0101 data=5a/0/3c selected=0 effect=0
// CHECK-NEXT: effect
// CHECK-NEXT: data=a5/f/c3 selected=1 effect=1
// CHECK-NEXT: effect
// CHECK-NEXT: data=xx1111xx/1001 selected=x effect=x
// CHECK-NEXT: forced=11
// CHECK-NEXT: released=69
