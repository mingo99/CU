module rf_wgt (
    input                   clk,
    input                   rstn,
    input  signed     [7:0] wgt_in,
    input                   wgt_read,
    output reg signed [7:0] wgt_buf
);

    always @(posedge clk or negedge rstn)
        if (~rstn) begin
            wgt_buf <= 0;
        end else if (wgt_read) begin
            wgt_buf <= wgt_in;
        end else begin
            wgt_buf <= wgt_buf;
        end

endmodule

