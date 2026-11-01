// CLAUSE: read twostate memory
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit[7:0]mem[1];int fd;
initial begin
fd=$fopen("in.hex","w");$fwrite(fd,"xz\n");$fclose(fd);$readmemh("in.hex",mem);if(mem[0]!=0)$fatal;
$display("PASS");$finish;
end
endmodule
