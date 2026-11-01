// CLAUSE: Indexed part-select used as an assignment target
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit[7:0]n=0;
initial begin n[2+:3]=3'b101;if(n!=8'h14)$fatal(1,"result"); $display("PASS");end
endmodule
