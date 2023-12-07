// `include "typedef.svh"

module pe_1x1 #(
    parameter DWIDTH = 16
) (
    input wire clk,
    input wire rstn,

    input wire signed [7:0] ifm_in,
    input wire signed [7:0] wgt_in,

    output reg signed [DWIDTH-1:0] psum
);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            psum <= 0;
        end else begin
            psum <= ifm_in * wgt_in;
        end
    end

endmodule

