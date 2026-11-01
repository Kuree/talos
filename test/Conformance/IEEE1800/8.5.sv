// CLAUSE: class struct copy
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C;int n;endclass
module top;typedef struct{int n;}S;S x,y;C a,b;initial begin a=new;a.n=1;b=a;b.n=2;x.n=1;y=x;y.n=2;if(a.n!=2||x.n!=1)$fatal(1,"handle versus value copy");$display("PASS");$finish;end endmodule
