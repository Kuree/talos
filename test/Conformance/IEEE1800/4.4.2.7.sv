// CLAUSE: Program zero delay waits for reactive work
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

program P;
  bit trigger=0,ready=0;
  initial begin
    #1; trigger=1; #0;
    if(!ready || top.value!==1)$fatal(1,"resume ready=%b value=%b",ready,top.value);
    $display("PASS");
  end
  initial begin @(posedge trigger); ready=1; end
endprogram
module top;
  bit value=0;
  P p();
  initial #1 value<=1;
endmodule
