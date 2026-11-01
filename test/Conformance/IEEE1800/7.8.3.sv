// CLAUSE: class index
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C;endclass
module top;C c;int a[C];initial begin c=new;a[c]=7;if(a[c]!=7)$fatal(1,"class key");$display("PASS");$finish;end endmodule
