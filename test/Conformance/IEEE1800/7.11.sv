// CLAUSE: array query directions
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[7:3];
initial begin
$display("left=%0d right=%0d low=%0d high=%0d increment=%0d size=%0d dimensions=%0d unpacked=%0d packed_size=%0d",$left(a),$right(a),$low(a),$high(a),$increment(a),$size(a),$dimensions(a),$unpacked_dimensions(a),$size(a,2)); if($left(a)!=7 || $right(a)!=3 || $low(a)!=3 || $high(a)!=7 || $increment(a)!=1 || $size(a)!=5 || $dimensions(a)!=2 || $unpacked_dimensions(a)!=1 || $size(a,2)!=32) $fatal;
$display("PASS"); $finish;
end
endmodule
