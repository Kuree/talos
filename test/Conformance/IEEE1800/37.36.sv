// CLAUSE: UDP: a UDP instance and its definition give the comb or sequential type, input count, table entries, initial statement and output value
// XFAIL: *
// UDP definitions and instances report def=null and value=z
// RUN: %clang -c -fPIC %S/Inputs/37.36/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: udp type=vpiUdp def=u_and comb=1 seq=0 value=1
// CHECK: defn type=vpiUdpDefn def=u_and comb=1 seq=0 inputs=2 initial=0
// CHECK: io y
// CHECK: io a
// CHECK: io b
// CHECK: entry size=3 text=11:1{{;?}}
// CHECK: entry size=3 text=0?:0{{;?}}
// CHECK: entry size=3 text=?0:0{{;?}}
// CHECK: entries=3
// CHECK: udp type=vpiUdp def=u_ff comb=0 seq=1 value=1
// CHECK: defn type=vpiUdpDefn def=u_ff comb=0 seq=1 inputs=2 initial=1
// CHECK: entry size=4 text=0r:?:0{{;?}}
// CHECK: entries=4

primitive u_and(output y, input a, input b);
  table
    1 1 : 1;
    0 ? : 0;
    ? 0 : 0;
  endtable
endprimitive
primitive u_ff(output reg q, input d, input clk);
  initial q = 1'b0;
  table
    0 r : ? : 0;
    1 r : ? : 1;
    ? f : ? : -;
    * ? : ? : -;
  endtable
endprimitive
// The flop's value 1 can only come from the clock edge that samples d, against an initial 0.
module top;
  logic a = 1, b = 1, d = 1, clk = 0;
  wire y, q;
  u_and ua(y, a, b);
  u_ff uf(q, d, clk);
  import "DPI-C" context function void probe();
  initial begin
    #1 clk = 1;
    #1 probe();
    $finish;
  end
endmodule
