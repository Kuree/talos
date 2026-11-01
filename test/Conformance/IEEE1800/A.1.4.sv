// CLAUSE: Continuous assignment as a module item
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
localparam N=7;wire y;assign y=(N==7);
initial begin #1;if(y!==1)$fatal(1,"result"); $display("PASS");end
endmodule
