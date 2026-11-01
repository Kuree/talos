// CLAUSE: Hierarchy paths relative to the design root
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK: below=1{{$}}
// CHECK: above=0{{$}}
// CHECK: value=700000{{$}}

// 1801-2018 10.5: path IDs start below the root instance and exclude its name. Talos defines that root (the
// clause's NOTE) as the elaboration root above --top, so /top/dut/VDD resolves and /dut/VDD is no ID:
// the failed call returns 0, leaves the supply alone and is a simulation error (11.2.3.3.4).
module leaf;
endmodule
module top;
import UPF::*;
leaf dut();
upfSupplyTypeT s;
initial begin
  $display("below=%0d", supply_on("/top/dut/VDD", 0.7));
  $display("above=%0d", supply_on("/dut/VDD", 0.5));
  s = get_supply_value("/top/dut/VDD");
  $display("value=%0d", s.voltage);
  $finish;
end
endmodule
