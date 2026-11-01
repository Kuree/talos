// CLAUSE: assertion control disable
// XFAIL: *
// The VPI assertion-disable control call does not succeed.
// RUN: %clang -c -fPIC %S/Inputs/39.5.2/vpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0;int hits=0;check_one:assert property(@(posedge clk)1'b1)hits++;
import "DPI-C" context function int c39_disable_assertion();
initial begin
#1;clk=1;#1;if(hits!=1)$fatal(1,"control setup");if(c39_disable_assertion()!=1)$fatal(1,"disable API");clk=0;#1;clk=1;#1;if(hits!=1)$fatal(1,"disabled assertion ran");
$display("PASS"); $finish;
end
endmodule
