// CLAUSE: A disabled tristate drivesZ into a UDP which treats that input asX; enabling the gate perm
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

primitive identity(output q,input a); table 0:0; 1:1; x:x; endtable endprimitive
module top; bit enable=0; logic data=1; wire bus_value,q; bufif1 b(bus_value,data,enable); identity u(q,bus_value);
initial begin #1; if(bus_value!==1'bz || q!==1'bx) $fatal; enable=1; #1; if(q!==1) $fatal; data=0; #1; if(q!==0) $fatal; $display("PASS"); $finish; end endmodule
