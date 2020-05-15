//-- AUTHOR: LIBING
//-- DATE: 2020.5
//-- DESCRIPTION: 
//-- DMA read(EXTERNAL->OCM): Move "cfg_len" data from external memory(cfg_src_sa) to OCM(cfg_dst_sa).

module dma_r_regular
#(
	//--------- AXI PARAMETERS -------
    AXI_DW = 128                   // AXI DATA    BUS WIDTH
)(
    //---- USER GLOBAL ----------------------
    input  logic                usr_clk     , // ram clock domain
    input  logic                usr_reset_n , // ram clock domain reset_n
    //---- CONFIGURE ------------------------
    input  logic                cfg_valid   ,
    output logic                cfg_ready   ,
    input  logic [31       : 0] cfg_src_sa  , // source start address
    input  logic [31       : 0] cfg_dst_sa  , // destination start address
    input  logic [31       : 0] cfg_len     , // DMA bytes number
    //---- ami interface.config -------------
    output logic                dmar_valid  ,
    input  logic                dmar_ready  ,
    output logic [31       : 0] dmar_sa     , // dma read start address   
    output logic [31       : 0] dmar_len    , // dma read length
    //---- ami interface.data ---------------
    input  logic [AXI_DW-1 : 0] dma_rdata   ,
    input  logic                dma_rlast   ,
    input  logic                dma_rvalid  ,
    output logic                dma_rready  ,
    //---- RAM INTERFACE --------------------
    output logic                ram_we      , // RAM write en
    output logic [31       : 0] ram_a       , // RAM address
    output logic [AXI_DW-1 : 0] ram_d         // RAM D
);

timeunit 1ns;
timeprecision 1ps;

localparam L = $clog2(AXI_DW/8);
enum logic {IDLE=1'b0, BUSY} st_cur, st_nxt;
logic [31 : L] ram_addr ;

//---- CONFIGURE ---------------------
assign cfg_ready  = st_cur==IDLE & dmar_ready;
//---- DMA READ CONFIGURE ------------
assign dmar_valid = cfg_valid        ;
assign dmar_sa    = cfg_src_sa       ; // dma read start address   
assign dmar_len   = cfg_len          ; // dma read length
//---- DMA READ DATA -----------------
assign dma_rready = st_cur==BUSY     ;
//---- RAM INTERFACE -----------------
assign ram_we     = dma_rvalid & dma_rready; // RAM write en
assign ram_a      = {ram_addr, {L{1'b0}}}; // RAM address
assign ram_d      = dma_rdata;  // RAM D

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n)
        st_cur <= IDLE;
    else
        st_cur <= st_nxt;

always_comb 
    case(st_cur)
        IDLE: st_nxt = cfg_ready & cfg_valid ? BUSY : st_cur;
        BUSY: st_nxt = ram_we & dma_rlast ? IDLE : st_cur;
        default: st_nxt = IDLE;
    endcase

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n)
        ram_addr <= 0;
    else if(cfg_valid & cfg_ready)
        ram_addr <= cfg_dst_sa[31:L];
    else if(st_cur==BUSY)
        ram_addr <= ram_addr+ram_we;

endmodule
