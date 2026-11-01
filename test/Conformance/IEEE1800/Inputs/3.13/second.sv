module top;

initial begin
if(`VALUE!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
