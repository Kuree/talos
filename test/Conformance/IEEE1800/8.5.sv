// CLAUSE: class struct copy
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

// A property of any type holds what was last stored: a shortreal, and a known value over an earlier X or Z.
class P;shortreal r;logic[3:0] l;endclass
class C;int n;endclass
module top;typedef struct{int n;}S;S x,y;C a,b;P p;initial begin p=new;p.r=1.5;if(p.r!=1.5)$fatal(1,"shortreal");p.l=4'bxz01;p.l=4'b1010;if(p.l!==4'b1010)$fatal(1,"unknown plane");p.l=4'bxz01;p.l<=4'b0110;#1;if(p.l!==4'b0110)$fatal(1,"nonblocking");p.l=4'bxz01;p.l[1:0]<=2'b10;#1;if(p.l!==4'bxz10)$fatal(1,"masked nonblocking");p.r<=2.5;#1;if(p.r!=2.5)$fatal(1,"shortreal nonblocking");a=new;a.n=1;b=a;b.n=2;x.n=1;y=x;y.n=2;if(a.n!=2||x.n!=1)$fatal(1,"handle versus value copy");$display("PASS");$finish;end endmodule
