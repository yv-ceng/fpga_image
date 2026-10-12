`timescale 1ns/1ps

module algo_pass #(
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

    always @(posedge clk) begin
        if (!rst_n) begin
            dout_dv  <= 1'b0;
            dout_pix <= 24'd0;
            dout_x   <= 16'd0;
            dout_y   <= 16'd0;
        end else begin
            dout_dv  <= din_dv;
            dout_pix <= din_pix;
            dout_x   <= din_x;
            dout_y   <= din_y;
        end
    end

endmodule
