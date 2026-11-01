// CLAUSE: Program-owned exit stops its own caller and sibling initial thread while another program r
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

program doomed;
 initial begin #1; $exit(); $fatal(1,"exit caller continued"); end
 initial begin #2; $fatal(1,"exit sibling survived"); end
endprogram
program keeper;
 initial begin #3; $display("PASS"); $finish; end
endprogram
module top; doomed d(); keeper k(); endmodule
