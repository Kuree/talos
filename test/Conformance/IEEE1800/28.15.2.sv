// CLAUSE: stored charge has the declared small strength
// XFAIL: *
// A charged trireg value is reported as HiZ strength instead of its declared small charge strength.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;logic en=1;trireg(small)n;bufif1 g(n,1'b1,en);
initial begin #1;en=0;#1;if(n!==1 || $sformatf("%v",n)!="Sm1")$fatal(1,"charge strength=%v",n);$display("PASS");$finish;end endmodule
