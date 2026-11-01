// CLAUSE: Query-phase command restrictions
// REQUIRES: upf
// XFAIL: *
// upf_query_object_type, upf_query_object_pathname (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.1/illegal.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.1.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: create_supply_net
// CHECK: top.dut.show{{$}}
// CHECK: kind=upfSupplyNetT{{$}}
// CHECK: here=/top/dut{{$}}
// CHECK: nets=n1 n2{{$}}

// 1801-2018 11.1.1: the first query starts phase 5, where set_scope, bind_checker, find_objects and load_upf
// stay available with immediate effect: the checker binds in the scope set after the query, through a load.
// Any other UPF command in this phase is an error.
module show #(parameter string kind = "unset", here = "unset", nets = "unset");
initial begin
  $display("%m");
  $display("kind=%s", kind);
  $display("here=%s", here);
  $display("nets=%s", nets);
end
endmodule
module leaf;
wire n1, n2;
endmodule
module top;
leaf dut();
endmodule
