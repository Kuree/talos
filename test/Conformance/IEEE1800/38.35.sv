// CLAUSE: vpi_put_value_array writes contiguous elements from a start index in the declared order, with vpiOneValue and with no delay
// XFAIL: *
// The runtime has no vpi_put_value_array (undefined symbol at link).
// RUN: %clang -c -fPIC %S/Inputs/38.35/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: a=0 7 8 0 w=7
// CHECK-NEXT: b=9 9 9 0
// CHECK-NEXT: m=000 145 156 203 x04 000
// CHECK-NEXT: bad flags error=1
// CHECK-NEXT: after bad flags a[0]=0

module top;
int a[4] = '{0, 0, 0, 0};
int b[4] = '{0, 0, 0, 0};
logic [11:0] m[2:0][3:5] = '{default: '0};
wire [31:0] w = a[1];
import "DPI-C" context function void probe();
import "DPI-C" context function void bad_flags();
initial begin
  probe();
  #1;
  $display("a=%0d %0d %0d %0d w=%0d", a[0], a[1], a[2], a[3], w);
  $display("b=%0d %0d %0d %0d", b[0], b[1], b[2], b[3]);
  $display("m=%h %h %h %h %h %h", m[1][3], m[1][4], m[1][5], m[0][3], m[0][4], m[0][5]);
  bad_flags();
  $display("after bad flags a[0]=%0d", a[0]);
  $finish;
end
endmodule
