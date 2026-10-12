`timescale 1ns/1ps

module algo_scale #(
    parameter IMG_W  = 128,  // 图像宽
    parameter IMG_H  = 128,  // 图像高
    parameter PIX_W  = 24,  // 像素位宽
    parameter ADDR_W = 14,  // 地址位宽
    parameter OUT_W  = 256,  // 输出宽
    parameter OUT_H  = 256,  // 输出高
    parameter MODE   = 0  // 模式选择
)(
    input                   clk,
    input                   rst_n,
    input                   start,

    output reg              rd_en,
    output reg [ADDR_W-1:0] rd_addr,
    input      [PIX_W-1:0]  rd_data,

    output reg              dout_dv,
    output     [PIX_W-1:0]  dout_pix,
    output reg [15:0]       dout_x, dout_y,
    output reg              done
);

    reg        busy;
    reg [15:0] ox, oy;
    reg [15:0] ox_d, oy_d;

    wire [15:0] sx = MODE ? (ox << 1) : (ox >> 1);
    wire [15:0] sy = MODE ? (oy << 1) : (oy >> 1);

    always @(posedge clk) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            ox       <= 16'd0;
            oy       <= 16'd0;
            ox_d     <= 16'd0;
            oy_d     <= 16'd0;
            rd_en    <= 1'b0;
            rd_addr  <= {ADDR_W{1'b0}};
            dout_dv  <= 1'b0;
            dout_x   <= 16'd0;
            dout_y   <= 16'd0;
            done     <= 1'b0;
        end else begin

            rd_en   <= busy;
            rd_addr <= sy*IMG_W + sx;
            ox_d    <= ox;
            oy_d    <= oy;

            dout_dv  <= rd_en;
            dout_x   <= ox_d;
            dout_y   <= oy_d;

            done <= rd_en & (ox_d == OUT_W-1) & (oy_d == OUT_H-1);

            if (busy) begin
                if (ox == OUT_W-1) begin
                    ox <= 16'd0;
                    if (oy == OUT_H-1) begin
                        oy   <= 16'd0;
                        busy <= 1'b0;
                    end else begin
                        oy <= oy + 16'd1;
                    end
                end else begin
                    ox <= ox + 16'd1;
                end
            end else if (start) begin
                busy <= 1'b1;
                ox   <= 16'd0;
                oy   <= 16'd0;
            end
        end
    end

    assign dout_pix = rd_data;

endmodule
