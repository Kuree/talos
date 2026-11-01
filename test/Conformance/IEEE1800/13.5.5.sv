// CLAUSE: class optional method parentheses
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
class C; int n; function void set(int value=7); n=value; endfunction function int get(); return n; endfunction endclass C c;
initial begin
c=new; c.set; if(c.get!=7) $fatal;
$display("PASS"); $finish;
end

endmodule
