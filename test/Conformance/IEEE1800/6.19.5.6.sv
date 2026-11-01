// CLAUSE: enum unknown members
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

typedef enum logic [1:0] {UNKNOWN=2'bxx,KNOWN=1,FLOAT=2'bzz} E;
module top;
E e;
initial begin
e=UNKNOWN; if(e.name()!="UNKNOWN" || e.next()!==KNOWN) $fatal(1,"name=%s next=%b",e.name(),e.next()); e=FLOAT; if(e.name()!="FLOAT" || e.next()!==UNKNOWN) $fatal;
$display("PASS"); $finish;
end
endmodule
