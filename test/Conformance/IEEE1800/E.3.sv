// CLAUSE: `default_trireg_strength sets relative trireg charge strength and rejects values above 250
// XFAIL: *
// 251 is now rejected, but the strengths never reach charge sharing: trireg charge uses only small/medium/large on the signal-strength scale, with no 0..250 capacitance scale.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/E.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: default_trireg_strength
// CHECK: 1 1{{$}}

// E.3: the integer is the relative strength of the capacitance, so when the nets share charge the larger one wins.
// Ignoring the directive leaves two equal nets and x x.
module top;
  logic a = 1, b = 0, en = 1, connect = 0;
`default_trireg_strength 250
  trireg big;
`default_trireg_strength 1
  trireg little;
  bufif1 (big, a, en);
  bufif1 (little, b, en);
  tranif1 (big, little, connect);
  initial begin
    #1 en = 0;
    #1 connect = 1;
    #1 $display("%b %b", big, little);
    $finish;
  end
endmodule
