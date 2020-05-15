//-- AUTHOR: LIBING
//-- DATE: 2020.5
//-- DESCRIPTION: 
//-- DMA read(EXTERNAL->OCM): Move fmap data from external memory to OCM.
// imagine a whole featuremap with dimension of W*H*C, move a block of it with size of W*h*c from external memory to OCM.
// cfg_len = W*h*c
// cfg_N = W*H
// cfg_n = W*h
// cfg_a = W*a
// where:
//        'W' is the total width
//        'H' is the total height
//        'C' is the total channel number
//        'h' is the block height
//        'c' is the block channel number
//        'a' is the number of overlapped rows

module dma_r_fmap 
#(
    AXI_DW = 128 
)(
    //---- USER GLOBAL -----------------------
    input  logic                usr_clk      , // ram clock domain
    input  logic                usr_reset_n  , // ram clock domain reset_n
    //---- CONFIGURE -------------------------
    input  logic                cfg_valid    ,
    output logic                cfg_ready    ,
    input  logic [31       : 0] cfg_src_sa   , // source      start address
    input  logic [31       : 0] cfg_dst_sa   , // destination start address
    input  logic [31       : 0] cfg_len      , // W*h*c, in bytes.
    input  logic [31       : 0] cfg_N        , // W*H  , in bytes.
    input  logic [31       : 0] cfg_n        , // W*h  , in bytes.
    input  logic [31       : 0] cfg_a        , // W*a  , in bytes. a: overlap line number along height direction blocks
    output logic                irq          ,
    output logic                irq_clear    ,
    output logic [4        : 0] err          ,
    //---- ami interface.config --------------
    output logic                dmar_valid   ,
    input  logic                dmar_ready   ,
    output logic [31       : 0] dmar_sa      ,
    output logic [31       : 0] dmar_len     ,
    output logic                dmar_irq_w1c ,
    input  logic                dmar_irq     ,
    input  logic [3        : 0] dmar_err     ,
    //---- ami interface.data ----------------
    input  logic [AXI_DW-1 : 0] dma_rdata    ,
    input  logic                dma_rlast    ,
    input  logic                dma_rvalid   ,
    output logic                dma_rready   ,
    //---- RAM interface ---------------------
    output logic                ram_we       ,
    output logic [31       : 0] ram_a        ,
    output logic [AXI_DW-1 : 0] ram_d         
);

timeunit 1ns;
timeprecision 1ps;

localparam L = $clog2(AXI_DW/8);

enum logic [1:0] { MOVE=2'b00, DONE, ERROR } st_cur, st_nxt; // "MOVE": DMA moving data; "DONE": configuration done; "ERROR": DMA error.

always_comb 
    case(st_cur)
        MOVE: st_cur = dmar_irq && ;
    endcase

// dma_r_regular configure
logic                cfg2_valid   ;
logic                cfg2_ready   ;
logic [31       : 0] cfg2_src_sa  ; // source start address
logic [31       : 0] cfg2_dst_sa  ; // destination start address
logic [31       : 0] cfg2_len     ; // DMA bytes number
// register latches
logic [31       : 0] src_sa; // source      start address
logic [31       : 0] dst_sa; // destination start address
logic [31       : 0] len   ; // W*h*c, in bytes.
logic [31       : 0] N     ; // W*H  , in bytes.
logic [31       : 0] n     ; // W*h  , in bytes.
logic [31       : 0] a     ; // W*a  , in bytes. a: overlap line number along height direction blocks

assign cfg2_valid = st_cur==MOVE && (cfg_valid || 

dma_r_regular #(
    .AXI_DW ( AXI_DW ) 
) u_dma_r_regular (
    .*,
    .cfg_valid  ( cfg2_valid  ),
    .cfg_ready  ( cfg2_ready  ),
    .cfg_src_sa ( cfg2_src_sa ),
    .cfg_dst_sa ( cfg2_dst_sa ),
    .cfg_len    ( cfg2_len    )
);

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n) begin
        src_sa <= 0;  
        dst_sa <= 0;
        len    <= 0;
        N      <= 0;
        n      <= 0;
        a      <= 0;
    end else if(cfg_valid & cfg_ready) begin
        src_sa <= cfg_src_sa; 
        dst_sa <= cfg_dst_sa;
        len    <= cfg_len   ;
        N      <= cfg_N     ;
        n      <= cfg_n     ;
        a      <= cfg_a     ;
    end



endmodule
