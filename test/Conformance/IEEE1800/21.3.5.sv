// CLAUSE: seek rewind pushback
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int fd,rc,ch;
initial begin
fd=$fopen("seek.txt","w"); $fwrite(fd,"ABCD"); $fclose(fd); fd=$fopen("seek.txt","r"); rc=$fseek(fd,2,0); if(rc!=0 || $ftell(fd)!=2 || $fgetc(fd)!=67) $fatal; rc=$ungetc(90,fd); rc=$rewind(fd); if(rc!=0 || $ftell(fd)!=0 || $fgetc(fd)!=65) $fatal; rc=$fseek(fd,-1,2); if(rc!=0 || $fgetc(fd)!=68) $fatal; $fclose(fd);
$display("PASS"); $finish;
end
endmodule
