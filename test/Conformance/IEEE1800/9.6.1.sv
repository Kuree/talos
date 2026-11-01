// CLAUSE: wait fork child control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit child;
initial begin
fork begin #1; child=1; end join_none wait fork; if($time!=1 || child!=1) $fatal;
$display("PASS"); $finish;
end

endmodule
