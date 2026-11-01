// CLAUSE: signed X and Z resizing
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  logic signed[1:0] s;logic signed[4:0] w;
  typedef logic[4:0]U;
  initial begin
    s=2'bz1;w=s;if(w!==5'bzzzz1)$fatal(1,"signed Z resize");
    w=U'(s);if(w!==5'bzzzz1)$fatal(1,"signed cast resize");
    s=2'bx0;w=s;if(w!==5'bxxxx0)$fatal(1,"signed X resize");
    w=s+1;if(w!==5'bxxxxx)$fatal(1,"signed X arithmetic");
    $display("PASS");$finish;
  end
endmodule
