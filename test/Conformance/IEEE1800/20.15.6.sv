// CLAUSE: stochastic error status
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int status,job,info;
initial begin
$q_initialize(81,1,0,status); if(status!=5) $fatal; $q_initialize(81,1,1,status); if(status!=0) $fatal; $q_initialize(81,1,1,status); if(status!=6) $fatal; $q_remove(81,job,info,status); if(status!=3) $fatal; $q_remove(9999,job,info,status); if(status!=2) $fatal; $q_add(81,1,2,status); if(status!=0) $fatal; $q_add(81,3,4,status); if(status!=1) $fatal;
$display("PASS"); $finish;
end
endmodule
