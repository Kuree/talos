// RUN: talos -O0 --native-scheduler=generic %s -o %t.generic
// RUN: %t.generic | FileCheck %s
// RUN: talos -O0 --vpi=off %s -o %t.default
// RUN: %t.default | FileCheck %s

// A delayed net (IEEE 1800-2023 28.16) keeps state reads on the runtime state
// ABI when direct static state is off. Capture specialization makes the level
// UDP's output driver handle a constant; its contribution stores must take
// the same ABI, or the level-sensitive hold row ('-', 29.3.6, 29.5) reads the
// stale initial value (29.7) back through the ABI.
`timescale 1ns / 1ns
primitive udp_level(output reg q = 1'b1, input d, enable);
  table
    ? 0 : ? : -;
    0 1 : ? : 0;
    1 1 : ? : 1;
  endtable
endprimitive

module native_driver_state_abi;
  logic d, enable, other = 0;
  wire level_q;
  wire #5 slow;
  udp_level level_instance(level_q, d, enable);
  assign slow = other;
  initial begin
    d = 1;
    enable = 0;
    #1 enable = 1;
    #1 d = 0;
    #1 enable = 0;
    d = 1;
    #1 $display("hold q=%b", level_q);
  end
endmodule

// CHECK: hold q=0
