// RUN: %split-file %s %t
// RUN: %talos -emit-sim --top=top %t/constants.sv %t/design.sv -o - | FileCheck %s \
// RUN:   --implicit-check-not='#dpi.scope<parent = {{[0-9]+}}, name = "constants"' \
// RUN:   --implicit-check-not='#dpi.scope<parent = {{[0-9]+}}, name = "$unit"' \
// RUN:   --implicit-check-not='#dpi.scope<parent = {{[0-9]+}}, name = "top.wires[{{[0-9]+}}]"'
// RUN: %target_clang %target_pic -I%resource_dir/include -c %t/check.c -o %t/check.o
// RUN: %talos --top=top --execution-tier=native %t/constants.sv %t/design.sv %t/check.o -o %t/native
// RUN: %t/native | FileCheck %s --check-prefix=RUNNING
// RUN: %talos --top=top --execution-tier=bytecode %t/constants.sv %t/design.sv %t/check.o -o %t/bytecode
// RUN: %t/bytecode | FileCheck %s --check-prefix=RUNNING

// CHECK: #dpi.scope<parent = {{[0-9]+}}, name = "$unit#2"
// CHECK: #dpi.scope<parent = {{[0-9]+}}, name = "queries"
// CHECK: #dpi.scope<parent = {{[0-9]+}}, name = "top.api"
// CHECK: #dpi.scope<parent = {{[0-9]+}}, name = "top.wires[0].observer.nested"
// RUNNING: PASS

//--- constants.sv
package constants;
  localparam int Width = 8;
  class Config;
    extern static function int get_width();
  endclass
  function int Config::get_width(); return Width; endfunction
endpackage

//--- design.sv
package queries;
  program;
    function int width(); return constants::Width; endfunction
  endprogram
endpackage

checker monitor(input bit value);
  function int checker_method(); return 1; endfunction
  if (1) begin : nested
    function int local_function(); return 2; endfunction
  end
endchecker

module top;
  if (1) begin : api
    import "DPI-C" context function int check_scopes();
  end
  for (genvar i = 0; i < constants::Width; i++) begin : wires
    wire value = 1'b0;
    class Marker;
      function int id(); return i; endfunction
    endclass
    monitor observer(value);
  end
  initial begin
    if (!api.check_scopes()) $fatal(1, "DPI declaration scope lookup");
    $display("PASS");
  end
endmodule

//--- check.c
#include "svdpi.h"
#include <string.h>

int check_scopes(void) {
  const char *nested = "top.wires[0].observer.nested";
  svScope checker_scope = svGetScopeFromName(nested);
  svScope pkg = svGetScopeFromName("queries");
  return checker_scope && !strcmp(svGetNameFromScope(checker_scope), nested) &&
         pkg && !strcmp(svGetNameFromScope(pkg), "queries");
}
