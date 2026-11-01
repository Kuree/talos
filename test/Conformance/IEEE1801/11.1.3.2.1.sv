// CLAUSE: query_upf overview
// REQUIRES: upf
// XFAIL: *
// query_upf (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.3.2.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: hierarchy=m1/b1 m1/b2{{$}}
// CHECK: domain=m1/b1 m1/b2{{$}}
// CHECK: domainTransitive=m1/b1 m1/b2{{$}}
// CHECK: relative=b1 b2{{$}}

// 1801-2018 11.1.3.2.1: a scope or a domain may be searched, -transitive is ignored for a domain, and every
// name is referenced to the current scope. PD's extent is m1, so it finds what a search of m1 finds.
module show #(parameter string hierarchy = "unset", domain = "unset", domainTransitive = "unset", relative = "unset");
initial begin
  $display("hierarchy=%s", hierarchy);
  $display("domain=%s", domain);
  $display("domainTransitive=%s", domainTransitive);
  $display("relative=%s", relative);
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
