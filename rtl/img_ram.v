`timescale 1ns/1ps

module img_ram #(
    parameter PIX_W  = 24,  // 像素位宽
    parameter IMG_W  = 128,  // 图像宽
    parameter IMG_H  = 128,  // 图像高
    parameter DEPTH  = IMG_W*IMG_H,  // 存储深度（像素总数）
    parameter ADDR_W = 14,  // 地址位宽
    parameter INIT_FILE = ""  // 预载文件路径
)(
    input                       clk,

    input                       wr_en,
    input      [ADDR_W-1:0]     wr_addr,
    input      [PIX_W-1:0]      wr_data,

    input                       rd_en,
    input      [ADDR_W-1:0]     rd_addr,
    output reg [PIX_W-1:0]      rd_data
);

    reg [PIX_W-1:0] mem [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
            $display("[img_ram] 已从 %0s 预载图像", INIT_FILE);
        end
    end

    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        if (rd_en) rd_data       <= mem[rd_addr];
    end

endmodule
