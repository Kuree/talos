// CLAUSE: p unpacked struct
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

typedef struct {int count; bit valid;} Payload;
module top;
Payload value; string text;
initial begin
value='{count:3,valid:1}; if(value.count!=3 || value.valid!=1) $fatal; text=$sformatf("%p",value); $display("PRINT|value|%s|END",text); if(value.count!=3 || value.valid!=1) $fatal;
$display("PASS"); $finish;
end
endmodule
