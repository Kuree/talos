// CLAUSE: `default_trireg_strength sets relative trireg charge strength and rejects values above 250
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/E.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: default_trireg_strength
// CHECK: 1 1{{$}}
// CHECK-NEXT: 0 0{{$}}

// E.3: the integer is the relative strength of the capacitance, so when the nets share charge the larger one wins,
// including within one charge strength level (100 and 200). Ignoring the directive leaves equal nets and x x.
`default_trireg_strength 250
module c250; trireg t; endmodule
`default_trireg_strength 1
module c1; trireg t; endmodule
`default_trireg_strength 100
module c100; trireg t; endmodule
`default_trireg_strength 200
module c200; trireg t; endmodule
`resetall
module top;
  logic one = 1, zero = 0, en = 1, connect = 0;
  c250 big();
  c1 little();
  c100 less();
  c200 more();
  bufif1 (big.t, one, en);
  bufif1 (little.t, zero, en);
  bufif1 (less.t, one, en);
  bufif1 (more.t, zero, en);
  tranif1 (big.t, little.t, connect);
  tranif1 (less.t, more.t, connect);
  initial begin
    #1 en = 0;
    #1 connect = 1;
    #1 $display("%b %b", big.t, little.t);
    $display("%b %b", less.t, more.t);
    $finish;
  end
endmodule
