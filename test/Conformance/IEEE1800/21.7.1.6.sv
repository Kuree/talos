// CLAUSE: vcd flush visible
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic q=0;int fd;
initial begin
$dumpfile("probe.vcd");$dumpvars(0,q);#1;$dumpflush;fd=$fopen("probe.vcd","r");if(fd==0 || $fgetc(fd)==-1)$fatal;$fclose(fd);
$display("PASS");$finish;
end
endmodule
