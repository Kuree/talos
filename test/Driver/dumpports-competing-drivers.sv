// RUN: %split-file %s %t
// RUN: cd %t && talos -O1 design.sv -o %t/sim
// RUN: cd %t && %t/sim
// RUN: FileCheck %s < %t/ports.evcd

// IEEE 1800-2023 21.7.4.3.2: competing input (outside) and output (inside)
// drivers resolve to a conflict state. A strong input over a weak output is
// u/d with the input strength, a weak input under a strong output is h/l with
// the output strength, whatever the two values are. Equal values in the same
// strength range are the conflict states 0/1 at the stronger strength.

//--- design.sv
module weak_out(inout wire q); assign (weak0, weak1) q = 0; endmodule
module weak_one(inout wire q); assign (weak0, weak1) q = 1; endmodule
module strong_out(inout wire q); assign (strong0, strong1) q = 1; endmodule
module pull_out(inout wire q); assign (pull0, pull1) q = 1; endmodule
module top;
  wire a, b, c, d, e;
  assign (strong0, strong1) a = 1;
  assign (weak0, weak1) b = 0;
  assign (strong0, strong1) c = 1;
  assign (strong0, strong1) d = 1;
  assign (weak0, weak1) e = 1;
  weak_out w(a);
  strong_out s(b);
  pull_out p(c);
  weak_one o(d);
  strong_out t(e);
  initial begin
    $dumpports(w, "ports.evcd");
    $dumpports(s, "ports.evcd");
    $dumpports(p, "ports.evcd");
    $dumpports(o, "ports.evcd");
    $dumpports(t, "ports.evcd");
    #2 $finish;
  end
endmodule

// CHECK: pu 0 6
// CHECK: ph 0 6
// CHECK: p1 0 6
// CHECK: pu 0 6
// CHECK: ph 0 6
