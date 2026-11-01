// CLAUSE: Rand join preserves each interleaved sequence relative order.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int trace[$]; automatic int ia=-1; automatic int ib=-1; automatic int ic=-1; automatic int id=-1;
randsequence(main) main:rand join left right; left:a b; right:c d; a:{trace.push_back(1);}; b:{trace.push_back(2);}; c:{trace.push_back(3);}; d:{trace.push_back(4);}; endsequence
if(trace.size()!=4) $fatal(1,"join size"); foreach(trace[i]) case(trace[i]) 1:ia=i;2:ib=i;3:ic=i;4:id=i;default:$fatal(1,"join payload");endcase if(ia<0 || ic<0 || ib<=ia || id<=ic) $fatal(1,"join order");
$display("PASS");
end
endmodule
