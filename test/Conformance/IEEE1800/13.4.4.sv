// CLAUSE: function background process
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int x=0;function void f();fork begin #1;x=1;end join_none endfunction
initial begin
f();if(x!=0)$fatal(1,"function blocked");#2;if(x!=1)$fatal(1,"background process");
$display("PASS");$finish;
end
endmodule
