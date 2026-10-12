`timescale 1ns/1ps

module pattern_gen #(
    parameter IMG_W = 128,  // 图像宽
    parameter IMG_H = 128  // 图像高
)(
    input               clk,
    input               rst_n,
    input               start,
    output reg          dv,
    output reg [23:0]   pix,
    output reg [15:0]   x,
    output reg [15:0]   y,
    output reg          done
);

    reg        busy;
    reg [15:0] cx, cy;

    function [7:0] grad2;
        input [15:0] v;
        begin
            grad2 = (v >= 16'd128) ? 8'd255 : {v[6:0], 1'b0};
        end
    endfunction

    reg [7:0] r, g, b;

    always @(*) begin

        if ((cx < IMG_W/2) && (cy < IMG_H/2)) begin
            r = 8'd200; g = 8'd32;  b = 8'd32;
        end else if ((cx >= IMG_W/2) && (cy < IMG_H/2)) begin
            r = 8'd32;  g = 8'd200; b = 8'd32;
        end else if (cx < IMG_W/2) begin
            r = 8'd32;  g = 8'd32;  b = 8'd200;
        end else begin
            r = 8'd210; g = 8'd210; b = 8'd210;
        end

        if ((((cx >> 3) + (cy >> 3)) & 16'd1) == 16'd0) begin
            r = (r * 3) >> 2;
            g = (g * 3) >> 2;
            b = (b * 3) >> 2;
        end

        if (cy < 16'd2) begin
            r = grad2(cx); g = 8'd0; b = 8'd0;
        end else if (cx < 16'd2) begin
            r = 8'd0; g = grad2(cy); b = 8'd0;
        end

        if ((cx >= 16'd4) && (cx <= 16'd11) && (cy >= 16'd4) && (cy <= 16'd11)) begin
            r = 8'd255; g = 8'd255; b = 8'd255;
        end

        if ((cx >= IMG_W-12) && (cx <= IMG_W-5) &&
            (cy >= IMG_H-12) && (cy <= IMG_H-5)) begin
            r = 8'd0; g = 8'd0; b = 8'd0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            cx   <= 16'd0;
            cy   <= 16'd0;
            dv   <= 1'b0;
            pix  <= 24'd0;
            x    <= 16'd0;
            y    <= 16'd0;
        end else begin
            dv  <= busy;
            pix <= {r, g, b};
            x   <= cx;
            y   <= cy;

            if (busy) begin
                if (cx == IMG_W-1) begin
                    cx <= 16'd0;
                    if (cy == IMG_H-1) begin
                        cy   <= 16'd0;
                        busy <= 1'b0;
                    end else begin
                        cy <= cy + 16'd1;
                    end
                end else begin
                    cx <= cx + 16'd1;
                end
            end else if (start) begin
                busy <= 1'b1;
                cx   <= 16'd0;
                cy   <= 16'd0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) done <= 1'b0;
        else        done <= busy & (cx == IMG_W-1) & (cy == IMG_H-1);
    end

endmodule
