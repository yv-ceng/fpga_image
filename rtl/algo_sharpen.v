`timescale 1ns/1ps

module algo_sharpen #(
    parameter IMG_W = 128,  // 图像宽
    parameter IMG_H = 128,  // 图像高
    parameter PIX_W = 24,  // 像素位宽
    parameter K     = 1  // 锐化强度
)(
    input                  clk,
    input                  rst_n,

    input                  din_de,
    input                  din_dv,
    input      [PIX_W-1:0] din_pix,
    input      [15:0]      din_x, din_y,

    output reg             dout_dv,
    output reg [PIX_W-1:0] dout_pix,
    output reg [15:0]      dout_x, dout_y
);

    wire             w_dv;
    wire [PIX_W-1:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    wire [15:0]      w_x, w_y;

    win3x3_gen #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .PIX_W (PIX_W)
    ) u_win (
        .clk     (clk),
        .rst_n   (rst_n),
        .din_de  (din_de),
        .din_dv  (din_dv),
        .din_pix (din_pix),
        .din_x   (din_x),
        .din_y   (din_y),
        .dout_dv (w_dv),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .dout_x  (w_x),
        .dout_y  (w_y)
    );

    function [15:0] blur_ch;
        input [7:0] a0, b0, c0;
        input [7:0] a1, b1, c1;
        input [7:0] a2, b2, c2;
        reg   [15:0] r0, r1, r2;
        begin
            r0 = a0 + (b0 << 1) + c0;
            r1 = a1 + (b1 << 1) + c1;
            r2 = a2 + (b2 << 1) + c2;
            blur_ch = (r0 + (r1 << 1) + r2) >> 4;
        end
    endfunction

    wire [15:0] blur_r = blur_ch(p00[23:16],p01[23:16],p02[23:16],
                                 p10[23:16],p11[23:16],p12[23:16],
                                 p20[23:16],p21[23:16],p22[23:16]);
    wire [15:0] blur_g = blur_ch(p00[15:8], p01[15:8], p02[15:8],
                                 p10[15:8], p11[15:8], p12[15:8],
                                 p20[15:8], p21[15:8], p22[15:8]);
    wire [15:0] blur_b = blur_ch(p00[7:0],  p01[7:0],  p02[7:0],
                                 p10[7:0],  p11[7:0],  p12[7:0],
                                 p20[7:0],  p21[7:0],  p22[7:0]);

    wire signed [16:0] cen_r = $signed({1'b0, p11[23:16]});
    wire signed [16:0] cen_g = $signed({1'b0, p11[15:8]});
    wire signed [16:0] cen_b = $signed({1'b0, p11[7:0]});
    wire signed [16:0] dif_r = cen_r - $signed({1'b0, blur_r});
    wire signed [16:0] dif_g = cen_g - $signed({1'b0, blur_g});
    wire signed [16:0] dif_b = cen_b - $signed({1'b0, blur_b});
    wire signed [16:0] out_r = cen_r + (K * dif_r);
    wire signed [16:0] out_g = cen_g + (K * dif_g);
    wire signed [16:0] out_b = cen_b + (K * dif_b);

    function [7:0] clamp8s;
        input signed [16:0] v;
        begin
            if (v < 0)                clamp8s = 8'd0;
            else if (v > 17'sd255)    clamp8s = 8'd255;
            else                      clamp8s = v[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            dout_dv  <= 1'b0;
            dout_pix <= {PIX_W{1'b0}};
            dout_x   <= 16'd0;
            dout_y   <= 16'd0;
        end else begin
            dout_dv  <= w_dv;
            dout_pix <= {clamp8s(out_r), clamp8s(out_g), clamp8s(out_b)};
            dout_x   <= w_x;
            dout_y   <= w_y;
        end
    end

endmodule
