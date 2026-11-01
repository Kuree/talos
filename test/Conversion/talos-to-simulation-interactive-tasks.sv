// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 Annex D: the tasks acting on the tool reach the runtime through
// the host command entry, spelled with a leading NUL no string can hold. The
// source listings exist only in the compiler, so they travel with the command.
module kid; task kt; endtask initial begin : deepblk end int v = 3; endmodule
module top;
  kid k();
  reg [3:0] n;
  initial begin
    $log("a.log");
    $nolog;
    $input("c.txt");
    $reset(1, 42);
    n = $reset_count + $reset_value;
    $scope(top.k);
    $showscopes(1);
    $showvars(n[1]);
    $list(top.k);
    $list;
  end
endmodule

// CHECK: simulation.string.literal "a.log"
// CHECK: simulation.string.literal "\00log"
// CHECK: simulation.system
// CHECK: simulation.string.literal "\00nolog"
// CHECK: simulation.system
// CHECK: simulation.string.literal "c.txt"
// CHECK: simulation.string.literal "\00input"
// The reset_value alone crosses the reset.
// CHECK: simulation.string.format_integer
// CHECK: simulation.string.literal "\00reset"
// CHECK: simulation.string.literal "\00reset_count"
// CHECK: simulation.string.literal "\00reset_value"
// $scope and $showvars read the design database that a dump operation retains.
// CHECK: simulation.dump.flush
// CHECK: simulation.string.literal "top.k"
// CHECK: simulation.string.literal "\00scope"
// $showscopes lists parent path and name, including a block with no symbol.
// CHECK: simulation.string.literal "top"
// CHECK: simulation.string.literal "k"
// CHECK: simulation.string.literal "top.k"
// CHECK: simulation.string.literal "kt"
// CHECK: simulation.string.literal "top.k"
// CHECK: simulation.string.literal "deepblk"
// CHECK: simulation.string.literal "\00showscopes"
// A select in $showvars stands for its whole vector (D.13).
// CHECK: simulation.dump.flush
// CHECK: simulation.string.literal "top.n"
// CHECK: simulation.string.literal "\00showvars"
// CHECK: simulation.string.literal "{{.*}}module kid;
// CHECK: simulation.string.literal "\00list"
