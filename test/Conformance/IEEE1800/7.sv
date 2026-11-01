// CLAUSE: Arrays and aggregates
// XFAIL: *
// 7.9.8 permits a narrower assignment-compatible traversal index; the frontend requires equivalent ref types.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int]; byte idx; int status;
initial begin

  a[1000]=3; a[2000]=4; status=a.first(idx);
  $display("first status=%0d idx=%0d",status,idx);
  if(status!=-1 || idx!==8'd232) $fatal(1,"first narrow status=%0d idx=%0d",status,idx);
  status=a.last(idx);
  if(status!=-1 || idx!==8'd208) $fatal(1,"last narrow status=%0d idx=%0d",status,idx);

$display("PASS");
$finish;
end
endmodule
