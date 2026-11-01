// CLAUSE: Keyword sets select reserved words per region; words reserved in the set are rejected as names
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/22.14.1/reserved.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/22.14.1/not_reserved.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/22.14.1/inside.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: expected a declaration name
// DIAG: use of undeclared identifier 'interface'
// DIAG: directive is not allowed inside a design element
// CHECK: 0123456789abcdef 0123456789abcdef 1{{$}}

// 22.14.1: the clause's m2 and if examples; logic is an ordinary variable only under the 1364-2001 keyword list.
`begin_keywords "1364-2001"
module m2(out);
  output [63:0] out;
  reg [63:0] logic;
  assign out = logic;
  initial logic = 64'h0123_4567_89ab_cdef;
endmodule
`end_keywords
`begin_keywords "1800-2005"
interface if1;
  logic v = 1;
endinterface
`end_keywords
module top;
  wire [63:0] o;
  m2 u(o);
  if1 i();
  initial begin
    #1 $display("%h %h %b", o, u.\logic , i.v);
    $finish;
  end
endmodule
