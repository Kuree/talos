// CLAUSE: mailbox typed string fifo
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
mailbox #(string) m; string v;
initial begin
m=new; m.put("one"); if(m.try_put("two")<=0 || m.try_put("three")<=0 || m.num()!=3) $fatal; m.peek(v); if(v!="one" || m.num()!=3) $fatal; m.get(v); if(v!="one") $fatal; m.get(v); if(v!="two") $fatal; m.get(v); if(v!="three" || m.num()!=0) $fatal;
$display("PASS"); $finish;
end

endmodule
