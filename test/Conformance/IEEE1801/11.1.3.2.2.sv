// CLAUSE: Tcl code using basic queries
// REQUIRES: upf
// XFAIL: *
// query_upf, upf_query_object_properties, upf_object_in_class, upf_query_object_pathname (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.3.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: basic=VDD VSS{{$}}
// CHECK: native=VDD VSS{{$}}

// 1801-2018 11.1.3.2.2: query_upf is equivalent to the clause's Tcl over the basic queries. Its helper proc
// (glob search only) and the command itself must find the same supply nets.
module show #(parameter string basic = "unset", native = "unset");
initial begin
  $display("basic=%s", basic);
  $display("native=%s", native);
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
