// CLAUSE: evcd flush visible
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(output wire q);assign q=1;endmodule
module top;
wire q;cell_t dut(q);int fd;
initial begin
$dumpports(dut,"probe.evcd");#1;$dumpportsflush("probe.evcd");fd=$fopen("probe.evcd","r");if(fd==0 || $fgetc(fd)==-1)$fatal;$fclose(fd);
$display("PASS");$finish;
end
endmodule
