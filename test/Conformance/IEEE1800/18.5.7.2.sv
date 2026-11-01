// CLAUSE: constraint array reduction
// XFAIL: *
// Array reduction calls in constraints are not lowered for the solver.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class R;rand int a[2];constraint c {foreach(a[i])a[i] inside {[0:3]};a.sum()==5;}endclass
module top;
R r;
initial begin
r=new;if(!r.randomize() || r.a.sum()!=5)$fatal;
$display("PASS");$finish;
end
endmodule
