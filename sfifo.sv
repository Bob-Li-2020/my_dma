// synchronous dual-port simple fifo. 
// NOTE: NO READ/WRITE PROTECTION

module sfifo 
#(
    DW         = 32, 
    AW         = 4, 
    SHOW_AHEAD = 0 
)(
    input  logic            clk    ,
    input  logic            rst_n  ,
    input  logic            we     ,
    input  logic            re     ,
    input  logic [DW-1 : 0] d      ,
    output logic [DW-1 : 0] q      ,
    output logic            rempty ,
    output logic            wfull  ,
    output logic [AW   : 0] cnt     
);

reg  [DW-1 : 0] rf [2**AW-1:0];
reg  [AW   : 0] wa ;
reg  [AW   : 0] ra ;
wire [AW   : 0] s = wa-ra;

assign wfull  = s[AW];
assign rempty = s==0 ;
assign cnt    = s    ;

always @(posedge clk or negedge rst_n)
    if(~rst_n) begin
        wa <= 0;
        ra <= 0;
    end
    else begin
        wa <= wa+we;
        ra <= ra+re;
    end

always @(posedge clk) 
	if(we) 
		rf [wa[AW-1:0]] <= d;

generate if(SHOW_AHEAD) begin: SHOW_AHEAD_Q
	always @ *
	       q = rf [ra[AW-1:0]];
end else begin: NO_SHOW_AHEAD_Q
	always @(posedge clk)
		q <= rf[ra[AW-1:0]];
end endgenerate

endmodule
