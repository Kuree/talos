// CLAUSE: Built-in classes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int value=0;
initial begin

  fork begin #1; value=1; end begin #5; value=5; end join_any
  disable fork;
  #6; if(value!=1) $fatal(1,"disabled child still ran=%0d",value);

$display("PASS");
$finish;
end
endmodule
