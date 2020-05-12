//-- AUTHOR: LIBING
//-- DATE: 2020.5
//-- DESCRIPTION: 
//-- DMA read(EXTERNAL->OCM): Move input featuremap from external to OCM.

module dma_r 
#(
	//--------- AXI PARAMETERS -------
    AXI_DW     = 128                   // AXI DATA    BUS WIDTH
)(
    //---- USER GLOBAL --------------------------
    input  logic                    usr_clk     , // ram clock domain
    input  logic                    usr_reset_n , // ram clock domain reset_n
    //---- CONFIGURE ----------------------------
    input  logic                    cfg_valid   ,
    output logic                    cfg_ready   ,
    input  logic [31           : 0] cfg_src_sa  , // source start address
    input  logic [31           : 0] cfg_dst_sa  , // destination start address
    input  logic [31           : 0] cfg_len     , // DMA bytes number
    //---- DMA READ CONFIGURE ------------------
    output logic                    dmar_valid  ,
    input  logic                    dmar_ready  ,
    output logic [31           : 0] dmar_sa     , // dma read start address   
    output logic [31           : 0] dmar_len    , // dma read length
    //---- DMA READ DATA -----------------------
    input  logic [AXI_DW-1     : 0] dma_rdata   ,
    input  logic                    dma_rlast   ,
    input  logic                    dma_rvalid  ,
    output logic                    dma_rready  ,
    //---- RAM INTERFACE ------------------------
    output logic                    ram_we      , // RAM write en
    output logic [31           : 0] ram_a       , // RAM address
    output logic [AXI_DW-1     : 0] ram_d         // RAM D
);

timeunit 1ns;
timeprecision 1ps;

localparam L = $clog2(AXI_DW/8);
localparam WFF_DW = AXI_DW,
           WFF_AW = 4;

enum logic [1:0] {IDLE=2'b0, BUSY, WAIT} st_cur, st_nxt; 

// fifo
logic                wff_we     ;
logic                wff_re     ;
logic [WFF_DW-1 : 0] wff_d      ;
logic [WFF_DW-1 : 0] wff_q      ;
logic                wff_rempty ;
logic                wff_wfull  ;
logic                wff_wafull ;
logic [WFF_AW   : 0] wff_cnt    ;
logic                wff_rlast  ;
// ram
logic                ram_rvalid ;
logic                ram_rlast  ;
// counter
logic [31       : L] src_sa     ;
logic [31       : L] len        ;
logic [31       : L] addr       ;
logic [31       : L] wff_re_cc  ;

// fifo
assign wff_we     = ram_rvalid       ; // & !wff_wfull; ensure that when wff_we==1'b1 wff is not full.
assign wff_re     = dma_wready & dma_wvalid;
assign wff_d      = ram_q            ;
assign wff_rlast  = wff_re && wff_re_cc+1'b1==len;
// cfg
assign cfg_ready  = st_cur==IDLE && dmaw_ready;
// dma read configure
assign dmaw_valid = cfg_valid        ;
assign dmaw_sa    = cfg_dst_sa       ;
assign dmaw_len   = cfg_len          ;
// dma read data
assign dma_wdata  = wff_q            ;
assign dma_wstrb  = '1               ;
assign dma_wlast  = dma_wvalid && wff_re_cc+1'b1==len;
assign dma_wvalid = !wff_rempty      ;
// ram
assign ram_re     = st_cur==BUSY && !wff_wafull; // RAM read en
assign ram_a      = {addr, {L{1'b0}}}; // RAM address
assign ram_rlast  = st_cur==BUSY && (ram_re && addr+1'b1==src_sa+len);

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n)
        st_cur <= IDLE;
    else
        st_cur <= st_nxt;

always_comb 
    case(st_cur)
        IDLE: st_nxt = cfg_ready & cfg_valid ? BUSY : st_cur;
        BUSY: st_nxt = ram_rlast ? WAIT : st_cur;
        WAIT: st_nxt = wff_rlast ? IDLE : st_cur;
        default: st_nxt = IDLE;
    endcase

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n) 
        addr <= 0;
    else if(st_cur==IDLE && st_nxt==BUSY) 
        addr <= cfg_src_sa[31:L];
    else if(st_cur==BUSY) 
        addr <= addr+ram_re;

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n) 
        wff_re_cc <= 0;
    else if(st_cur==IDLE && st_nxt==BUSY) 
        wff_re_cc <= 0;
    else if(st_cur==BUSY || st_cur==WAIT) 
        wff_re_cc <= wff_re_cc+wff_re;

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n) 
    begin
        src_sa <= 0;
        len <= 0;
    end 
    else if(cfg_valid & cfg_ready) begin
        src_sa <= cfg_src_sa;
        len <= cfg_len;
    end

sfifo #(
    .DW         ( WFF_DW ),
    .AW         ( WFF_AW ),
    .SHOW_AHEAD ( 1      ) 
) w_buffer (
    .clk    ( usr_clk     ),
    .rst_n  ( usr_reset_n ),
    .we     ( wff_we      ),
    .re     ( wff_re      ),
    .d      ( wff_d       ),
    .q      ( wff_q       ),
    .rempty ( wff_rempty  ),
    .wfull  ( wff_wfull   ),
    .cnt    ( wff_cnt     ) 
);
endmodule
