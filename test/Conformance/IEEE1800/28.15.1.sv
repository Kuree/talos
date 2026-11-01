// CLAUSE: Disabled inverted tristate outputs do not override implicit pull nets, while enabling them
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
tri0 a; tri1 b; bit enable=0; notif1 n0(a,1'b0,enable),n1(b,1'b1,enable);
initial begin
#1; if(a!==0 || b!==1) $fatal; enable=1; #1; if(a!==1 || b!==0) $fatal; enable=0; #1; if(a!==0 || b!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
