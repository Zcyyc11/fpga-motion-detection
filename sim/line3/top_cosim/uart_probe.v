`timescale 1ns / 1ps
// Independent observation only: byte sampling sees tx, reference sees UART inputs.
// No receiver decoder output is used to make the reference table.
module line3_uart_probe #(parameter integer BIT_NS=500)(
    input wire clk, rst_n, tx, tick,
    input wire [15:0] video_frame,
    input wire tv, input wire [7:0] tid,
    input wire [15:0] x1,y1,x2,y2,
    input wire ev, input wire [7:0] eid,
    input wire [1:0] etype, input wire [15:0] cx,
    input wire drop
);
    integer bytes_fd, ref_fd, faults_fd;
    integer uf=0, count=0, k;
    reg [7:0] value;
    initial begin
        bytes_fd=$fopen("uart_bytes.csv","w");
        ref_fd=$fopen("tx_inputs.csv","w");
        faults_fd=$fopen("probe_faults.txt","w");
        if (!bytes_fd || !ref_fd || !faults_fd) $fatal(1,"LINE3 probe output open failed");
        $fwrite(bytes_fd,"time_ns,byte_hex\n");
        $fwrite(ref_fd,"kind,uart_frame,video_frame,time_ns,fields\n");
        wait(rst_n === 1'b1);
        forever begin
            @(negedge tx);
            #(BIT_NS/2);
            if (tx !== 1'b0) $fwrite(faults_fd,"bad start at %0t\n",$time);
            #(BIT_NS);
            for(k=0;k<8;k=k+1) begin
                if (tx !== 1'b0 && tx !== 1'b1) $fwrite(faults_fd,"unknown data at %0t\n",$time);
                value[k]=tx;
                #(BIT_NS);
            end
            if (tx !== 1'b1) $fwrite(faults_fd,"bad stop at %0t\n",$time);
            $fwrite(bytes_fd,"%0d,%02x\n",$time,value);
            $fflush(bytes_fd);
            $fflush(faults_fd);
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin uf=0; count=0; end
        else begin
            if ($isunknown({tick,tv,ev,drop,video_frame}))
                $fwrite(faults_fd,"unknown control at %0t\n",$time);
            if (drop) $fwrite(faults_fd,"uart_drop at %0t\n",$time);
            if (tick) begin
                if (tv || ev) $fwrite(faults_fd,"tick/input collision at %0t\n",$time);
                $fwrite(ref_fd,"H,%0d,%0d,%0d,%0d\n",uf,video_frame,$time,count);
                uf=(uf+1)&65535;
                count=0;
            end else begin
                if (tv) begin
                    if ($isunknown({tid,x1,y1,x2,y2})) $fwrite(faults_fd,"unknown target at %0t\n",$time);
                    $fwrite(ref_fd,"T,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0\n",uf,video_frame,$time,tid,x1,y1,x2,y2);
                    count=count+1;
                end
                if (ev) begin
                    if ($isunknown({eid,etype,cx})) $fwrite(faults_fd,"unknown event at %0t\n",$time);
                    $fwrite(ref_fd,"E,%0d,%0d,%0d,%0d,%0d,%0d\n",uf,video_frame,$time,eid,etype,cx);
                end
            end
            $fflush(ref_fd);
        end
    end
endmodule
