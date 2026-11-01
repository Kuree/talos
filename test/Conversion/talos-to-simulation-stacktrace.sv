// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 20.17.2: called as a task, $stacktrace displays the call stack
// information; called as a function, it returns that information as a string.
// The content is implementation dependent: the calling scope and source line,
// then each caller whose call site is unique, up to the top-level process.
module top;
  string s;
  task t;
    // CHECK: simulation.bytes.constant "top.t at {{.*}}talos-to-simulation-stacktrace.sv:[[# @LINE + 2]]\0Atop at {{.*}}talos-to-simulation-stacktrace.sv:[[# @LINE + 6]]"
    // CHECK: simulation.display {{.*}}newline = true
    $stacktrace;
    // CHECK: simulation.string.literal "top.t at {{.*}}talos-to-simulation-stacktrace.sv:[[# @LINE + 1]]\0Atop at {{.*}}talos-to-simulation-stacktrace.sv:[[# @LINE + 3]]"
    s = $stacktrace;
  endtask
  initial t();
endmodule
