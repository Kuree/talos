// RUN: %split-file %s %t
// RUN: cd %t && talos -O1 design.sv -o %t/sim
// RUN: cd %t && %t/sim
// RUN: FileCheck %s --check-prefix=CLOSE < %t/close.evcd
// RUN: FileCheck %s --check-prefix=LIMIT < %t/limit.evcd

// IEEE 1800-2023 21.7.3.6.1: $vcdclose records the final simulation time when
// the extended VCD file closes. 21.7.3.4: reaching $dumpportslimit stops the
// dumping and inserts a comment that the size limit was attained.

//--- design.sv
module cell_t(output reg q = 0);
endmodule
module top;
  wire q;
  cell_t dut(q);
  initial begin
    $dumpports(dut, "close.evcd");
    $dumpports(dut, "limit.evcd");
    $dumpportslimit(64, "limit.evcd");
    repeat (5) #1 dut.q = ~dut.q;
    #2 $finish;
  end
endmodule

// CLOSE: $enddefinitions
// CLOSE: $vcdclose #7 $end
// CLOSE-NOT: {{.}}

// LIMIT-NOT: $enddefinitions $end
// LIMIT: $comment dumpports limit of 64 bytes reached $end
// LIMIT-NEXT: $vcdclose #{{[0-9]+}} $end
// LIMIT-NOT: {{.}}
