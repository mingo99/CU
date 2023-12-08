///==------------------------------------------------------------------==///
/// Conv kernel: adder tree of psum module
///==------------------------------------------------------------------==///

module psum_add #(
    parameter DWIDTH = 32,
    parameter PE_DWIDTH = 16
) (
    input wire                        clk,
    input wire                        rstn,
    input wire signed [PE_DWIDTH-1:0] pe_data,
    input wire signed [   DWIDTH-1:0] psum_in,

    output reg signed [DWIDTH-1:0] psum_out
);

    // Adder tree
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            psum_out <= 0;
        end else begin
            psum_out <= psum_in + pe_data;
        end
    end
endmodule

