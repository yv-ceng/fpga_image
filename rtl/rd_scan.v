`timescale 1ns/1ps

module rd_scan #(
    parameter IMG_W  = 128,  // 图像宽
    parameter IMG_H  = 128,  // 图像高
    parameter ADDR_W = 14  // 地址位宽
)(
    input                   clk,
    input                   rst_n,
    input                   start,
    output reg              de,
    output reg              dv,
    output reg              rd_en,
    output reg [ADDR_W-1:0] rd_addr,
    output reg [15:0]       x,
    output reg [15:0]       y,
    output reg              frame_done
);

    reg        busy;
    reg [15:0] cx, cy;

    reg [15:0] ax, ay;
    reg        slot_d1;

    wire real_pix = busy && (cx < IMG_W) && (cy < IMG_H);

    always @(posedge clk) begin
        if (!rst_n) begin
            busy       <= 1'b0;
            cx         <= 16'd0;
            cy         <= 16'd0;
            rd_en      <= 1'b0;
            rd_addr    <= {ADDR_W{1'b0}};
            ax         <= 16'd0;
            ay         <= 16'd0;
            slot_d1    <= 1'b0;
            de         <= 1'b0;
            dv         <= 1'b0;
            x          <= 16'd0;
            y          <= 16'd0;
            frame_done <= 1'b0;
        end else begin

            frame_done <= 1'b0;

            rd_en   <= real_pix;
            rd_addr <= cy*IMG_W + cx;
            ax      <= cx;
            ay      <= cy;
            slot_d1 <= busy;

            de <= slot_d1;
            dv <= rd_en;
            x  <= ax;
            y  <= ay;

            frame_done <= slot_d1 & (ax == IMG_W) & (ay == IMG_H);

            if (busy) begin
                if (cx == IMG_W) begin
                    cx <= 16'd0;
                    if (cy == IMG_H) begin
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

endmodule
