// CLAUSE: Complex UPF query command
// REQUIRES: upf
// XFAIL: *
// query_upf (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: glob=m1/b1 m1/b2{{$}}
// CHECK: regexp=m1/b2{{$}}
// CHECK: exact=m1/b1{{$}}
// CHECK: exactStar={{$}}
// CHECK: ignoreCase=m1/b1{{$}}

// 1801-2018 11.1.3.1: the complex query searches names by pattern. Glob by default, -regexp, -exact, which
// disallows wildcards, and -ignore_case must each select different results.
module show #(parameter string glob = "unset", regexp = "unset", exact = "unset", exactStar = "unset", ignoreCase = "unset");
initial begin
  $display("glob=%s", glob);
  $display("regexp=%s", regexp);
  $display("exact=%s", exact);
  $display("exactStar=%s", exactStar);
  $display("ignoreCase=%s", ignoreCase);
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
