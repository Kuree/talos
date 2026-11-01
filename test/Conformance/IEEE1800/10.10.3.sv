// CLAUSE: unpacked concat nested strings
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef string SQ[$]; string a,b; SQ q;
initial begin
a="A"; b="B"; q='{"0","1"}; q={a,q,{"C",b}}; if(q.size()!=4 || q[0]!="A" || q[1]!="0" || q[2]!="1" || q[3]!="CB") $fatal; q={a,SQ'{"C",b}}; if(q.size()!=3 || q[2]!="B") $fatal;
$display("PASS"); $finish;
end
endmodule
