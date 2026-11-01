// CLAUSE: string integer toa
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s;
initial begin
s.itoa(-123); if(s!="-123") $fatal; s.hextoa(255); if(s!="ff") $fatal(1,"hex=%s",s); s.octtoa(8); if(s!="10") $fatal; s.bintoa(5); if(s!="101") $fatal;
$display("PASS"); $finish;
end
endmodule
