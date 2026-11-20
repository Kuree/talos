module other;
  import "DPI-C" ranged = function void first(input int values[1:2]);
  import "DPI" versioned = function void second(input bit [3:0] values);
  import "DPI-C" shaped = function void third(input bit [] values);
  typedef logic [7:4] hi_t;
  import "DPI-C" packed_bounds = function void p(input logic [3:0] values);
  import "DPI-C" nested_bounds = function void n(input hi_t values[2]);
  typedef struct packed { hi_t field; } record_t;
  import "DPI-C" field_bounds = function void field(input record_t values[2]);
  import "DPI-C" scalar_abi = function void s(input byte unsigned value);
  import "DPI-C" single_bit = function void bit_arg(input logic value);
  function int legacy(); return 1; endfunction
  export "DPI" export_mode = function legacy;
endmodule

module top;
  other instance_a();
  import "DPI-C" ranged = function void a(input int values[2:1]);
  import "DPI-C" versioned = function void b(input bit [3:0] values);
  import "DPI-C" shaped = function void c(input bit values[]);
  typedef logic [3:0] lo_t;
  import "DPI-C" packed_bounds = function void p(input logic [0:3] values);
  import "DPI-C" nested_bounds = function void n(input lo_t values[2]);
  typedef struct packed { lo_t field; } record_t;
  import "DPI-C" field_bounds = function void field(input record_t values[2]);
  import "DPI-C" scalar_abi = function void s(input bit [7:0] value);
  import "DPI-C" single_bit = function void bit_arg(input logic [0:0] value);
  function int modern(); return 2; endfunction
  export "DPI-C" export_mode = function modern;
endmodule
