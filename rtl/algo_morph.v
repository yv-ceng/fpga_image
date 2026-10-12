`timescale 1ns/1ps

module algo_morph #(
    parameter IMG_W = 128,  // 图像宽
    parameter IMG_H = 128,  // 图像高
    parameter PIX_W = 24,  // 像素位宽
    parameter MODE  = 1  // 模式选择
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

    reg [7:0] wr [0:8];
    reg [7:0] wg [0:8];
    reg [7:0] wb [0:8];
    reg [7:0] rr, gg, bb;
    integer   i;

    always @(*) begin

        wr[0]=p00[23:16]; wr[1]=p01[23:16]; wr[2]=p02[23:16];
        wr[3]=p10[23:16]; wr[4]=p11[23:16]; wr[5]=p12[23:16];
        wr[6]=p20[23:16]; wr[7]=p21[23:16]; wr[8]=p22[23:16];
        wg[0]=p00[15:8];  wg[1]=p01[15:8];  wg[2]=p02[15:8];
        wg[3]=p10[15:8];  wg[4]=p11[15:8];  wg[5]=p12[15:8];
        wg[6]=p20[15:8];  wg[7]=p21[15:8];  wg[8]=p22[15:8];
        wb[0]=p00[7:0];   wb[1]=p01[7:0];   wb[2]=p02[7:0];
        wb[3]=p10[7:0];   wb[4]=p11[7:0];   wb[5]=p12[7:0];
        wb[6]=p20[7:0];   wb[7]=p21[7:0];   wb[8]=p22[7:0];

        rr = wr[0];  gg = wg[0];  bb = wb[0];
        for (i = 1; i < 9; i = i + 1) begin
            if (MODE != 0) begin
                if (wr[i] > rr) rr = wr[i];
                if (wg[i] > gg) gg = wg[i];
                if (wb[i] > bb) bb = wb[i];
            end else begin
                if (wr[i] < rr) rr = wr[i];
                if (wg[i] < gg) gg = wg[i];
                if (wb[i] < bb) bb = wb[i];
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            dout_dv  <= 1'b0;
            dout_pix <= {PIX_W{1'b0}};
            dout_x   <= 16'd0;
            dout_y   <= 16'd0;
        end else begin
            dout_dv  <= w_dv;
            dout_pix <= {rr, gg, bb};
            dout_x   <= w_x;
            dout_y   <= w_y;
        end
    end

endmodule
