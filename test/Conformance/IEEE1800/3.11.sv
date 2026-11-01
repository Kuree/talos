// CLAUSE: negative genvar scopes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  for(genvar i=-2;i<1;i++) begin:g
    localparam int VALUE=i;
  end
  if(0) begin:unused
    nonexistent_module deliberately_not_elaborated();
  end
  initial begin
    if(g[-2].VALUE!=-2 || g[-1].VALUE!=-1 || g[0].VALUE!=0) $fatal(1,"generate index");
    $display("PASS"); $finish;
  end
endmodule
