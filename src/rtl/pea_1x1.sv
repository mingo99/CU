// `include "typedef.svh"

module pea_1x1 #(
    parameter COL       = 8,
    parameter WGT_WIDTH = 8,
    parameter IFM_WIDTH = 64,
    parameter OFM_WIDTH = 32,
    parameter RF_AWIDTH = 4,
    parameter PE_DWIDTH = 16
) (
    input wire           clk,
    input wire           rstn,
    input wire           stride,
    input wire           wgt_read,
    input wire           ifm_read,
    input wire [COL-1:0] pvalid,
    input wire           ic_done,
    input wire           oc_done,

    input wire [WGT_WIDTH-1:0] wgt_group,
    input wire [IFM_WIDTH-1:0] ifm_group,

    output wire  [COL-1:0] sum_valid,
    output sum_t           sum      [COL]
);

    wire [7:0] wgt_buf;
    wire [COL*8-1:0] ifm_buf;

    wire [PE_DWIDTH-1:0] pe_data[COL];

    wire [COL-1:0] result_valid;
    assign sum_valid = stride ? result_valid & {(COL >> 1) {2'b01}} : result_valid;

    genvar col;
    generate
        for (col = 0; col < COL; col = col + 1) begin : g_pe_col
            wire [7:0] ifm_in;
            assign ifm_in = ifm_buf[col*8+:8];
            pe_1x1 #(
                .DWIDTH(PE_DWIDTH)
            ) u_pe_1x1 (
                .clk   (clk),
                .rstn  (rstn),
                .ifm_in(ifm_in),
                .wgt_in(wgt_buf),
                .psum  (pe_data[col])
            );

        end

        rf_ifm #(
            .COL(COL)
        ) u_rf_ifm (
            .clk     (clk),
            .rstn    (rstn),
            .ifm_in  (ifm_group),
            .ifm_read(ifm_read),
            .ifm_buf (ifm_buf)
        );

        rf_wgt u_rf_wgt (
            .clk     (clk),
            .rstn    (rstn),
            .wgt_in  (wgt_group),
            .wgt_read(wgt_read),
            .wgt_buf (wgt_buf)
        );

        for (col = 0; col < COL; col = col + 1) begin : g_psum_buffer
            rf_psum #(
                .DWIDTH(OFM_WIDTH),
                .AWIDTH(RF_AWIDTH)
            ) u_rf_psum (
                .clk         (clk),
                .rstn        (rstn),
                .ic_done     (ic_done),
                .oc_done     (oc_done),
                .data_valid  (pvalid[col]),
                .pe_data     (pe_data[col]),
                .result_valid(result_valid[col]),
                .result      (sum[col])
            );

        end
    endgenerate


endmodule

