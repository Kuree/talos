// CLAUSE: live bits nested dynamic
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  typedef struct {int a[]; logic [3:0] tag;} T;
  T value;

initial begin

  value.a=new[3]; if($bits(value)!=100) $fatal(1,"live bits=%0d",$bits(value));
  value.a=new[1]; if($bits(value)!=36) $fatal(1,"resized live bits=%0d",$bits(value));

$display("PASS");
$finish;
end
endmodule
