// CLAUSE: mailbox bounded put unblocks
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
mailbox #(int) m; int v; bit done;
initial begin
m=new(1); m.put(7); fork begin m.put(9); done=1; end join_none #1; if(done || m.num()!=1) $fatal; m.get(v); if(v!=7) $fatal; #1; if(!done || m.num()!=1) $fatal; m.get(v); if(v!=9) $fatal;
$display("PASS"); $finish;
end

endmodule
