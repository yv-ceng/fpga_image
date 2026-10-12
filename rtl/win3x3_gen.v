`timescale 1ns/1ps

module win3x3_gen #(
    parameter IMG_W = 128,  // 图像宽
    parameter IMG_H = 128,  // 图像高
    parameter PIX_W = 24  // 像素位宽
)(
    input                  clk,
    input                  rst_n,

    input                  din_de,
    input                  din_dv,
    input      [PIX_W-1:0] din_pix,
    input      [15:0]      din_x, din_y,

    output reg             dout_dv,
    output reg [PIX_W-1:0] p00, p01, p02,
    output reg [PIX_W-1:0] p10, p11, p12,
    output reg [PIX_W-1:0] p20, p21, p22,
    output reg [15:0]      dout_x, dout_y
);

    reg [PIX_W-1:0] lb0 [0:IMG_W-1];
    reg [PIX_W-1:0] lb1 [0:IMG_W-1];

    reg [PIX_W-1:0] b_r0, b_r1, b_r2;
    reg [PIX_W-1:0] m_r0, m_r1, m_r2;
    reg [PIX_W-1:0] t_r0, t_r1, t_r2;

    wire        wr_sel   = din_y[0];
    wire        mid_sel  = ~din_y[0];
    wire [15:0] rd_idx16 = (din_x >= IMG_W) ? (IMG_W-1) : din_x;
    wire [15:0] wr_idx16 = (din_x >= IMG_W) ? (IMG_W-1) : din_x;
    wire [PIX_W-1:0] lb0_rd = lb0[rd_idx16];
    wire [PIX_W-1:0] lb1_rd = lb1[rd_idx16];
    wire [PIX_W-1:0] mid_raw = mid_sel ? lb1_rd : lb0_rd;
    wire [PIX_W-1:0] top_raw = mid_sel ? lb0_rd : lb1_rd;

    wire col_pad = (din_x >= IMG_W);
    wire [PIX_W-1:0] mid_val = ((din_y >= 16'd1) && !col_pad) ? mid_raw : {PIX_W{1'b0}};
    wire [PIX_W-1:0] top_val = ((din_y >= 16'd2) && !col_pad) ? top_raw : {PIX_W{1'b0}};

    wire left_oob = (din_x <= 16'd1);
    wire [PIX_W-1:0] b_left = left_oob ? {PIX_W{1'b0}} : b_r1;
    wire [PIX_W-1:0] m_left = left_oob ? {PIX_W{1'b0}} : m_r1;
    wire [PIX_W-1:0] t_left = left_oob ? {PIX_W{1'b0}} : t_r1;

    always @(posedge clk) begin
        if (!rst_n) begin
            b_r0 <= {PIX_W{1'b0}}; b_r1 <= {PIX_W{1'b0}}; b_r2 <= {PIX_W{1'b0}};
            m_r0 <= {PIX_W{1'b0}}; m_r1 <= {PIX_W{1'b0}}; m_r2 <= {PIX_W{1'b0}};
            t_r0 <= {PIX_W{1'b0}}; t_r1 <= {PIX_W{1'b0}}; t_r2 <= {PIX_W{1'b0}};
            dout_dv <= 1'b0;
            dout_x  <= 16'd0;
            dout_y  <= 16'd0;
            p00 <= {PIX_W{1'b0}}; p01 <= {PIX_W{1'b0}}; p02 <= {PIX_W{1'b0}};
            p10 <= {PIX_W{1'b0}}; p11 <= {PIX_W{1'b0}}; p12 <= {PIX_W{1'b0}};
            p20 <= {PIX_W{1'b0}}; p21 <= {PIX_W{1'b0}}; p22 <= {PIX_W{1'b0}};
        end else begin

            dout_dv <= din_de && (din_x >= 16'd1) && (din_y >= 16'd1);

            if (din_de) begin

            b_r2 <= b_r1;  b_r1 <= b_r0;  b_r0 <= din_pix;
            m_r2 <= m_r1;  m_r1 <= m_r0;  m_r0 <= mid_val;
            t_r2 <= t_r1;  t_r1 <= t_r0;  t_r0 <= top_val;

            if (din_dv) begin
                if (wr_sel) lb1[wr_idx16] <= din_pix;
                else        lb0[wr_idx16] <= din_pix;
            end

            p00 <= t_left;  p01 <= t_r0;  p02 <= top_val;
            p10 <= m_left;  p11 <= m_r0;  p12 <= mid_val;
            p20 <= b_left;  p21 <= b_r0;  p22 <= din_pix;

            dout_x  <= din_x - 16'd1;
            dout_y  <= din_y - 16'd1;
            end
        end
    end

endmodule
