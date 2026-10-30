// A design database fixture; no simulation is required by the frontend tests.
module upf_leaf(input logic d, output logic q);
  assign q = d;
endmodule
module upf_cluster(input logic d, output logic q);
  upf_leaf child(d, q);
endmodule
module upf_test;
  logic d, power_en, iso;
  logic [1:0] wide;
  wire q, q2, q3;
  upf_leaf dut(d, q), dut2(d, q2);
  upf_cluster cluster(d, q3);
endmodule
