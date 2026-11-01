// CLAUSE: upf_get_value_real
// REQUIRES: upf
// XFAIL: *
// set_level_shifter is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.2.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: threshold=0.250000{{$}}

// 1801-2018 11.2.3.2.4: the real value of a property, using its example's level-shifter threshold.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire q;
leaf dut(q);
initial begin
  h = upf_get_handle_by_name("/top/PD.LS");
  $display("threshold=%f", upf_get_value_real(upf_query_object_properties(h, UPF_THRESHOLD_VALUE)));
  $finish;
end
endmodule
