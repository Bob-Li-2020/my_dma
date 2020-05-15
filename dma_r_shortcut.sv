//-- AUTHOR: LIBING
//-- DATE: 2020.5
//-- DESCRIPTION: 
//-- DMA read(EXTERNAL->OCM): Move data from external memory to OCM. Before writing to OCM, shortcut is performed.
// TODO : H BLOCKING AND C BLOCKING.

module dma_r_shortcut
#(
	//--------- AXI PARAMETERS -------
    AXI_DW     = 128,                // AXI DATA    BUS WIDTH
    AMI_RD     = 16                  // AMI R CHANNEL BUFFER DEPTH
)(
    //---- USER GLOBAL ----------------------
    input  logic                usr_clk     , // ram clock domain
    input  logic                usr_reset_n , // ram clock domain reset_n
    //---- CONFIGURE ------------------------
    input  logic                cfg_valid   ,
    output logic                cfg_ready   ,
    input  logic [31       : 0] cfg_src0_sa , // shortcut source 0 start address
    input  logic [31       : 0] cfg_src1_sa , // shortcut source 1 start address
    input  logic [31       : 0] cfg_dst_sa  , // destination start address
    input  logic [31       : 0] cfg_len     , // DMA bytes number
    //---- DMA READ CONFIGURE ---------------
    output logic                dmar_valid  ,
    input  logic                dmar_ready  ,
    output logic [31       : 0] dmar_sa     , // dma read start address   
    output logic [31       : 0] dmar_len    , // dma read length
    //---- DMA READ DATA --------------------
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

localparam BUF1_DW = AXI_DW,
           BUF1_AW = $clog2(AMI_RD);

localparam L = $clog2(AXI_DW/8);

enum logic [1:0] {IDLE=2'b00, SRC0, SRC1 } st_cur, st_nxt; // SRC0: DMA read source0; SRC1: DMA read source1.
logic dma_done;

// fifo
logic                buf1_we     ;
logic                buf1_re     ;
logic [WFF_DW-1 : 0] buf1_d      ;
logic [WFF_DW-1 : 0] buf1_q      ;
logic                buf1_rempty ;
logic                buf1_wfull  ;
logic                buf1_wafull ;
logic [WFF_AW   : 0] buf1_cnt    ;
logic                buf1_rlast  ;

always_ff @(posedge usr_clk or negedge usr_reset_n)
    if(!usr_reset_n)
        st_cur <= IDLE;
    else
        st_cur <= st_nxt;

always_comb 
    case(st_cur)
        IDLE: st_nxt = cfg_valid & cfg_ready ? SRC0 : st_cur;
        SRC0: st_nxt = dma_rlast ? (dma_done ? IDLE : SRC1) : st_cur;
        SRC1: st_nxt = dma_rlast ? (dma_done ? IDLE : SRC0) : st_cur;
        default: st_nxt = IDLE;
    endcase

sfifo #(
    .DW         ( BUF1_DW ),
    .AW         ( BUF1_AW ),
    .SHOW_AHEAD ( 1       ) 
) src1_buffer (
    .clk    ( usr_clk ),
    .rst_n  ( usr_reset_n ),
    .we     ( buf1_we     ),
    .re     ( buf1_re     ),
    .d      ( buf1_d      ),
    .q      ( buf1_q      ),
    .rempty ( buf1_rempty ),
    .wfull  ( buf1_wfull  ),
    .cnt    ( buf1_cnt    ) 
);

endmodule
