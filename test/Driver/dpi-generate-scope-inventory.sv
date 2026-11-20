// RUN: %split-file %s %t
// RUN: %talos -emit-sim --top=top %t/constants.sv %t/design.sv -o - | FileCheck %s \
// RUN:   --implicit-check-not='#dpi.scope<parent = {{[0-9]+}}, name = "constants"' \
// RUN:   --implicit-check-not='#dpi.scope<parent = {{[0-9]+}}, name = "top.wires['

// CHECK: name = "$unit#2"
// CHECK: name = "queries"
// CHECK: name = "top.api"

//--- constants.sv
package constants;
  localparam int Width = 8;
endpackage

//--- design.sv
package queries;
  function int width(); return constants::Width; endfunction
endpackage

module top;
  if (1) begin : api
    import "DPI-C" context function void tick();
  end
  for (genvar i = 0; i < constants::Width; i++) begin : wires
    wire value = 1'b0;
  end
  initial api.tick();
endmodule
