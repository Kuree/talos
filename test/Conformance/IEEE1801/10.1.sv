// CLAUSE: Completed information-model queries
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.1/illegal.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.1/illegal-model.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: create_supply_net
// DIAG: upf_query_object_type
// CHECK: functions=/top/CORE.ground /top/CORE.power{{$}}

// 1801-2018 10.1: the model is built after phase 4, so the query sees the set as -update completed it,
// not the first call. Its result reaches the simulator by bind_checker, which phase 5 allows (11.1.1).
// A query followed by a command that changes the intent, or inside a power model, is an error.
module show #(parameter string functions = "unset");
initial begin
  $display("functions=%s", functions);
end
endmodule
module leaf;
endmodule
module top;
leaf dut();
endmodule
