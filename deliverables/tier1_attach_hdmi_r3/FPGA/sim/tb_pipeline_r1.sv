`timescale 1ns/1ps
module tb_pipeline_r1;
  tb_md_pipeline #(.MODE_BG(1),.THRESH(100),.DUMP_N(0)) check_pipeline();
  integer good=0;
  always @(posedge check_pipeline.clk) if(check_pipeline.mk_poke) begin
    if(check_pipeline.b_valid) begin
      good=good+1;
      if(check_pipeline.dut.b_obj_count==0 ||
         check_pipeline.b_x2<check_pipeline.b_x1 ||
         check_pipeline.b_y2<check_pipeline.b_y1)
        $fatal(1,"PIPELINE_R1 metadata invalid");
    end
    if(check_pipeline.poke_idx==11) begin
      if(good<8)$fatal(1,"PIPELINE_R1 insufficient valid frames %0d",good);
      $display("PIPELINE_R1_PASS valid_frames=%0d",good);
    end
  end
endmodule
