module pea_ctrl #(
    parameter COL           = 8,
    parameter TILE_LEN      = 16,
    parameter CHN_WIDTH     = 4,
    parameter CHN_OFT_WIDTH = 6,
    parameter FMS_WIDTH     = 8,
    parameter TC_COL_WIDTH  = 6,   // Pixel col/row counter width
    parameter TC_ROW_WIDTH  = 6,
    parameter PC_COL_WIDTH  = 4,   // Pixel col/row counter width
    parameter PC_ROW_WIDTH  = 4
) (
    input wire                 clk,
    input wire                 rstn,
    input wire [CHN_WIDTH-1:0] chi,
    input wire [CHN_WIDTH-1:0] cho,
    input wire                 stride,
    input wire [FMS_WIDTH-1:0] ifm_size,   // With padding
    input wire                 start_conv,

    input wire [PC_ROW_WIDTH-1:0] tile_row_offset,
    input wire [PC_COL_WIDTH-1:0] tile_col_offset,
    input wire [TC_ROW_WIDTH-1:0] tc_row_max,
    input wire [TC_COL_WIDTH-1:0] tc_col_max,

    output wire           ifm_read,
    output wire           wgt_read,
    output wire [COL-1:0] pvalid,
    output wire           ic_done,
    output wire           oc_done,
    output wire           conv_done
);
    localparam CH_CNT_WIDTH = CHN_WIDTH + CHN_OFT_WIDTH;

    // Output feature map
    wire [FMS_WIDTH-1:0] ofm_size;
    assign ofm_size = stride ? ((ifm_size - 1) >> 1) + 1'b1 : ifm_size;

    // Channel number decode
    wire [CH_CNT_WIDTH-1:0] ic_num, oc_num;
    assign ic_num = (chi << CHN_OFT_WIDTH) - 1'b1;
    assign oc_num = (cho << CHN_OFT_WIDTH) - 1'b1;

    reg [TC_ROW_WIDTH-1:0] tc_row;
    reg [TC_COL_WIDTH-1:0] tc_col;

    wire tile_row_last, tile_col_last;
    assign tile_row_last = tc_row == tc_row_max;
    assign tile_col_last = tc_col == tc_col_max;

    wire tile_done, tile_ver_done;

    wire [TC_ROW_WIDTH-1:0] tc_row_nxt = conv_done ? 'b0 : tc_row + tile_ver_done;
    wire [TC_COL_WIDTH-1:0] tc_col_nxt = tile_ver_done ? 'b0 : tc_col + tile_done;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tc_row <= 'b0;
            tc_col <= 'b0;
        end else begin
            tc_row <= tc_row_nxt;
            tc_col <= tc_col_nxt;
        end
    end

    reg [PC_COL_WIDTH-1:0] pc_col;
    wire [PC_COL_WIDTH-1:0] pc_col_max, pc_col_nxt;

    wire cnt_valid;
    assign pc_col_max = tile_col_last & (|tile_col_offset) ? tile_col_offset - 1 : TILE_LEN - 1;
    assign pc_col_nxt = ic_done ? 'b0 : pc_col + cnt_valid;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pc_col <= 'b0;
        end else begin
            pc_col <= pc_col_nxt;
        end
    end

    wire ic_last, oc_last;
    reg [CH_CNT_WIDTH-1:0] ic_cnt, oc_cnt;
    wire [CH_CNT_WIDTH-1:0] ic_cnt_nxt, oc_cnt_nxt;
    assign ic_cnt_nxt = ic_done ? (ic_last ? 'b0 : ic_cnt + 1'b1) : ic_cnt;
    assign oc_cnt_nxt = oc_done ? (oc_last ? 'b0 : oc_cnt + 1'b1) : oc_cnt;

    assign ic_last = (ic_cnt == ic_num);
    assign oc_last = oc_cnt == oc_num;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ic_cnt <= 'b0;
            oc_cnt <= 'b0;
        end else begin
            ic_cnt <= ic_cnt_nxt;
            oc_cnt <= oc_cnt_nxt;
        end
    end

    // wire pc_col_last = pc_col == pc_col_max;
    wire pc_col_last = pc_col == (TILE_LEN - 1);

    reg [4:0] conv_done_reg;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) conv_done_reg <= 'b0;
        else conv_done_reg <= {conv_done_reg[3:0], conv_done};
    end

    // FSM
    localparam IDLE = 3'b001;
    localparam FLUSH = 3'b010;
    localparam CALC = 3'b100;

    reg [2:0] curr_state, next_state;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    always @(*) begin
        case (curr_state)
            IDLE: begin
                if (start_conv) next_state = FLUSH;
                else next_state = IDLE;
            end
            FLUSH: begin
                next_state = CALC;
            end
            CALC: begin
                if (conv_done) next_state = IDLE;
                else if (ic_done) next_state = FLUSH;
                else next_state = CALC;
            end
            default: next_state = IDLE;
        endcase
    end

    reg ifm_rd_col_msk_pre;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) ifm_rd_col_msk_pre <= 1'b1;
        else if (ifm_rd_col_msk_pre)
            ifm_rd_col_msk_pre <= (pc_col_max==(TILE_LEN-1)) | ~((pc_col == (pc_col_max - 1) & cnt_valid));
        else ifm_rd_col_msk_pre <= ic_done;
    end

    wire ifm_rd_col_msk;
    assign ifm_rd_col_msk = tile_col_last ? ifm_rd_col_msk_pre | ic_done : ifm_rd_col_msk_pre;

    assign ifm_read = (|curr_state[2:1]) & (~ic_done) & ifm_rd_col_msk;
    assign wgt_read = curr_state[1];

    assign cnt_valid = curr_state[2];

    // PE data valid signal for different stride(1/2)
    reg pvalid_s1;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) pvalid_s1 <= 'b0;
        else pvalid_s1 <= cnt_valid;
    end

    reg pvalid_s2_reg;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pvalid_s2_reg <= 'b0;
        end else if (cnt_valid) begin
            pvalid_s2_reg <= ~pvalid_s2_reg;
        end
    end

    wire pvalid_s2, pvalid_unmsk;
    assign pvalid_s2 = pvalid_s1 & pvalid_s2_reg;
    assign pvalid_unmsk = stride ? pvalid_s2 : pvalid_s1;

    reg pvld_col_msk_pre;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) pvld_col_msk_pre <= 1'b1;
        else if (pvld_col_msk_pre)
            pvld_col_msk_pre <= (pc_col_max==(TILE_LEN-1)) | ~((pc_col == pc_col_max) & cnt_valid);
        else pvld_col_msk_pre <= ic_done;
    end

    reg pvld_col_msk;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) pvld_col_msk <= 1'b1;
        else pvld_col_msk <= pvld_col_msk_pre;
    end

    wire pvalid_single;
    assign pvalid_single = pvalid_unmsk & pvld_col_msk;

    reg pvld_row_msk_vld;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) pvld_row_msk_vld <= 'b0;
        else pvld_row_msk_vld <= tile_row_last & (|tile_row_offset);
    end

    wire [COL-1:0] pvld_row_msk;
    assign pvld_row_msk = pvld_row_msk_vld ? ({COL{1'b1}} >> (COL - tile_row_offset)) : {COL{1'b1}};
    assign pvalid = {COL{pvalid_single}} & pvld_row_msk;

    assign ic_done = pc_col_last & cnt_valid;
    assign oc_done = ic_last & ic_done;
    assign tile_done = oc_last & oc_done;
    assign tile_ver_done = tile_col_last & tile_done;
    assign conv_done = tile_row_last & tile_ver_done;

endmodule
