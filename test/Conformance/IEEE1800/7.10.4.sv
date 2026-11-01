// CLAUSE: queue concat update
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int q[$]='{1};
initial begin
q={q,2};if(q.size()!=2||q[1]!=2)$fatal(1,"queue concatenation update");
$display("PASS");$finish;
end
endmodule
