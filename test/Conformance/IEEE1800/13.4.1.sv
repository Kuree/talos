// CLAUSE: return queue typedef
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef int Q[$]; Q a,b; function automatic Q make(); Q localq='{7}; return localq; endfunction
initial begin
a=make(); a[0]=9; b=make(); if(a[0]!=9 || b[0]!=7) $fatal;
$display("PASS"); $finish;
end

endmodule
