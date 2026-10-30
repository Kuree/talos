// RUN: talos-opt %s --split-input-file --verify-diagnostics -o /dev/null
// expected-error@+1 {{atomic members must be unique dataflow fusion fragments}}
module attributes {test = #schedule.fusion<id = 0, fragments = [0, 1], interleaved = true, dataflow = true, atomic = [2]>} {}
// -----
// expected-error@+1 {{atomic members must be unique dataflow fusion fragments}}
module attributes {test = #schedule.fusion<id = 0, fragments = [0, 1], interleaved = true, dataflow = true, atomic = [1, 1]>} {}
// -----
// expected-error@+1 {{atomic members must be unique dataflow fusion fragments}}
module attributes {test = #schedule.fusion<id = 0, fragments = [0, 1], interleaved = true, atomic = [1]>} {}
