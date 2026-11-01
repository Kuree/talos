// CLAUSE: plusargs prefix first
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe +packet_id=17 +packet_id=22 +tag=abc +flag
// CHECK-DAG: {{^PASS$}}

module top;
int id,missing; string tag;
initial begin
id=0; missing=99; if(!$test$plusargs("flag") || !$test$plusargs("packet") || $test$plusargs("absent")) $fatal; if(!$value$plusargs("packet_id=%d",id) || id!=17) $fatal; if(!$value$plusargs("tag=%s",tag) || tag!="abc") $fatal; if($value$plusargs("absent=%d",missing)!=0 || missing!=99) $fatal;
$display("PASS"); $finish;
end
endmodule
