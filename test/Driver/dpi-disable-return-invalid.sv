// RUN: %target_clang %target_pic -c \
// RUN:   %S/Inputs/dpi_disable_return_invalid_impl.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos %s %t.o -o %t.native
// RUN: not --status=19 %t.native > %t.native.out && test ! -s %t.native.out
// RUN: not --status=19 %t.native +export-after-disable
// RUN: talos --execution-tier=bytecode %s %t.o -o %t.bytecode
// RUN: not --status=19 %t.bytecode > %t.bytecode.out && test ! -s %t.bytecode.out
// RUN: not --status=19 %t.bytecode +export-after-disable

module dpi_disable_return_invalid;
  import "DPI-C" context task drive_invalid_disable(input int reenter, output int result);

  task automatic invalid_disable(output int result);
    #10 result = 42;
  endtask
  export "DPI-C" c_invalid_disable = task invalid_disable;

  initial begin : caller
    int result;
    drive_invalid_disable($test$plusargs("export-after-disable"), result);
    $display("continued %0d", result);
  end

  initial begin
    #1 disable dpi_disable_return_invalid.caller;
  end
endmodule
