//-- AUTHOR: LIBING
//-- DATE: 2020.5
//-- DESCRIPTION: 
//-- DMA write(OCM->EXTERNAL): Move output featuremap from OCM to external.

module dma_w 
#(
	//--------- AXI PARAMETERS -------
    AXI_DW     = 128                 , // AXI DATA    BUS WIDTH
    AXI_BYTES  = AXI_DW/8            , // BYTES NUMBER IN <AXI_DW>
    AXI_WSTRBW = AXI_BYTES           , // AXI WSTRB BITS WIDTH
    //--------- RAM ATTRIBUTES -------
    RAM_WS     = 1                     // RAM MODEL READ WAIT STATES CYCLE
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
    //---- DMA WRITE CONFIGURE ------------------
    output logic                    dmaw_valid  ,
    input  logic                    dmaw_ready  ,
    output logic [31           : 0] dmaw_sa     , // dma write start address   
    output logic [31           : 0] dmaw_len    , // dma write length
    //---- DMA WRITE DATA -----------------------
    output logic [AXI_DW-1     : 0] dma_wdata   ,
    output logic [AXI_WSTRBW-1 : 0] dma_wstrb   ,
    output logic                    dma_wlast   ,
    output logic                    dma_wvalid  ,
    input  logic                    dma_wready  ,
    //---- RAM INTERFACE ------------------------
    output logic                    ram_re      , // RAM read en
    output logic [31           : 0] ram_a       , // RAM address
    input  logic [AXI_DW-1     : 0] ram_q         // RAM Q
);

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
// dma write configure
assign dmaw_valid = cfg_valid        ;
assign dmaw_sa    = cfg_dst_sa       ;
assign dmaw_len   = cfg_len          ;
// dma write data
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

//------- wait states control -------------
generate 
    if(RAM_WS==0) begin: WS0
        assign ram_rvalid = ram_re   ;
        assign wff_wafull = wff_wfull;
    end: WS0
    else begin: WS_N
        logic [RAM_WS : 0] ram_re_ff   ;
        logic [WFF_AW : 0] rff_wcnt_af ; // rff wcnt almost full
        assign ram_rvalid = ram_re_ff[RAM_WS-1];
        assign wff_wafull = rff_wcnt_af >= 2**WFF_AW;
        always_ff @(posedge usr_clk or negedge usr_reset_n)
            if(!usr_reset_n)
                ram_re_ff <= '0;
            else
                ram_re_ff <= {ram_re_ff[RAM_WS-1:0], ram_re};

        always_comb begin
            rff_wcnt_af = wff_cnt;
            for(int k=0;k<RAM_WS;k++) begin
                rff_wcnt_af = rff_wcnt_af+ram_re_ff[k];
            end
        end
    end: WS_N
endgenerate

endmodule
