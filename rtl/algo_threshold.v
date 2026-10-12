`timescale 1ns/1ps

module algo_threshold #(
    parameter IMG_W = 128,  // 图像宽
    parameter IMG_H = 128,  // 图像高

    parameter R_LO = 230, parameter R_HI = 255,  // R 下限/R 上限
    parameter G_LO = 230, parameter G_HI = 255,  // G 下限/G 上限
    parameter B_LO = 230, parameter B_HI = 255  // B 下限/B 上限
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

    wire [7:0] r8 = din_pix[23:16];
    wire [7:0] g8 = din_pix[15:8];
    wire [7:0] b8 = din_pix[7:0];
    wire hit = (r8 >= R_LO) && (r8 <= R_HI) &&
               (g8 >= G_LO) && (g8 <= G_HI) &&
               (b8 >= B_LO) && (b8 <= B_HI);

    reg        found;
    reg [15:0] min_x, max_x, min_y, max_y;
    reg [15:0] cnt;

    reg        end_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            dout_dv <= 1'b0;
            dout_pix <= 24'd0;
            dout_x  <= 16'd0;
            dout_y  <= 16'd0;
            found   <= 1'b0;
            min_x   <= 16'd0;  max_x <= 16'd0;
            min_y   <= 16'd0;  max_y <= 16'd0;
            cnt     <= 16'd0;
            end_d   <= 1'b0;
        end else begin

            dout_dv  <= din_dv;
            dout_pix <= hit ? 24'hFFFFFF : 24'h000000;
            dout_x   <= din_x;
            dout_y   <= din_y;

            if (din_dv) begin
                if (hit) begin
                    if (!found) begin

                        found <= 1'b1;
                        min_x <= din_x;  max_x <= din_x;
                        min_y <= din_y;  max_y <= din_y;
                        cnt   <= 16'd1;
                    end else begin
                        if (din_x < min_x) min_x <= din_x;
                        if (din_x > max_x) max_x <= din_x;
                        if (din_y < min_y) min_y <= din_y;
                        if (din_y > max_y) max_y <= din_y;
                        cnt <= cnt + 16'd1;
                    end
                end

                if ((din_x == IMG_W-1) && (din_y == IMG_H-1)) end_d <= 1'b1;
            end

            if (end_d) begin
                end_d <= 1'b0;
                if (found) begin
                    $display("[algo_threshold] 目标检测结果：包围盒 x=[%0d..%0d] y=[%0d..%0d]，宽=%0d 高=%0d，像素数=%0d",
                             min_x, max_x, min_y, max_y,
                             max_x - min_x + 16'd1, max_y - min_y + 16'd1, cnt);
                end else begin
                    $display("[algo_threshold] 目标检测结果：未检测到任何符合颜色区间的像素");
                end
            end
        end
    end

endmodule
