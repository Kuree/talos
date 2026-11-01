// CLAUSE: case fourstate
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [3:0] v; int result;
initial begin

  v=4'b1x0z; result=0;
  case(v) 4'b1x0z:result=1; default:result=2; endcase
  if(result!=1) $fatal(1,"case X/Z");
  result=0; casez(v) 4'b1x00:result=3; default:result=4; endcase
  if(result!=3) $fatal(1,"casez");

$display("PASS");
$finish;
end
endmodule
