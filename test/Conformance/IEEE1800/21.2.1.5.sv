// CLAUSE: hierarchical name scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string text; function automatic string path(); return $sformatf("%m"); endfunction
initial begin
begin: worker text=$sformatf("%m"); $display("BLOCK|%s",text); if(text!="top.worker") $fatal; text=path(); $display("FUNCTION|%s",text); if(text!="top.path") $fatal; end
$display("PASS"); $finish;
end
endmodule
