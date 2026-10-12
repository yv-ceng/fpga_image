`timescale 1ns/1ps

module bmp_writer #(
    parameter IMG_W   = 128,  // 图像宽
    parameter IMG_H   = 128,  // 图像高
    parameter PIX_W   = 24,  // 像素位宽
    parameter EXP_PIX = IMG_W*IMG_H,  // 期望像素数
    parameter FILE_PATH = "out_pass.bmp"  // 输出文件名
)(
    input               clk,
    input               rst_n,

    input               din_dv,
    input      [PIX_W-1:0] din_pix,
    input      [15:0]   din_x,
    input      [15:0]   din_y,

    output reg          busy,
    output reg          done
);

    localparam [31:0] ROW_BYTES = ((IMG_W*3 + 3) / 4) * 4;  // 每行字节数
    localparam [31:0] PAD_BYTES = ROW_BYTES - IMG_W*3;  // 行尾补零字节数
    localparam [31:0] IMG_BYTES = ROW_BYTES * IMG_H;  // 像素数据字节数
    localparam [31:0] FILE_SIZE = 54 + IMG_BYTES;  // 文件总字节数

    localparam [31:0] W32 = IMG_W;  // 宽（32 位常量）
    localparam [31:0] H32 = IMG_H;  // 高（32 位常量）

    reg [PIX_W-1:0] frame [0:IMG_W*IMG_H-1];

    reg [7:0] hdr [0:53];
    initial begin

        hdr[ 0] = 8'h42;  hdr[ 1] = 8'h4D;

        hdr[ 2] = FILE_SIZE[7:0];   hdr[ 3] = FILE_SIZE[15:8];
        hdr[ 4] = FILE_SIZE[23:16]; hdr[ 5] = FILE_SIZE[31:24];

        hdr[ 6] = 8'h00;  hdr[ 7] = 8'h00;  hdr[ 8] = 8'h00;  hdr[ 9] = 8'h00;

        hdr[10] = 8'd54;  hdr[11] = 8'h00;  hdr[12] = 8'h00;  hdr[13] = 8'h00;

        hdr[14] = 8'd40;  hdr[15] = 8'h00;  hdr[16] = 8'h00;  hdr[17] = 8'h00;

        hdr[18] = W32[7:0];    hdr[19] = W32[15:8];
        hdr[20] = W32[23:16];  hdr[21] = W32[31:24];

        hdr[22] = H32[7:0];    hdr[23] = H32[15:8];
        hdr[24] = H32[23:16];  hdr[25] = H32[31:24];

        hdr[26] = 8'h01;  hdr[27] = 8'h00;

        hdr[28] = 8'd24;  hdr[29] = 8'h00;

        hdr[30] = 8'h00;  hdr[31] = 8'h00;  hdr[32] = 8'h00;  hdr[33] = 8'h00;

        hdr[34] = IMG_BYTES[7:0];    hdr[35] = IMG_BYTES[15:8];
        hdr[36] = IMG_BYTES[23:16];  hdr[37] = IMG_BYTES[31:24];

        hdr[38] = 8'h13;  hdr[39] = 8'h0B;  hdr[40] = 8'h00;  hdr[41] = 8'h00;
        hdr[42] = 8'h13;  hdr[43] = 8'h0B;  hdr[44] = 8'h00;  hdr[45] = 8'h00;

        hdr[46] = 8'h00;  hdr[47] = 8'h00;  hdr[48] = 8'h00;  hdr[49] = 8'h00;
        hdr[50] = 8'h00;  hdr[51] = 8'h00;  hdr[52] = 8'h00;  hdr[53] = 8'h00;
    end

    reg [8*260-1:0] bmp_path;
    initial begin
        if (!$value$plusargs("BMP_OUT=%s", bmp_path)) begin
            bmp_path = FILE_PATH;
        end
    end

    localparam S_FILL = 3'd0, S_HDR = 3'd1, S_PIX = 3'd2,  // 状态机编码
               S_PAD  = 3'd3, S_DONE = 3'd4, S_END = 3'd5;

    reg [2:0]      state;
    reg [31:0]     pix_cnt;
    reg [5:0]      hi;
    reg [15:0]     wy;
    reg [15:0]     wx;
    reg [1:0]      bsel;
    reg [1:0]      pad;
    integer        fd;
    reg [31:0]     wr_bytes;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_FILL;
            pix_cnt  <= 32'd0;
            hi       <= 6'd0;
            wy       <= 16'd0;
            wx       <= 16'd0;
            bsel     <= 2'd0;
            pad      <= 2'd0;
            busy     <= 1'b0;
            done     <= 1'b0;
            wr_bytes <= 32'd0;
        end else begin
            case (state)

            S_FILL: begin
                if (din_dv) begin
                    if ((din_x < IMG_W) && (din_y < IMG_H)) begin
                        frame[din_y*IMG_W + din_x] <= din_pix;
                        pix_cnt <= pix_cnt + 32'd1;
                        if (pix_cnt == EXP_PIX-1) begin
                            fd = $fopen(bmp_path, "wb");
                            if (fd == 0) begin
                                $display("[bmp_writer] 错误：无法创建文件 %0s", bmp_path);
                                $finish;
                            end
                            $display("[bmp_writer] 收满 %0d 个像素，开始写 %0s", EXP_PIX, bmp_path);
                            hi   <= 6'd0;
                            wy   <= IMG_H-1;
                            wx   <= 16'd0;
                            bsel <= 2'd0;
                            pad  <= 2'd0;
                            busy <= 1'b1;
                            state <= S_HDR;
                        end
                    end else begin
                        $display("[bmp_writer] 警告：像素坐标越界 (%0d,%0d)，已忽略", din_x, din_y);
                    end
                end
            end

            S_HDR: begin
                $fwrite(fd, "%c", hdr[hi]);
                wr_bytes <= wr_bytes + 32'd1;
                if (hi == 6'd53) begin
                    state <= S_PIX;
                end else begin
                    hi <= hi + 6'd1;
                end
            end

            S_PIX: begin
                case (bsel)
                    2'd0: $fwrite(fd, "%c", frame[wy*IMG_W + wx][7:0]);
                    2'd1: $fwrite(fd, "%c", frame[wy*IMG_W + wx][15:8]);
                    2'd2: $fwrite(fd, "%c", frame[wy*IMG_W + wx][23:16]);
                endcase
                wr_bytes <= wr_bytes + 32'd1;

                if (bsel == 2'd2) begin
                    bsel <= 2'd0;
                    if (wx == IMG_W-1) begin
                        wx <= 16'd0;
                        if (PAD_BYTES != 0) begin
                            pad   <= 2'd0;
                            state <= S_PAD;
                        end else if (wy == 0) begin
                            state <= S_DONE;
                        end else begin
                            wy <= wy - 16'd1;
                        end
                    end else begin
                        wx <= wx + 16'd1;
                    end
                end else begin
                    bsel <= bsel + 2'd1;
                end
            end

            S_PAD: begin
                $fwrite(fd, "%c", 8'h00);
                wr_bytes <= wr_bytes + 32'd1;
                if (pad == PAD_BYTES-1) begin
                    pad <= 2'd0;
                    if (wy == 0) begin
                        state <= S_DONE;
                    end else begin
                        wy    <= wy - 16'd1;
                        state <= S_PIX;
                    end
                end else begin
                    pad <= pad + 2'd1;
                end
            end

            S_DONE: begin
                $fclose(fd);
                busy <= 1'b0;
                done <= 1'b1;
                $display("[bmp_writer] BMP 写出完成：%0d 字节（期望 %0d），像素 %0d 个",
                         wr_bytes, FILE_SIZE, EXP_PIX);
                state <= S_END;
            end

            S_END: begin
                busy <= 1'b0;
                done <= 1'b1;
            end

            default: state <= S_FILL;
            endcase
        end
    end

endmodule
