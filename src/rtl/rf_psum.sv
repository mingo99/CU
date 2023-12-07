module rf_psum #(
    parameter DWIDTH = 32,
    parameter AWIDTH = 4,
    parameter PE_DWIDTH = 16
) (
    input wire clk,
    input wire rstn,
    input wire ic_done,
    input wire oc_done,

    input wire                        data_valid,
    input wire signed [PE_DWIDTH-1:0] pe_data,

    output wire                     result_valid,
    output wire signed [DWIDTH-1:0] result
);

    wire ping_full, ping_empty, ping_wren, ping_rden;
    wire pong_full, pong_empty, pong_wren, pong_rden;
    wire [DWIDTH-1:0] psum_out, ping_dout, pong_dout;

    reg psum_out_valid;
    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            psum_out_valid <= 1'b0;
        end else begin
            psum_out_valid <= data_valid;
        end
    end

    reg [1:0] oc_done_reg, ic_done_reg;
    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            ic_done_reg <= 'b0;
            oc_done_reg <= 'b0;
        end else begin
            ic_done_reg <= {ic_done_reg[0], ic_done};
            oc_done_reg <= {oc_done_reg[0], oc_done};
        end
    end

    wire psum_in_valid, switch_en;
    assign psum_in_valid = ic_done_reg[1];
    assign switch_en = oc_done_reg[1];

    reg fifo_sel;
    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            fifo_sel <= 1'b0;
        end else if (switch_en) begin
            fifo_sel <= ~fifo_sel;
        end
    end

    // psum_state->0:invalid psum; 1:valid psum
    // sum_state ->0:invalid sum;  1:valid sum
    reg ping_psum_state, ping_sum_state;
    reg pong_psum_state, pong_sum_state;
    wire ping_psum_state_nxt, ping_sum_state_nxt;
    wire pong_psum_state_nxt, pong_sum_state_nxt;

    assign ping_psum_state_nxt = ping_psum_state ? ~switch_en : psum_in_valid & ~fifo_sel;
    assign pong_psum_state_nxt = pong_psum_state ? ~switch_en : psum_in_valid & fifo_sel;
    assign ping_sum_state_nxt  = ping_sum_state ? ~ping_empty : switch_en & ~fifo_sel;
    assign pong_sum_state_nxt  = pong_sum_state ? ~pong_empty : switch_en & fifo_sel;

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            ping_psum_state <= 1'b0;
            pong_psum_state <= 1'b0;
            ping_sum_state  <= 1'b0;
            pong_sum_state  <= 1'b0;
        end else begin
            ping_psum_state <= ping_psum_state_nxt;
            pong_psum_state <= pong_psum_state_nxt;
            ping_sum_state  <= ping_sum_state_nxt;
            pong_sum_state  <= pong_sum_state_nxt;
        end
    end

    wire [DWIDTH-1:0] psum_in;
    assign psum_in = fifo_sel&pong_psum_state ? pong_dout : (
                ~fifo_sel&ping_psum_state ? ping_dout : 'b0);

    assign ping_wren = ~(ping_full | fifo_sel) & psum_out_valid;
    assign pong_wren = ~pong_full & fifo_sel & psum_out_valid;

    assign ping_rden = ping_sum_state ? ~ping_empty : ~ping_empty & data_valid & ping_psum_state;
    assign pong_rden = pong_sum_state ? ~pong_empty : ~pong_empty & data_valid & pong_psum_state;

    assign result_valid = (ping_sum_state & ping_rden) | (pong_sum_state & pong_rden);
    assign result = fifo_sel ? ping_dout : pong_dout;

    psum_add #(
        .DWIDTH(DWIDTH)
    ) u_psum_add (
        .clk     (clk),
        .rstn    (rstn),
        .pe_data (pe_data),
        .psum_in (psum_in),
        .psum_out(psum_out)
    );

    syncfifo #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) ping_fifo (
        .clk (clk),
        .rstn(rstn),

        .full(ping_full),
        .wren(ping_wren),
        .din (psum_out),

        .empty(ping_empty),
        .rden (ping_rden),
        .dout (ping_dout)
    );

    syncfifo #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) pong_fifo (
        .clk (clk),
        .rstn(rstn),

        .full(pong_full),
        .wren(pong_wren),
        .din (psum_out),

        .empty(pong_empty),
        .rden (pong_rden),
        .dout (pong_dout)
    );


endmodule

