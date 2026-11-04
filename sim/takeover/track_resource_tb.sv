`timescale 1ns/1ps
module track_resource_tb;
 reg clk=0,rst_n=0,v=0,tick=0,last=0;
 reg [15:0] x=0,y=0;
 always #5 clk=~clk;
 wire ov,ol; wire[7:0] id; wire[15:0] ox,oy,xx,yy,dw;
 track #(.MISSED_MAX(2)) dut(.clk(clk),.rst_n(rst_n),.t_valid(v),.t_id(8'd0),
 .t_x1(x),.t_x2(x),.t_y1(y),.t_y2(y),.t_last(last),.frame_tick(tick),
 .o_valid(ov),.o_last(ol),.o_id(id),.o_x1(ox),.o_y1(oy),.o_x2(xx),.o_y2(yy),.o_dwell(dw));
 reg avin=0; reg[7:0] ai=0; reg[15:0] ax=0,ad=0,threshold=0;
 wire av;wire[7:0] aid;wire[1:0] at;wire[15:0] ac;
 alarm a(.clk(clk),.rst_n(rst_n),.LINE_X(16'd50),.DWELL(threshold),.t_valid(avin),.t_id(ai),
 .t_x1(ax),.t_x2(ax),.t_y1(16'd0),.t_y2(16'd0),.t_dwell(ad),.a_valid(av),.a_id(aid),.a_type(at),.a_cx(ac));
 integer errors=0,n=0,events=0,crosses=0,dwells=0,cycle=0,start_cycle=0,max_latency=0;
 integer ids[0:63],dws[0:63],xs[0:63],ys[0:63],lasts[0:63];
 integer px[0:15],py[0:15];integer i,j,oldid,persistent;
 always @(posedge clk) begin #1;
 cycle=cycle+1;
 if(ov)begin
 if(n>=64)$fatal(1,"output overflow");
 ids[n]=id;dws[n]=dw;xs[n]=ox;ys[n]=oy;lasts[n]=ol;n=n+1;
 if(ol && cycle-start_cycle>max_latency)max_latency=cycle-start_cycle;
 end
 if(av)begin events=events+1;if(at==1)crosses=crosses+1;if(at==2)dwells=dwells+1;end
 end
 task check(input bit ok,input string msg);begin
 if(!ok)begin errors=errors+1;$display("FAIL %s",msg);end
 end endtask
 task reset;begin @(negedge clk);rst_n=0;v=0;tick=0;avin=0;
 repeat(3)@(negedge clk);rst_n=1;n=0;events=0;crosses=0;dwells=0;end endtask
 task send(input integer count);begin
 for(integer k=0;k<count;k=k+1)begin @(negedge clk);v=1;x=px[k];y=py[k];last=(k==count-1);end
 @(negedge clk);v=0;last=0;tick=1;start_cycle=cycle;
 @(negedge clk);tick=0;
 end endtask
 task settle;begin repeat(6000)@(negedge clk);end endtask
 task frame(input integer count);begin n=0;send(count);settle;
 check(n==count,"frame output count");
 for(integer k=0;k<n;k=k+1)begin
 check(lasts[k]==(k==n-1),"last exactly on final output");
 check(xs[k]==px[k] && ys[k]==py[k],"input order and coordinates");
 for(integer q=0;q<k;q=q+1)check(ids[q]!=ids[k],"unique IDs within frame");
 end
 end endtask
 task alarm_sample(input integer pos,input integer dwell);begin
 @(negedge clk);avin=1;ax=pos;ad=dwell;
 @(negedge clk);avin=0;@(negedge clk);
 end endtask
 initial begin
 reset;
 px[0]=20;py[0]=20;px[1]=40;py[1]=20;frame(2);
 check(dws[0]==1 && dws[1]==1,"new nearby tracks both dwell one");
 oldid=ids[0];persistent=ids[1];frame(2);
 check(ids[0]==oldid && ids[1]==persistent && dws[0]==2 && dws[1]==2,"near tracks remain separate next frame");
 reset;
 for(i=0;i<16;i=i+1)begin px[i]=100+i*100;py[i]=100;end
 frame(16);for(i=0;i<16;i=i+1)check(dws[i]==1,"sixteen new tracks");
 frame(16);for(i=0;i<16;i=i+1)check(ids[i]==i && dws[i]==2,"sixteen persistent tracks");
 // Full live table rejects only the unmatched target. Last still marks the
 // final accepted item, including when the rejected target is first/last.
 px[0]=10000;px[1]=100;px[2]=200;py[0]=100;py[1]=100;py[2]=100;
 n=0;send(3);settle;
 check(n==2 && ids[0]==0 && ids[1]==1 && xs[0]==100 && xs[1]==200,"full table accepted outputs keep input order");
 check(lasts[0]==0 && lasts[1]==1,"full table rejected input does not corrupt last");
 px[0]=100;px[1]=200;px[2]=10000;n=0;send(3);settle;
 check(n==2 && lasts[1]==1,"last rejected input still terminates accepted stream");
 // Stable nearest/tie order, including 17-bit centre arithmetic at high coordinates.
 reset;px[0]=39990;px[1]=40010;py[0]=0;py[1]=0;frame(2);
 px[0]=40000;frame(1);check(ids[0]==0 && dws[0]==2,"equal distance chooses first track at high coordinates");
 reset;px[0]=100;py[0]=100;frame(1);px[0]=124;py[0]=124;frame(1);
 check(ids[0]==0 && dws[0]==2,"Manhattan distance exactly MATCH_DIST matches");
 px[0]=149;py[0]=148;frame(1);check(ids[0]==1 && dws[0]==1,"Manhattan distance MATCH_DIST plus one does not match");
 reset;px[0]=10;py[0]=0;frame(1);oldid=ids[0];
 frame(0);frame(0);frame(1);check(ids[0]==oldid && dws[0]==2,"MISSED_MAX empty frames retain the track");
 frame(0);frame(0);frame(0);frame(1);check(ids[0]!=oldid && dws[0]==1,"MISSED_MAX plus one empty frames retire the track");
 // Natural lifetimes: keep id zero alive while all other IDs roll around.
 reset;px[0]=10;py[0]=0;frame(1);persistent=ids[0];
 for(i=0;i<257;i=i+1)begin
 px[1]=1000;py[1]=0;frame(2);
 check(ids[0]==persistent && ids[1]!=persistent && dws[1]==1,"wrap never duplicates a live ID");
 if(i==0)check(ids[1]==1,"first churn id");
 if(i==255)check(ids[1]==1,"wrap skips occupied zero");
 frame(1);frame(1);frame(1);
 end
 // Next frame metadata arrives while the previous frame is still processing.
 reset;for(i=0;i<16;i=i+1)begin px[i]=100+i*100;py[i]=50;end
 n=0;send(16);
 for(i=0;i<16;i=i+1)begin @(negedge clk);v=1;x=px[i]+1;y=51;last=(i==15);end
 @(negedge clk);v=0;last=0;settle;
 check(n==16,"first frame survives overlapping capture");
 n=0;@(negedge clk);tick=1;start_cycle=cycle;@(negedge clk);tick=0;settle;
 check(n==16,"next frame capture has no drops");
 for(i=0;i<16;i=i+1)check(ids[i]==i && dws[i]==2 && xs[i]==px[i]+1 && ys[i]==51,"overlap retains all metadata");
 // A valid on the tick is the first target of the new accumulation window.
 reset;n=0;@(negedge clk);tick=1;v=1;x=600;y=7;
 @(negedge clk);tick=0;v=0;settle;check(n==0,"tick closes prior empty window");
 send(0);settle;check(n==1 && xs[0]==600,"tick coincident valid preserved for next frame");
 reset;threshold=0;alarm_sample(40,1);alarm_sample(60,1);
 check(events==0,"reused id does not inherit crossing history");
 alarm_sample(40,2);alarm_sample(60,3);check(crosses==1,"real crossing after id reuse");
 reset;threshold=1;alarm_sample(60,1);check(dwells==1,"threshold one alerts on first observation");
 reset;threshold=65535;alarm_sample(60,1);alarm_sample(60,65535);alarm_sample(60,65535);
 check(dwells==1,"saturated dwell alerts once");
 $display("TRACK_RESOURCE_DONE errors=%0d max_output_latency=%0d",errors,max_latency);
 if(errors)$fatal(1,"track resource regression");$finish;
 end
 initial begin #200000000;$fatal(1,"test timeout");end
endmodule
