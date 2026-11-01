// CLAUSE: string atoi does not consume a sign
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  string text = "-123";
  initial begin
    if(text.atoi()!=0)$fatal(1,"atoi consumed a sign");
    $display("PASS");$finish;
  end
endmodule
