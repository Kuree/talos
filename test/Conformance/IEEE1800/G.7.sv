// CLAUSE: weak reference
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class Obj; int value=7; endclass
module top;
  Obj a,b;
  std::weak_reference#(Obj) w;
  initial begin
    a=new; w=new(a); b=w.get();
    if(b!=a || b.value!=7) $fatal(1,"weak get");
    w.clear(); if(w.get()!=null || a.value!=7) $fatal(1,"weak clear");
    $display("PASS"); $finish;
  end
endmodule
