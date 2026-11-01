// CLAUSE: read packed memory
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct packed{byte a,b;}T;T mem[1];int fd;
initial begin
fd=$fopen("in.hex","w");$fwrite(fd,"1234\n");$fclose(fd);$readmemh("in.hex",mem);if(mem[0].a!=8'h12 || mem[0].b!=8'h34)$fatal;
$display("PASS");$finish;
end
endmodule
