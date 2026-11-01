// CLAUSE: Program runs after module NBA updates
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

program P;
  initial begin
    if(top.value!==1)$fatal(1,"program value=%b before NBA",top.value);
    $display("PASS");
  end
endprogram
module top;
  bit value=0;
  P p();
  initial value<=1;
endmodule
