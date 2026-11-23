// RUN: mkdir -p %t.dir
// RUN: talos -O3 --vpi=off %s -o %t.dir/native && cd %t.dir && ./native && FileCheck %s --check-prefix=DUMP < wave.vcd
// RUN: talos -O3 --execution-tier=bytecode --vpi=off %s -o %t.dir/vm && cd %t.dir && ./vm && FileCheck %s --check-prefix=DUMP < wave.vcd
// RUN: talos -O3 --vpi=off +define+FINISH_WITHOUT_DUMPALL %s -o %t.dir/finish && cd %t.dir && ./finish && FileCheck %s --check-prefix=FINISH < wave.vcd
//
// A Reactive writer can inspect the waveform or finish before the Active
// continuous assignments run (4.5, 4.9.1, 21.7.1.4). The two halves may
// share a VCD identifier with the source only if all samples agree.
// DUMP: $var reg 8 [[DATA:[^ ]+]] data
// DUMP: $var wire 8 [[COPY:[^ ]+]] mirror
// DUMP: #1
// DUMP-NEXT: $dumpall
// DUMP-DAG: b11100001 [[DATA]]
// DUMP-DAG: b0 [[COPY]]
// DUMP-NEXT: $end
// DUMP-NEXT: b11100001 [[COPY]]
// FINISH: $var reg 8 [[DATA:[^ ]+]] data
// FINISH: $var wire 8 [[COPY:[^ ]+]] mirror
// FINISH: #0
// FINISH: b0 [[COPY]]
// FINISH: #1
// FINISH-NEXT: b11100001 [[DATA]]
// FINISH-NOT: b11100001 [[COPY]]
module top;
  timeunit 1ns; timeprecision 1ns;
  logic [7:0] data = 0;
  wire [7:0] mirror;
  assign mirror[7:4] = data[7:4];
  assign mirror[3:0] = data[3:0];
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, top);
  end
  stimulus p();
endmodule

program automatic stimulus;
  timeunit 1ns; timeprecision 1ns;
  initial begin
    #1 top.data = 8'he1;
`ifndef FINISH_WITHOUT_DUMPALL
    $dumpall;
    #1;
`endif
    $finish;
  end
endprogram
