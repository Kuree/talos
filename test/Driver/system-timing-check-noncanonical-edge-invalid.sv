// RUN: not talos -O0 %s -o %t 2>&1 | FileCheck %s

module system_timing_check_noncanonical_edge_invalid(input wire clock);
  specify
    // IEEE 1800-2023 31.4.4 derives the data event from the opposite edge. This
    // Clause 31.5 set holds both a transition and its opposite, so it has none.
    $width(edge [01, 10] clock, 1);
  endspecify
endmodule

// CHECK: error: IEEE 1800-2017 Clause 31 system timing checks are retained in semantic IR but are not executable yet
