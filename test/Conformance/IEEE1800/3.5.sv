// CLAUSE: virtual interface selection
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface I; int value=0; endinterface
module top;
  I a(); I b(); virtual I selected;
  initial begin
    selected=a; selected.value=7; selected=b; selected.value=9;
    if(a.value!=7 || b.value!=9) $fatal(1,"virtual interface aliases");
    $display("PASS"); $finish;
  end
endmodule
