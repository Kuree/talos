// CLAUSE: UPF ports and nets with same name
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: port=700000{{$}}
// CHECK: net=900000{{$}}

// 1801-2018 10.3.2.2.3: a same-name port and net have one path ID, so a search finds the port and the
// net needs the @upfSupplyNetT suffix. They are not connected here, so each keeps the voltage written
// through its own ID; ignoring the suffix would leave both at the same value.
module top;
import UPF::*;
upfSupplyTypeT port, net, explicit;
initial begin
  void'(supply_on("/top/VDD", 0.7));
  void'(supply_on("/top/VDD@upfSupplyNetT", 0.9));
  port = get_supply_value("/top/VDD");
  net = get_supply_value("/top/VDD@upfSupplyNetT");
  $display("port=%0d", port.voltage);
  $display("net=%0d", net.voltage);
  $finish;
end
endmodule
