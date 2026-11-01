module leaf;
endmodule
module top;
  leaf a();
endmodule
config selected_config;
  design work.top;
  default liblist work;
  cell work.leaf liblist work;
endconfig
