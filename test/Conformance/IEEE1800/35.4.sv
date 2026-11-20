// CLAUSE: Global DPI linkage names, declaration ranges and version strings
// SINCE: 0.2.0
// RUN: %not %talos --std=1800-2023 -emit-talos --top=top %S/Inputs/35.4/conflict.sv -o %t.bad.mlir
// RUN: %clang -c -fPIC %S/Inputs/35.4/probe.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// DIAG-DAG: DPI declarations for C identifier 'ranged' must have matching
// DIAG-DAG: DPI declarations for C identifier 'versioned' must have matching
// DIAG-DAG: DPI declarations for C identifier 'shaped' must have matching
// DIAG-DAG: DPI declarations for C identifier 'packed_bounds' must have matching
// DIAG-DAG: DPI declarations for C identifier 'nested_bounds' must have matching
// DIAG-DAG: DPI declarations for C identifier 'field_bounds' must have matching
// DIAG-DAG: DPI declarations for C identifier 'scalar_abi' must have matching
// DIAG-DAG: DPI declarations for C identifier 'single_bit' must have matching
// DIAG-DAG: DPI declarations for C identifier 'export_mode' must have matching
// CHECK: {{^PASS$}}

package shared_types;
  typedef struct packed { logic [3:0] hi, lo; } packed_pair_t;
  typedef struct { int words[3:2]; } unpacked_pair_t;
endpackage

module other;
  import "DPI-C" c_named = function int a(input int other_name = 6);
  import "DPI-C" c_word = function int word_value(input integer value);
  import "DPI-C" c_time = function int time_value(input time value);
  import "DPI-C" c_signed_time = function int signed_time_value(input time signed value);
  import "DPI-C" c_packed = function int packed_value(input shared_types::packed_pair_t value);
  import "DPI-C" c_unpacked = function int unpacked_value(input shared_types::unpacked_pair_t value);
endmodule
module top;
  other instance_a();
  typedef logic signed [31:0] word_t;
  typedef shared_types::unpacked_pair_t local_pair_t;
  typedef struct packed { reg [3:0] hi, lo; } local_packed_pair_t;
  import "DPI-C" c_named = function int b(input int x = 9);
  import "DPI-C" c_word = function int word_value(input word_t value);
  import "DPI-C" c_time = function int time_value(input logic [63:0] value);
  import "DPI-C" c_signed_time = function int signed_time_value(input logic signed [63:0] value);
  import "DPI-C" c_packed = function int packed_value(input local_packed_pair_t value);
  import "DPI-C" c_unpacked = function int unpacked_value(input local_pair_t value);
  if (0) begin : unused
    import "DPI-C" c_packed = function int different_shape(input logic [1:0][3:0] value);
  end
  local_pair_t pair = '{words:'{5, 9}};
  initial begin
    if (instance_a.a() != 7 || b() != 10) $fatal(1, "shared C identifier");
    if (instance_a.word_value(32'h12345678) != 32'h12345678 ||
        word_value(32'h76543210) != 32'h76543210) $fatal(1, "integer alias");
    if (instance_a.time_value(64'h2_00000003) != 5 ||
        time_value(64'h5_00000004) != 9) $fatal(1, "time alias");
    if (instance_a.signed_time_value(64'h1_00000004) != 5 ||
        signed_time_value(64'h2_00000005) != 7) $fatal(1, "signed time alias");
    if (instance_a.packed_value(8'h45) != 'h45 || packed_value(8'hab) != 'hab)
      $fatal(1, "packed struct alias");
    if (instance_a.unpacked_value(pair) != 14 || unpacked_value(pair) != 14)
      $fatal(1, "unpacked struct typedef");
    $display("PASS");
  end
endmodule
