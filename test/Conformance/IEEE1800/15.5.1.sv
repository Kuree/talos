// CLAUSE: event merge before wait
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
event a,b; bit seen;
initial begin
a=b; if(a!==b) $fatal; fork begin @a; seen=1; end join_none #1; ->b; #1; if(!seen) $fatal;
$display("PASS"); $finish;
end

endmodule
