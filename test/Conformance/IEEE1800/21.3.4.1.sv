// CLAUSE: ungetc success
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int fd,ch,rc;
initial begin
fd=$fopen("characters.txt","w"); $fwrite(fd,"AB"); $fclose(fd); fd=$fopen("characters.txt","r"); ch=$fgetc(fd); if(ch!=65) $fatal; rc=$ungetc(90,fd); $display("UNGETC=%0d",rc); if(rc!=0) $fatal; if($fgetc(fd)!=90 || $fgetc(fd)!=66 || $fgetc(fd)!=-1) $fatal; $fclose(fd);
$display("PASS"); $finish;
end
endmodule
