// CLAUSE: fgets line
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int fd,n; string line;
initial begin
fd=$fopen("lines.txt","w"); if(fd==0) $fatal; $fwrite(fd,"first\nsecond\n"); $fflush(fd); $fclose(fd); fd=$fopen("lines.txt","r"); n=$fgets(line,fd); if(n!=6 || line!="first\n") $fatal; n=$fgets(line,fd); if(n!=7 || line!="second\n") $fatal; $fclose(fd);
$display("PASS"); $finish;
end
endmodule
