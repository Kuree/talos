// CLAUSE: assoc invalid index
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{[wW][aA][rR][nN][iI][nN][gG]}}
// CHECK-DAG: {{^PASS$}}

module top;
int a[integer]; integer k; int v;
initial begin

  a='{default:7}; a[0]=3; k='x; v=a[k]; a[k]=9;
  $display("v=%0d size=%0d zero=%0d existsX=%0d",v,a.num(),a[0],a.exists(k));
  if(v!=7 || a.num()!=1 || a[0]!=3 || a.exists(k)!=0) $fatal(1,"invalid associative index v=%0d size=%0d",v,a.num());

$display("PASS");
$finish;
end
endmodule
