// CLAUSE: array port positional mapping
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child(input integer a[2:1],output integer b[1:2]);
  assign b[1]=a[2]; assign b[2]=a[1];
endmodule
module top;
  integer a[4:5]='{10,20}; wire integer b[9:8];
  child c(a,b);
  initial begin #1; if(b[9]!=10 || b[8]!=20) $fatal(1,"array port map b=%p",b); $display("PASS"); $finish; end
endmodule
