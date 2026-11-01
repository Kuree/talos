// CLAUSE: triage stream packed unpack control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
struct packed {bit data;} r;
initial begin
{>>{r}}=1'b1; if(r.data!=1) $fatal;
$display("PASS"); $finish;
end
endmodule
