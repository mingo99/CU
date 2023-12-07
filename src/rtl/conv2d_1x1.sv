///==------------------------------------------------------------------==///
/// Conv kernel: top level module
///==------------------------------------------------------------------==///
module conv2d_1x1 #(
    parameter COL           = 8,
    parameter WGT_WIDTH     = 8,
    parameter IFM_WIDTH     = 64,
    parameter OFM_WIDTH     = 32,
    parameter RF_AWIDTH     = 4,
    parameter PE_DWIDTH     = 16,
    parameter TILE_LEN      = 16,
    parameter CHN_WIDTH     = 4,
    parameter CHN_OFT_WIDTH = 6,
    parameter FMS_WIDTH     = 8,
    parameter TC_ROW_WIDTH  = 6,
    parameter TC_COL_WIDTH  = 6,   // pixel col/row counter width
    parameter PC_ROW_WIDTH  = 4,
    parameter PC_COL_WIDTH  = 4    // pixel col/row counter width
) (
    input wire                 clk,
    input wire                 rstn,
    input wire [CHN_WIDTH-1:0] cfg_ci,
    input wire [CHN_WIDTH-1:0] cfg_co,
    input wire                 cfg_stride,
    input wire [FMS_WIDTH-1:0] cfg_ifm_size,
    input wire                 start_conv,
    input wire [IFM_WIDTH-1:0] ifm_group,
    input wire [WGT_WIDTH-1:0] wgt_group,

    input wire [PC_ROW_WIDTH-1:0] tile_row_offset,
    input wire [PC_COL_WIDTH-1:0] tile_col_offset,
    input wire [TC_ROW_WIDTH-1:0] tc_row_max,
    input wire [TC_COL_WIDTH-1:0] tc_col_max,

    output wire                 ifm_read,
    output wire                 wgt_read,
    output wire                 conv_done,
    output wire       [COL-1:0] sum_valid,
    output wire sum_t           sum      [COL]
);

    // stage configuration parameters
    reg stride_reg;
    reg [5:0] chi_reg, cho_reg;
    reg [FMS_WIDTH-1:0] ifm_size_reg;

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            chi_reg      <= 'b0;
            cho_reg      <= 'b0;
            stride_reg   <= 'b0;
            ifm_size_reg <= 'b0;
        end else if (start_conv) begin
            chi_reg      <= cfg_ci;
            cho_reg      <= cfg_co;
            stride_reg   <= cfg_stride;
            ifm_size_reg <= cfg_ifm_size;
        end
    end

    wire [5:0] chi, cho;
    wire stride;
    wire [FMS_WIDTH-1:0] ifm_size;

    assign chi      = start_conv ? cfg_ci : chi_reg;
    assign cho      = start_conv ? cfg_co : cho_reg;
    assign stride   = start_conv ? cfg_stride : stride_reg;
    assign ifm_size = start_conv ? cfg_ifm_size : ifm_size_reg;

    ///==-------------------------------------------------------------------------------------==

    // wire pvalid, ic_done, oc_done;
    wire ic_done, oc_done;
    wire [COL-1:0] pvalid;

    pea_ctrl #(
        .COL          (COL),
        .TILE_LEN     (TILE_LEN),
        .CHN_WIDTH    (CHN_WIDTH),
        .CHN_OFT_WIDTH(CHN_OFT_WIDTH),
        .FMS_WIDTH    (FMS_WIDTH),
        .TC_COL_WIDTH (TC_COL_WIDTH),
        .TC_ROW_WIDTH (TC_ROW_WIDTH),
        .PC_COL_WIDTH (PC_COL_WIDTH),
        .PC_ROW_WIDTH (PC_ROW_WIDTH)
    ) u_pea_ctrl (
        .clk            (clk),
        .rstn           (rstn),
        .chi            (chi),
        .cho            (cho),
        .stride         (stride),
        .ifm_size       (ifm_size),
        .start_conv     (start_conv),
        .tile_row_offset(tile_row_offset),
        .tile_col_offset(tile_col_offset),
        .tc_row_max     (tc_row_max),
        .tc_col_max     (tc_col_max),
        .ifm_read       (ifm_read),
        .wgt_read       (wgt_read),
        .pvalid         (pvalid),
        .ic_done        (ic_done),
        .oc_done        (oc_done),
        .conv_done      (conv_done)
    );

    pea_1x1 #(
        .COL      (COL),
        .WGT_WIDTH(WGT_WIDTH),
        .IFM_WIDTH(IFM_WIDTH),
        .OFM_WIDTH(OFM_WIDTH),
        .RF_AWIDTH(RF_AWIDTH),
        .PE_DWIDTH(PE_DWIDTH)
    ) u_pea_1x1 (
        .clk      (clk),
        .rstn     (rstn),
        .stride   (stride),
        .wgt_read (wgt_read),
        .ifm_read (ifm_read),
        .pvalid   (pvalid),
        .ic_done  (ic_done),
        .oc_done  (oc_done),
        .wgt_group(wgt_group),
        .ifm_group(ifm_group),
        .sum_valid(sum_valid),
        .sum      (sum)
    );


endmodule

