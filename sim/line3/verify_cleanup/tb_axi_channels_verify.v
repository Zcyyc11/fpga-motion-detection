`timescale 1ns/1ps
module tb_axi_channels_verify;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[31:0]aw=0,wd=0,ar=0;reg awv=0,wv=0,br=0,arv=0,rr=0;
 wire awr,wr,bv,arr,rv;wire[1:0]bp,rp;wire[31:0]rd,pswd;
 wire pe,pw;wire[5:0]pa;reg[31:0]mem=0,psrd=0;
 axi_lite_slave dut(.S_AXI_ACLK(clk),.S_AXI_ARESETN(rst),.S_AXI_AWADDR(aw),.S_AXI_AWVALID(awv),.S_AXI_AWREADY(awr),
 .S_AXI_WDATA(wd),.S_AXI_WSTRB(4'hF),.S_AXI_WVALID(wv),.S_AXI_WREADY(wr),.S_AXI_BRESP(bp),.S_AXI_BVALID(bv),.S_AXI_BREADY(br),
 .S_AXI_ARADDR(ar),.S_AXI_ARVALID(arv),.S_AXI_ARREADY(arr),.S_AXI_RDATA(rd),.S_AXI_RRESP(rp),.S_AXI_RVALID(rv),.S_AXI_RREADY(rr),
 .ps_en(pe),.ps_we(pw),.ps_addr(pa),.ps_wdata(pswd),.ps_rdata(psrd));
 always @(posedge clk)begin
 if(!rst)begin mem<=0;psrd<=0;end
 else begin if(pe&&pw)mem<=pswd;psrd<=(pe&&!pw)?mem:0;end
 end
 integer errors=0,k;reg done;reg[31:0]saved;
 task check(input bit ok,input string msg);begin
 if(!ok)begin errors=errors+1;$display("FAIL %s",msg);end else $display("PASS %s",msg);
 end endtask
 task reset_dut;begin
 @(negedge clk);rst=0;awv=0;wv=0;br=0;arv=0;rr=0;
 repeat(3)@(negedge clk);rst=1;
 end endtask
 task address;begin
 @(negedge clk);awv=1;aw=0;done=0;
 for(k=0;k<20&&!done;k=k+1)begin @(posedge clk);if(awr===1)done=1;end
 check(done,"write address accepted");@(negedge clk);awv=0;
 end endtask
 task payload;begin
 @(negedge clk);wv=1;wd=32'h1234;done=0;
 for(k=0;k<20&&!done;k=k+1)begin @(posedge clk);if(wr===1)done=1;end
 check(done,"write data accepted");@(negedge clk);wv=0;
 end endtask
 task response;begin
 done=0;for(k=0;k<20&&!done;k=k+1)begin @(negedge clk);if(bv===1)done=1;end
 check(done,"split channels produce BVALID");check(mem===32'h1234,"split channels write once");
 end endtask
 initial begin
 reset_dut;address;repeat(3)@(negedge clk);payload;response;
 reset_dut;payload;repeat(3)@(negedge clk);address;response;
 reset_dut;
 @(negedge clk);awv=1;wv=1;wd=32'h5678;
 @(posedge clk);check(awr&&wr,"simultaneous write handshake");
 @(negedge clk);awv=0;wv=0;
 repeat(3)@(negedge clk);check(bv&&mem==32'h5678,"write response held");
 br=1;@(negedge clk);br=0;
 ar=0;arv=1;
 @(posedge clk);check(arr,"read accepted");
 @(negedge clk);arv=0;done=0;
 for(k=0;k<20&&!done;k=k+1)begin @(negedge clk);if(rv===1)done=1;end
 check(done && rd===32'h5678,"registered slave read");saved=rd;
 repeat(5)begin @(negedge clk);check(rv && rd===saved,"read held under backpressure");end
 rr=1;@(negedge clk);rr=0;
 $display("VERIFY_DONE axi errors=%0d",errors);$finish;
 end
 initial begin #200000;$fatal(1,"FAIL timeout axi");end
endmodule
