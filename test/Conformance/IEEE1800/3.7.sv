// CLAUSE: tristate unknown control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  logic data=1,enable=0; wire value;
  bufif1 gate_instance(value,data,enable);
  initial begin
    #1; if(value!==1'bz) $fatal(1,"disabled gate");
    enable=1; #1; if(value!==1) $fatal(1,"enabled gate");
    enable=1'bx; #1; if(value!==1'bx) $fatal(1,"unknown control");
    $display("PASS"); $finish;
  end
endmodule
