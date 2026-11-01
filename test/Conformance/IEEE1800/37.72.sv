// CLAUSE: Case, pattern: vpiCaseType and vpiQualifier; vpiCaseItem groups labels through vpiExpr with vpiStmt; default has no vpiExpr; patterns
// XFAIL: *
// With two or more labelled items the first has no vpiStmt and the others no vpiExpr, and a matches item has no pattern object.
// RUN: %clang -c -fPIC %S/Inputs/37.72/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Items come in no promised order, so each line names its case and they match in any order.
// CHECK-DAG: vpiCase type=exact qualifier=none condition=x=2
// CHECK-DAG: item of exact/none exprs={{1,5,|5,1,}} stmt=a=0
// CHECK-DAG: item of exact/none exprs={{2,3,|3,2,}} stmt=b=20
// CHECK-DAG: item of exact/none exprs=null stmt=c=0
// CHECK-DAG: vpiCase type=casex qualifier=none condition=z=1
// CHECK-DAG: item of casex/none exprs=0, stmt=d=40
// CHECK-DAG: item of casex/none exprs=null stmt=none
// CHECK-DAG: vpiCase type=casez qualifier=unique condition=z=1
// CHECK-DAG: item of casez/unique exprs=1, stmt=e=50
// CHECK-DAG: vpiCase type=exact qualifier=tagged condition=x=2
// CHECK-DAG: item of exact/tagged pattern=vpiAnyPattern stmt=f=60

module top;
int x = 2;
logic [1:0] z = 2'b01;
int a, b, c, d, e, f;
import "DPI-C" context function void probe();
initial begin
  case (x)
    1, 5: a = 10;
    2, 3: b = 20;
    default: c = 30;
  endcase
  casex (z)
    2'b0x: d = 40;
    default: ;
  endcase
  unique casez (z)
    2'b01: e = 50;
  endcase
  case (x) matches
    .*: f = 60;
  endcase
  probe();
  $finish;
end
endmodule
