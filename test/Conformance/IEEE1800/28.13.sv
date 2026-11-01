// CLAUSE: A strong buffer regenerates a weak0 input and defeats pull1; a tran preserves weak0 so the
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wire source_buffer,source_tran,buffered,passed; assign(weak1,weak0) source_buffer=0; assign(weak1,weak0) source_tran=0;
buf(strong1,strong0) g(buffered,source_buffer); tran t(source_tran,passed); pullup(buffered); pullup(passed);
initial begin
#1; if(buffered!==0 || passed!==1) $fatal(1,"buffered=%b passed=%b",buffered,passed);
$display("PASS"); $finish;
end
endmodule
