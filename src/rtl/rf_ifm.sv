module rf_ifm #(
    parameter COL = 8
) (
    input                     clk,
    input                     rstn,
    input  signed [COL*8-1:0] ifm_in,
    input                     ifm_read,
    output signed [COL*8-1:0] ifm_buf
);

    reg signed [COL*8-1:0] ifm_buf_reg;
    assign ifm_bud = ifm_buf_reg;

    always @(posedge clk or negedge rstn)
        if (~rstn) begin
            ifm_buf_reg <= 0;
        end else if (ifm_read) begin
            ifm_buf_reg <= ifm_in;
        end else begin
            ifm_buf_reg <= ifm_buf_reg;

        end

    assign ifm_buf = ifm_buf_reg;

endmodule

