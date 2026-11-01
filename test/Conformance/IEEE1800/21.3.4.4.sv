// CLAUSE: fread integral control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin : test
int fd,n; byte value;
fd=$fopen("one.dat","wb"); if(fd==0)$fatal; $fwrite(fd,"%s","A"); $fclose(fd); fd=$fopen("one.dat","rb");
n=$fread(value,fd);
$fclose(fd); $display("N=%0d",n); if(n!=1 || value!=65)$fatal(1,"FREAD_RESULT");
$display("PASS"); $finish;
end endmodule
