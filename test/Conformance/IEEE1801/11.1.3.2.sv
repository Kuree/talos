// CLAUSE: query_upf
// REQUIRES: upf
// XFAIL: *
// query_upf (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: outputs=m1/out1{{$}}
// CHECK: plain={{$}}
// CHECK: transitive=m1/b1/in1 m1/b2/in1 m1/in1{{$}}
// CHECK: sets=CORE{{$}}
// CHECK: nets=VDD VSS{{$}}

// 1801-2018 11.1.3.2: -object_type, -direction and -transitive restrict the search, and UPF-created objects
// are found along with HDL ones. Names are relative to the current scope, /top here.
module show #(parameter string outputs = "unset", plain = "unset", transitive = "unset", sets = "unset", nets = "unset");
initial begin
  $display("outputs=%s", outputs);
  $display("plain=%s", plain);
  $display("transitive=%s", transitive);
  $display("sets=%s", sets);
  $display("nets=%s", nets);
end
endmodule
module bot(input wire in1, output wire out1);
  assign out1 = in1;
endmodule
module mid(input wire in1, output wire out1);
  wire link1;
  bot b1(in1, link1);
  bot b2(link1, out1);
endmodule
module top;
logic drive = 0;
wire seen;
mid m1(drive, seen);
endmodule
