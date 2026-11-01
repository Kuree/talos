// CLAUSE: ferror clears string
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int fd,error,ch; string message;
initial begin
fd=$fopen("good.txt","w"); $fwrite(fd,"A"); $fclose(fd); fd=$fopen("good.txt","r"); if(fd==0 || $feof(fd)!=0) $fatal; ch=$fgetc(fd); if(ch!=65) $fatal; message="stale"; error=$ferror(fd,message); if(error!=0 || message!="") $fatal(1,"error=%0d message=%s",error,message); ch=$fgetc(fd); if(ch!=-1 || !$feof(fd)) $fatal; $fclose(fd);
$display("PASS"); $finish;
end
endmodule
