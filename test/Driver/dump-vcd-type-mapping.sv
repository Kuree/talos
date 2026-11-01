// RUN: %split-file %s %t
// RUN: cd %t && talos -O1 design.sv -o %t/sim
// RUN: cd %t && %t/sim
// RUN: FileCheck %s < %t/waves.vcd

// IEEE 1800-2023 Table 21-11 maps int and a default enum to the IEEE 1364-2005
// integer type and the other integral variables to reg. integer and time keep
// their own IEEE 1364-2005 VCD types.

//--- design.sv
module top;
  typedef enum { A, B } plain_t;
  typedef enum logic [1:0] { C, D } based_t;
  bit [3:0] b;
  logic l;
  int i;
  shortint s;
  longint w;
  byte y;
  plain_t pe;
  based_t be;
  integer v;
  time t;
  wire n;
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, top);
    #1 $finish;
  end
endmodule

// CHECK-DAG: $var reg 4 {{[^ ]+}} b [3:0] $end
// CHECK-DAG: $var reg 1 {{[^ ]+}} l $end
// CHECK-DAG: $var integer 32 {{[^ ]+}} i [31:0] $end
// CHECK-DAG: $var reg 16 {{[^ ]+}} s [15:0] $end
// CHECK-DAG: $var reg 64 {{[^ ]+}} w [63:0] $end
// CHECK-DAG: $var reg 8 {{[^ ]+}} y [7:0] $end
// CHECK-DAG: $var integer 32 {{[^ ]+}} pe [31:0] $end
// CHECK-DAG: $var reg 2 {{[^ ]+}} be [1:0] $end
// CHECK-DAG: $var integer 32 {{[^ ]+}} v [31:0] $end
// CHECK-DAG: $var time 64 {{[^ ]+}} t [63:0] $end
// CHECK-DAG: $var wire 1 {{[^ ]+}} n $end
