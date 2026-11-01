// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DTWO_CALLERS -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=AMBIGUOUS

// IEEE 1800-2023 20.17.2: $stacktrace names the call stack up to the top-level
// process. Each subroutine on the chain has one call site, so the frames are
// known when compiling; with two callers of outer the chain ends there.
module top;
  task automatic inner(); $stacktrace; endtask
  task automatic outer(); inner(); endtask
  initial begin
    outer();
`ifdef TWO_CALLERS
    outer();
`endif
  end
endmodule

// CHECK: simulation.bytes.constant "top.inner at {{.*}}.sv:8\0Atop.outer at {{.*}}.sv:9\0Atop at {{.*}}.sv:11"
// AMBIGUOUS: simulation.bytes.constant "top.inner at {{.*}}.sv:8\0Atop.outer at {{.*}}.sv:9"{{$}}
