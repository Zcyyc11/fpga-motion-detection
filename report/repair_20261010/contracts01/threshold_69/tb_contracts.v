`timescale 1ns/1ps
// Independent directed stimuli: no pattern/model-generated expected arrays.
module tb_contracts;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg tv=0;
    reg [10:0] td=0;
    wire tov, tm;
    threshold th(.clk(clk),.rst_n(rst_n),.in_valid(tv),.absdiff(td),.out_valid(tov),.mask(tm));
    reg mv=0, mb=0;
    reg [15:0] mx=0,my=0;
    wire mov,mom;
    wire [15:0] mox,moy;
    morph_open #(.W(10)) morph(.clk(clk),.rst_n(rst_n),.in_valid(mv),
        .in_x(mx),.in_y(my),.in_mask(mb),.o_valid(mov),.o_x(mox),.o_y(moy),.o_mask(mom));
    reg sof=0,pde=0;
    reg [15:0] px=0,py=1;
    wire pv;
    wire [15:0] pox,poy,pframe;
    wire [7:0] pixel;
    pattern_gen #(.H_ACTIVE(64),.V_ACTIVE(8),.OBJ_W(16),.OBJ_H(4),.X0(0),.Y0(1),.DX(16))
        pat(.clk(clk),.rst_n(rst_n),.sof(sof),.de(pde),.x(px),.y(py),
        .vde(pv),.x_o(pox),.y_o(poy),.pixel(pixel),.frame_idx(pframe));
    integer f,x,y,fd,threshold_checks=0,pattern_checks=0;
    integer lefts[0:5];
    reg expected;
    task threshold_check(input integer value,input bit valid,input bit want);
        begin
            @(negedge clk); td=value; tv=valid;
            @(posedge clk); #1;
            if(tov !== valid || tm !== want)
                $fatal(1,"THRESHOLD value=%0d expected=%0d actual=%0d",value,want,tm);
            threshold_checks=threshold_checks+1;
        end
    endtask
    always @(negedge clk) if(mov) begin
        if ((^mox === 1'bx) || (^moy === 1'bx) || (mom === 1'bx))
            $fatal(1,"MORPH unknown output");
        $fwrite(fd,"%0d,%0d,%0d,%0d\n",f,mox,moy,mom);
    end
    initial begin
        fd=$fopen("morph.csv","w");
        if(!fd) $fatal(1,"Cannot open morph.csv");
        $fwrite(fd,"frame,x,y,mask\n");
        repeat(3) @(negedge clk); rst_n=1;
        threshold_check(0,1,0);
        threshold_check(69,1,0);
        threshold_check(70,1,0);
        threshold_check(71,1,1);
        threshold_check(1020,1,1);
        threshold_check(70,0,0);
        @(negedge clk); tv=0;
        // Cold-start all-foreground, blank, all-foreground. Every edge is touched.
        for(f=0;f<3;f=f+1) begin
            for(y=0;y<10;y=y+1) begin
                for(x=0;x<10;x=x+1) begin
                    @(negedge clk); mv=1; mx=x; my=y; mb=(f!=1);
                    @(negedge clk); mv=0; // exercise bubbles between samples
                end
            end
            repeat(5) @(negedge clk);
        end
        // Explicit positions include exactly touching the right edge and a real wrap.
        lefts[0]=0; lefts[1]=16; lefts[2]=32; lefts[3]=48; lefts[4]=0; lefts[5]=16;
        for(f=0;f<6;f=f+1) begin
            @(negedge clk); sof=1;
            @(negedge clk); sof=0;
            for(x=0;x<64;x=x+1) begin
                @(negedge clk); pde=1;px=x;
                @(posedge clk); #1;
                expected=(x>=lefts[f] && x<lefts[f]+16);
                if(pv !== 1'b1 || pixel !== (expected ? 8'd255 : 8'd0) || pox !== x)
                    $fatal(1,"PATTERN frame=%0d x=%0d expected_left=%0d actual_pixel=%0d",f,x,lefts[f],pixel);
                pattern_checks=pattern_checks+1;
            end
            @(negedge clk); pde=0;
        end
        $fclose(fd);
        $display("CONTRACTS_DONE threshold=%0d pattern=%0d",threshold_checks,pattern_checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"TIMEOUT contracts"); end
endmodule
