`timescale 1ns/1ps

module algo_gray #(
    parameter IMG_W = 128,  // 图像宽
    parameter IMG_H = 128  // 图像高
)(
    input               clk,
    input               rst_n,

    input               din_dv,
    input      [23:0]   din_pix,
    input      [15:0]   din_x,
    input      [15:0]   din_y,

    output reg          dout_dv,
    output reg [23:0]   dout_pix,
    output reg [15:0]   dout_x,
    output reg [15:0]   dout_y
);

    wire [15:0] r16 = {8'h00, din_pix[23:16]};
    wire [15:0] g16 = {8'h00, din_pix[15:8]};
    wire [15:0] b16 = {8'h00, din_pix[7:0]};

    wire [15:0] sum_y = ( (r16 << 6) + (r16 << 3) + (r16 << 2) + r16 )
                      + ( (g16 << 7) + (g16 << 4) + (g16 << 2) + (g16 << 1) )
                      + ( (b16 << 5) - (b16 << 1) - b16 );

    always @(posedge clk) begin
        if (!rst_n) begin
            dout_dv  <= 1'b0;
            dout_pix <= 24'd0;
            dout_x   <= 16'd0;
            dout_y   <= 16'd0;
        end else begin
            dout_dv  <= din_dv;
            dout_pix <= {sum_y[15:8], sum_y[15:8], sum_y[15:8]};
            dout_x   <= din_x;
            dout_y   <= din_y;
        end
    end

endmodule
