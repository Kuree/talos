// CLAUSE: memory text roundtrip
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [7:0] source_mem[0:2],target_mem[0:2];
initial begin
 $readmemh("fixture.hex",source_mem);
 if(source_mem[0]!==8'h12 || source_mem[1]!==8'h34 || source_mem[2]!==8'h56) $fatal;
 $writememh("round.hex",source_mem);
 $readmemh("round.hex",target_mem);
 foreach(target_mem[i]) if(target_mem[i]!==source_mem[i]) $fatal;
 $display("PASS"); $finish;
end
endmodule
