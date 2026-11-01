// CLAUSE: upf_iter_get_next
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.1.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: function=power{{$}}
// CHECK-DAG: function=ground{{$}}
// CHECK: count=2{{$}}
// CHECK: end=0{{$}}

// 1801-2018 11.2.3.1.3: each call returns the next element and 0 once none is left, as in its example.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT list, f;
int count = 0;
wire q;
leaf dut(q);
initial begin
  list = upf_query_object_properties(upf_get_handle_by_name("/top/PD.primary"), UPF_FUNCTIONS);
  f = upf_iter_get_next(list);
  while (f != 0) begin
    $display("function=%s", upf_get_value_str(upf_query_object_properties(f, UPF_NAME)));
    count++;
    f = upf_iter_get_next(list);
  end
  $display("count=%0d", count);
  $display("end=%0d", upf_iter_get_next(list));
  $finish;
end
endmodule
