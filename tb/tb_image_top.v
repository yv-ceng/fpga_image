`timescale 1ns/1ps
// 文件名 : tb_image_top.v   
// 模块名 : tb_image_top

//宏配置区
//------------------------------------------------------------------------------
// 【选择运行模式】
//   CFG_SCRIPT_MODE : 从 data/image.mem 读图
//   CFG_GUI_MODE    : 图案pattern_gen.v

// ### MODE_BEGIN ###
`define CFG_SCRIPT_MODE
`define PATH_MODE_ABS
// `define CFG_GUI_MODE
// ### MODE_END ###

`ifdef CFG_GUI_MODE
  `define PATTERN_INTERNAL                        // 图案由pattern_gen.v 生成
  `define PATH_MODE_ABS                           // 用绝对路径
`endif

// ### ALGO_SELECT_BEGIN ###
// `define ALGO_MORPH_DILATE
// `define ALGO_MORPH_ERODE
// `define ALGO_GRAY
`define ALGO_PASS
// `define ALGO_SCALE_2X
// `define ALGO_SHARPEN
// `define ALGO_THRESHOLD

// ### ALGO_SELECT_END ###

//是否启用"仿真内参考模型自检"
`define REF_CHECK

// 文件路径
// ### OUT_NAME_BEGIN ###
`ifdef PATH_MODE_ABS
  `define IMG_MEM_PATH "E:/fpga_image/data/image.mem"
  `define BMP_PATH     "E:/fpga_image/out/out_pass.bmp"
  `define REF_BMP_PATH "E:/fpga_image/out/out_ref.bmp"
`else
  `define IMG_MEM_PATH "../../data/image.mem"
  `define BMP_PATH     "../../out/out_pass.bmp"
  `define REF_BMP_PATH "../../out/out_ref.bmp"
`endif
`define ALGO_TAG "PASS"

// ### OUT_NAME_END ###

module tb_image_top;
    localparam IMG_W  = 128;
    localparam IMG_H  = 128;
    localparam PIX_W  = 24;
    localparam DEPTH  = IMG_W*IMG_H;             // 输入总像素数 
    localparam ADDR_W = 14;

`ifdef ALGO_SCALE_2X
    localparam OUT_W = IMG_W*2;                  // 2 倍放大：
    localparam OUT_H = IMG_H*2;
`else
    localparam OUT_W = IMG_W;                    // 其余算法输出尺寸不变
    localparam OUT_H = IMG_H;
`endif
    localparam OUT_PIX = OUT_W*OUT_H;            // 输出总像素数

    reg clk = 1'b0;
    always #5 clk = ~clk;                        // 10ns 周期
    reg rst_n = 1'b0;                            // 复位

    //图像源
    reg [PIX_W-1:0] img_in [0:DEPTH-1];          // 从 image.mem 读进来的图像副本
    reg [8*260-1:0] mem_path;
    reg [8*260-1:0] bmp_path;

    //TB → img_ram 写端口
    reg              wr_en;
    reg [ADDR_W-1:0] wr_addr;
    reg [PIX_W-1:0]  wr_data;

    //img_ram 读端口
    wire              rd_en;
    wire [ADDR_W-1:0] rd_addr;
    wire [PIX_W-1:0]  rd_data;                   // ★比 rd_addr 晚 1 拍

    // 读扫描器输出
    wire             de_scan;
    wire             dv_scan;
    wire [15:0]      x_scan, y_scan;
    wire             frame_done;

    // 送进算法的像素
    wire [PIX_W-1:0] pix_scan = dv_scan ? rd_data : {PIX_W{1'b0}};

    //算法输出像素流
    wire             dv_algo;
    wire [PIX_W-1:0] pix_algo;
    wire [15:0]      x_algo, y_algo;

    // BMP 写出器状态
    wire             bmp_busy, bmp_done;
    wire             bmp_ref_busy, bmp_ref_done;

    // 内部图案生成器
    reg              gen_start;
    wire             gen_dv;
    wire [PIX_W-1:0] gen_pix;
    wire [15:0]      gen_x, gen_y;
    wire             gen_done;

    //统计、校验和、超时
    reg [31:0] cnt_scan, cnt_algo;
    reg [31:0] chk_gen, chk_rd, chk_out;
    reg [31:0] cyc;
    localparam [31:0] TIMEOUT = 400*DEPTH;       // 超时上限

    //流程变量
    reg              start_scan;
    reg [31:0]       i;
    reg [31:0]       k;
    integer          xcnt;

`ifdef REF_CHECK
    localparam PW = IMG_W + 2;                   // 补零图宽
    localparam PH = IMG_H + 2;                   // 补零图高

    reg [PIX_W-1:0] src_img  [0:DEPTH-1];        // 输入图副本
    reg [PIX_W-1:0] pad_img  [0:PW*PH-1];        // 四周补 0 的输入图
    reg [PIX_W-1:0] gold_img [0:OUT_PIX-1];      // 参考模型输出

    reg             gs_start;                    // 启动 golden 图输出
    reg             gs_run;
    reg             gs_dv;
    reg [PIX_W-1:0] gs_pix;
    reg [15:0]      gs_x, gs_y;
    reg [31:0]      gs_idx;

    reg [31:0]      cmp_cnt, cmp_bad;            // 比对像素数 / 不一致像素数
    reg [7:0]       cmp_maxerr;                  // 最大通道误差
    reg             cmp_first;                   // 是否已记录首个不一致位置
    reg [15:0]      cmp_fx, cmp_fy;
`endif

    initial begin //参数与模式打印
        if (!$value$plusargs("IMG_MEM=%s", mem_path)) mem_path = `IMG_MEM_PATH;
        if (!$value$plusargs("BMP_OUT=%s", bmp_path)) bmp_path = `BMP_PATH;

        $display("=========================================================");
`ifdef CFG_GUI_MODE
        $display("[TB] 运行模式    = GUI 模式");
`else
        $display("[TB] 运行模式    = 脚本模式");
`endif
        $display("[TB] 算法        = %s", `ALGO_TAG);
        $display("[TB] 输入尺寸    = %0d x %0d，输出尺寸 = %0d x %0d", IMG_W, IMG_H, OUT_W, OUT_H);
`ifdef PATTERN_INTERNAL
        $display("[TB] 图案来源    = RTL 内部生成");
`else
        $display("[TB] 图案来源    = image.mem 文件（%0s）", mem_path);
`endif
        $display("[TB] 输出 bmp    = %0s", bmp_path);
        $display("=========================================================");

        //段 4b：准备图像
`ifdef PATTERN_INTERNAL
        $display("[TB] 使用 RTL 内部图案生成器，跳过 image.mem 读取");
`else
        $readmemh(mem_path, img_in);
        xcnt = 0;
        for (k = 0; k < DEPTH; k = k + 1) begin
            if (^img_in[k] === 1'bx) xcnt = xcnt + 1;
        end
        if (xcnt != 0) begin
            $display("[TB] 错误：image.mem 里有 %0d 个像素是 X，文件行数不足 %0d 行！", xcnt, DEPTH);
            $display("[TB] 请三选一：1) 改宏 CFG_GUI_MODE（图案内部生成，不需要文件）");
            $display("[TB]           2) 再加一行 PATH_MODE_ABS（改用绝对路径）");
            $display("[TB]           3) 生成文件：python scripts/img2mem.py ... 或 Tcl 里 source scripts/make_mem.tcl");
            $finish;
        end
        $display("[TB] image.mem 读取完成：共 %0d 个像素，无 X", DEPTH);
`endif

        //======== 段 4c：复位与初始化 ========
`ifndef PATTERN_INTERNAL
        wr_en      = 1'b0;
        wr_addr    = {ADDR_W{1'b0}};
        wr_data    = {PIX_W{1'b0}};
`endif
        start_scan = 1'b0;
        gen_start  = 1'b0;
        rst_n      = 1'b0;
        repeat (10) @(posedge clk);
        rst_n      = 1'b1;
        repeat (5)  @(posedge clk);

        //======== 段 4d：把图像写进帧缓存 ========
`ifdef PATTERN_INTERNAL
        $display("[TB] 启动内部图案生成器，边生成边写入帧缓存...");
        @(posedge clk);
        gen_start = 1'b1;
        @(posedge clk);
        gen_start = 1'b0;
        wait (gen_done === 1'b1);
        repeat (5) @(posedge clk);
`else
        $display("[TB] 开始把图像写入帧缓存...");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            wr_en   = 1'b1;
            wr_addr = i[ADDR_W-1:0];
            wr_data = img_in[i];
`ifdef REF_CHECK
            src_img[i[ADDR_W-1:0]] = img_in[i];   // 同步留一份源图给参考模型
`endif
        end
        @(posedge clk);
        wr_en   = 1'b0;
        wr_addr = {ADDR_W{1'b0}};
        wr_data = {PIX_W{1'b0}};
        repeat (5) @(posedge clk);
`endif
`ifdef REF_CHECK
        //======== 段 4d-2：算参考模型 + 准备 golden 图 ========
        // 作用：这一步是纯 Verilog 的"软件式"全帧计算（数组 + for 循环 + 任意寻址），
        //       与 RTL 的流式实现互为独立实现，两者结果必须逐像素相同。
        $display("[TB] 计算参考模型（行为级全帧实现，仅仿真）...");
        build_reference;
        @(posedge clk);
        gs_start = 1'b1;
        @(posedge clk);
        gs_start = 1'b0;
`endif
        $display("[TB] 帧缓存写入完成，准备启动处理");

        //======== 段 4e：启动（rd_scan 或 algo_scale 都接这个 start）========
        @(posedge clk);
        start_scan = 1'b1;
        @(posedge clk);
        start_scan = 1'b0;

        //======== 段 4f：等待 BMP 写完 ========
        $display("[TB] 等待 BMP 写出...");
        wait (bmp_done === 1'b1);
`ifdef REF_CHECK
        wait (bmp_ref_done === 1'b1);   // 等参考模型图也写完
`endif
        repeat (20) @(posedge clk);

        //======== 段 4g：打印汇总与自检结果 ========
        $display("=========================================================");
        $display("[TB] ===== 仿真结果汇总 =====");
        $display("[TB] 算法          = %s", `ALGO_TAG);
        $display("[TB] 输入/输出尺寸 = %0d x %0d  ->  %0d x %0d", IMG_W, IMG_H, OUT_W, OUT_H);
`ifdef ALGO_SCALE_2X
        $display("[TB] 说明          = 缩放算法自己驱动帧缓存读口，没有走 rd_scan");
`else
        if (cnt_scan == DEPTH)
            $display("[TB] 扫描输出像素  = %0d / %0d  OK", cnt_scan, DEPTH);
        else
            $display("[TB] 扫描输出像素  = %0d / %0d  **异常**", cnt_scan, DEPTH);
`endif
        if (cnt_algo == OUT_PIX)
            $display("[TB] 算法输出像素  = %0d / %0d  OK", cnt_algo, OUT_PIX);
        else
            $display("[TB] 算法输出像素  = %0d / %0d  **异常**（可能少了像素或坐标越界）", cnt_algo, OUT_PIX);
`ifdef PATTERN_INTERNAL
        $display("[TB] 校验和 写入RAM = 0x%08X", chk_gen);
`endif
`ifndef ALGO_SCALE_2X
        $display("[TB] 校验和 RAM读出 = 0x%08X", chk_rd);
`endif
        $display("[TB] 校验和 送写出 = 0x%08X", chk_out);
`ifndef ALGO_SCALE_2X
`ifdef ALGO_PASS
        // 直通算法不改动像素，所以"RAM 读出"与"送写出"必须完全一致
        if (chk_rd == chk_out)
            $display("[TB] 校验和比较    = RAM 读出 == 送写出   OK");
        else
            $display("[TB] 校验和比较    = **不一致**，算法层或对齐有问题");
`else
        // ★非直通算法会改变像素值★，两个校验和本来就应当不同，不能拿来判错。
        // 内容正确性交给 [TB][REF] 参考模型自检（它才是真正的逐像素判据）。
        $display("[TB] 校验和说明    = 非直通算法改变了像素，两个校验和不同属正常");
`endif
`endif
`ifdef PATTERN_INTERNAL
`ifndef ALGO_SCALE_2X
        if (chk_gen == chk_rd)
            $display("[TB] 校验和比较    = 写入RAM == RAM读出   OK");
        else
            $display("[TB] 校验和比较    = **写入 != 读出**，帧缓存或地址有问题");
`endif
`endif
        $display("[TB] 总仿真周期数  = %0d", cyc);
        $display("[TB] 输出文件      = %0s", bmp_path);
`ifdef PATTERN_INTERNAL
        $display("[TB] 参考图文件    = %0s（内容 = 输入图案，仅用于 PASS 的 fc /b 比对）", `REF_BMP_PATH);
`endif
`ifdef REF_CHECK
        $display("=========================================================");
        $display("[TB][REF] 参考模型自检");
        $display("[TB][REF]   比对像素数   = %0d / %0d", cmp_cnt, OUT_PIX);
        $display("[TB][REF]   不一致像素   = %0d", cmp_bad);
        $display("[TB][REF]   最大通道误差 = %0d", cmp_maxerr);
        if ((cmp_cnt == OUT_PIX) && (cmp_bad == 32'd0))
            $display("[TB][REF]   判定 = PASS —— RTL 输出与参考模型逐像素完全一致");
        else begin
            $display("[TB][REF]   判定 = FAIL —— 首个不一致位置 (x=%0d, y=%0d)", cmp_fx, cmp_fy);
        end
        $display("[TB][REF]   golden 图：%0s", `REF_BMP_PATH);
        $display("[TB][REF]   字节级比对（cmd）：fc /b out\\out_ref.bmp <RTL 输出图>");
        $display("=========================================================");
`endif
        $display("[TB] 三种验收方式（任选）：");
        $display("[TB]   1) 看上面的 [TB][REF] 判定 —— 仿真内自检，最省事");
        $display("[TB]   2) 看图：RTL 输出 %0s 与参考图 out\\out_ref.bmp", bmp_path);
        $display("[TB]   3) cmd 里做字节比对：fc /b out\\out_ref.bmp <RTL 输出图>");
        $display("[TB]   4) 或 Vivado Tcl Console：source scripts/compare_bmp.tcl");
        $display("=========================================================");
        $finish;
    end

    // 段 5：像素计数器
    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_scan <= 32'd0;
            cnt_algo <= 32'd0;
        end else begin
            if (dv_scan) cnt_scan <= cnt_scan + 32'd1;
            if (dv_algo) cnt_algo <= cnt_algo + 32'd1;
        end
    end

    // 段 6：校验和（不依赖任何外部脚本的自检手段）
    always @(posedge clk) begin
        if (!rst_n) begin
            chk_rd  <= 32'd0;
            chk_out <= 32'd0;
        end else begin
            if (dv_scan) chk_rd  <= chk_rd  + rd_data;
            if (dv_algo) chk_out <= chk_out + pix_algo;
        end
    end

`ifdef PATTERN_INTERNAL
    always @(posedge clk) begin
        if (!rst_n) chk_gen <= 32'd0;
        else if (gen_dv) chk_gen <= chk_gen + gen_pix;
    end
`endif

    // 段 7：超时保护
    always @(posedge clk) begin
        if (!rst_n) begin
            cyc <= 32'd0;
        end else begin
            cyc <= cyc + 32'd1;
            if (cyc > TIMEOUT) begin
                $display("=========================================================");
                $display("[TB]  超时错误：已跑 %0d 拍仍未见 BMP 写完 ", cyc);
                $display("[TB] 常见原因：1) 算法输出像素数不足 %0d；2) 坐标越界被写出器丢弃；", OUT_PIX);
                $display("[TB]           3) 状态机卡死；4) 3x3 窗口模块没收到消隐时隙（de 恒为 0）。");
                $display("=========================================================");
                $finish;
            end
        end
    end

    // 段 8：被测链路例化

    // 段 8a：帧缓存
    img_ram #(
        .PIX_W  (PIX_W),
        .IMG_W  (IMG_W),
        .IMG_H  (IMG_H),
        .DEPTH  (DEPTH),
        .ADDR_W (ADDR_W),
        .INIT_FILE ("")
    ) u_img_ram (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .rd_en   (rd_en),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );


    // 段 8b：读扫描器
`ifndef ALGO_SCALE_2X
    rd_scan #(
        .IMG_W  (IMG_W),
        .IMG_H  (IMG_H),
        .ADDR_W (ADDR_W)
    ) u_rd_scan (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start_scan),
        .de         (de_scan),
        .dv         (dv_scan),
        .rd_en      (rd_en),
        .rd_addr    (rd_addr),
        .x          (x_scan),
        .y          (y_scan),
        .frame_done (frame_done)
    );
`else
    // 缩放模式下没有 rd_scan：算法自己驱动 RAM 读口。
    assign de_scan    = 1'b0;
    assign dv_scan    = 1'b0;
    assign x_scan     = 16'd0;
    assign y_scan     = 16'd0;
    assign frame_done = 1'b0;
`endif

    // 段 8c：算法模块
    `ifdef ALGO_PASS
        algo_pass #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_dv(dv_scan), .din_pix(rd_data), .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );

    `elsif ALGO_GRAY
        // 灰度化：Y = (77R+150G+29B)>>8，纯移位加法实现
        algo_gray #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_dv(dv_scan), .din_pix(rd_data), .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );

    `elsif ALGO_THRESHOLD
        // 颜色识别 + 目标检测：默认阈值抓"接近白色"的像素（测试图案里只有左上 8x8 白块）
        algo_threshold #(
            .IMG_W(IMG_W), .IMG_H(IMG_H),
            .R_LO(230), .R_HI(255),
            .G_LO(230), .G_HI(255),
            .B_LO(230), .B_HI(255)
        ) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_dv(dv_scan), .din_pix(rd_data), .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );

    `elsif ALGO_MORPH_DILATE
        // 3x3 膨胀：窗口内取最大
        algo_morph #(.IMG_W(IMG_W), .IMG_H(IMG_H), .MODE(1)) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_de(de_scan), .din_dv(dv_scan), .din_pix(pix_scan),
            .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );

    `elsif ALGO_MORPH_ERODE
        // 3x3 腐蚀：窗口内取最小（边界补 0，所以最外一圈会变黑，属正常）
        algo_morph #(.IMG_W(IMG_W), .IMG_H(IMG_H), .MODE(0)) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_de(de_scan), .din_dv(dv_scan), .din_pix(pix_scan),
            .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );

    `elsif ALGO_SHARPEN
        // 锐化：out = clamp(中心 + K*(中心 - 高斯模糊))，K=1
        algo_sharpen #(.IMG_W(IMG_W), .IMG_H(IMG_H), .K(1)) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_de(de_scan), .din_dv(dv_scan), .din_pix(pix_scan),
            .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );

    `elsif ALGO_SCALE_2X
        // 2 倍放大（最近邻）：输出 256x256，自
        algo_scale #(
            .IMG_W(IMG_W), .IMG_H(IMG_H), .PIX_W(PIX_W), .ADDR_W(ADDR_W),
            .OUT_W(OUT_W), .OUT_H(OUT_H), .MODE(0)
        ) u_algo (
            .clk(clk), .rst_n(rst_n),
            .start(start_scan),
            .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo),
            .done()
        );

    `else
        // 兜底：一个算法宏都没打开时按直通运行，保证工程永远能编译通过
        algo_pass #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_algo (
            .clk(clk), .rst_n(rst_n),
            .din_dv(dv_scan), .din_pix(rd_data), .din_x(x_scan), .din_y(y_scan),
            .dout_dv(dv_algo), .dout_pix(pix_algo), .dout_x(x_algo), .dout_y(y_algo)
        );
        initial $display("[TB] 提示：宏配置区未启用任何算法，当前按直通运行");
    `endif

    // 段 8d：内部图案生成器+ 写帧缓存
`ifdef PATTERN_INTERNAL
    pattern_gen #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H)
    ) u_pattern_gen (
        .clk   (clk),
        .rst_n (rst_n),
        .start (gen_start),
        .dv    (gen_dv),
        .pix   (gen_pix),
        .x     (gen_x),
        .y     (gen_y),
        .done  (gen_done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_en   <= 1'b0;
            wr_addr <= {ADDR_W{1'b0}};
            wr_data <= {PIX_W{1'b0}};
        end else begin
            wr_en   <= gen_dv;
            wr_addr <= gen_y*IMG_W + gen_x;
            wr_data <= gen_pix;
`ifdef REF_CHECK
            if (gen_dv) src_img[gen_y*IMG_W + gen_x] <= gen_pix;  // 同步留一份源图
`endif
        end
    end
`endif

    // 段 8e：BMP 写出器（主路：算法输出）
    bmp_writer #(
        .IMG_W     (OUT_W),
        .IMG_H     (OUT_H),
        .PIX_W     (PIX_W),
        .EXP_PIX   (OUT_PIX),
        .FILE_PATH (`BMP_PATH)
    ) u_bmp_writer (
        .clk     (clk),
        .rst_n   (rst_n),
        .din_dv  (dv_algo),
        .din_pix (pix_algo),
        .din_x   (x_algo),
        .din_y   (y_algo),
        .busy    (bmp_busy),
        .done    (bmp_done)
    );

    // 段 8f：BMP 写出器 写的是参考模型算出的 golden 图
`ifdef REF_CHECK
    // 参考图写出器
    bmp_writer #(
        .IMG_W     (OUT_W),
        .IMG_H     (OUT_H),
        .PIX_W     (PIX_W),
        .EXP_PIX   (OUT_PIX),
        .FILE_PATH (`REF_BMP_PATH)
    ) u_bmp_ref (
        .clk     (clk),
        .rst_n   (rst_n),
        .din_dv  (gs_dv),
        .din_pix (gs_pix),
        .din_x   (gs_x),
        .din_y   (gs_y),
        .busy    (bmp_ref_busy),
        .done    (bmp_ref_done)
    );
`elsif PATTERN_INTERNAL
    // 退回老行为
    bmp_writer #(
        .IMG_W     (IMG_W),
        .IMG_H     (IMG_H),
        .PIX_W     (PIX_W),
        .EXP_PIX   (DEPTH),
        .FILE_PATH (`REF_BMP_PATH)
    ) u_bmp_ref (
        .clk     (clk),
        .rst_n   (rst_n),
        .din_dv  (gen_dv),
        .din_pix (gen_pix),
        .din_x   (gen_x),
        .din_y   (gen_y),
        .busy    (bmp_ref_busy),
        .done    (bmp_ref_done)
    );
`else
    // 脚本模式且关掉了 REF_CHECK 没有参考路，把状态信号固定住
    assign bmp_ref_busy = 1'b0;
    assign bmp_ref_done = 1'b0;
`endif

    `ifdef DUMP_WAVE
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_image_top.clk,
                     tb_image_top.rst_n,
                     tb_image_top.wr_en,
                     tb_image_top.wr_addr,
                     tb_image_top.wr_data,
                     tb_image_top.de_scan,
                     tb_image_top.dv_scan,
                     tb_image_top.rd_addr,
                     tb_image_top.rd_data,
                     tb_image_top.x_scan,
                     tb_image_top.y_scan,
                     tb_image_top.dv_algo,
                     tb_image_top.pix_algo,
                     tb_image_top.bmp_done);
    end
    `endif


`ifdef REF_CHECK

    // ---- 小工具函数（组合逻辑，只读入参）----
    function [7:0] abs8;                          // 两个字节差的绝对值
        input [7:0] a, b;
        begin abs8 = (a > b) ? (a - b) : (b - a); end
    endfunction

    function [7:0] max3;                          // 三个字节取最大
        input [7:0] a, b, c;
        begin max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c); end
    endfunction

    function [7:0] chan;                          // 取某个通道：0=R 1=G 2=B
        input [PIX_W-1:0] p;
        input integer c;
        begin chan = (c == 0) ? p[23:16] : ((c == 1) ? p[15:8] : p[7:0]); end
    endfunction

    function [7:0] clamp8;                        // 饱和到 0..255（不是截断）
        input signed [16:0] v;
        begin
            if (v < 0)             clamp8 = 8'd0;
            else if (v > 17'sd255) clamp8 = 8'd255;
            else                   clamp8 = v[7:0];
        end
    endfunction

    //参考模型本体
    task build_reference;
        integer ix, iy, wx, wy, ch;
        reg [7:0] r, g, b, yv;
        reg [7:0] ar, ag, ab;                    // 归约累加器
        reg [7:0] w9 [0:8];                      // 3x3 邻域暂存
        reg [7:0] ch3 [0:2];                     // 三个通道结果
        reg [15:0] s0, s1, s2, bl;
        reg [7:0]  cen;
        reg signed [16:0] sv;
        reg [PIX_W-1:0] p;
        begin
            // ---- ① 造"四周补 0"的输入图 ----
            for (iy = 0; iy < PH; iy = iy + 1) begin
                for (ix = 0; ix < PW; ix = ix + 1) begin
                    if ((ix == 0) || (iy == 0) || (ix == PW-1) || (iy == PH-1))
                        pad_img[iy*PW + ix] = {PIX_W{1'b0}};
                    else
                        pad_img[iy*PW + ix] = src_img[(iy-1)*IMG_W + (ix-1)];
                end
            end

`ifdef ALGO_SCALE_2X
            // 最近邻 2 倍放大：一个源像素铺 2x2（与 RTL 的 ox>>1 / oy>>1 等价）
            for (iy = 0; iy < OUT_H; iy = iy + 1)
                for (ix = 0; ix < OUT_W; ix = ix + 1)
                    gold_img[iy*OUT_W + ix] = src_img[(iy>>1)*IMG_W + (ix>>1)];

`elsif ALGO_MORPH_DILATE
            // 3x3 膨胀：窗口内每通道取最大；越界由补零图天然给出 0
            for (iy = 0; iy < IMG_H; iy = iy + 1) begin
                for (ix = 0; ix < IMG_W; ix = ix + 1) begin
                    ar = 8'd0; ag = 8'd0; ab = 8'd0;
                    for (wy = -1; wy <= 1; wy = wy + 1) begin
                        for (wx = -1; wx <= 1; wx = wx + 1) begin
                            p = pad_img[(iy+1+wy)*PW + (ix+1+wx)];
                            if (p[23:16] > ar) ar = p[23:16];
                            if (p[15:8]  > ag) ag = p[15:8];
                            if (p[7:0]   > ab) ab = p[7:0];
                        end
                    end
                    gold_img[iy*IMG_W + ix] = {ar, ag, ab};
                end
            end

`elsif ALGO_MORPH_ERODE
            // 3x3 腐蚀：窗口内每通道取最小（初值给 255，然后不断取小）
            for (iy = 0; iy < IMG_H; iy = iy + 1) begin
                for (ix = 0; ix < IMG_W; ix = ix + 1) begin
                    ar = 8'd255; ag = 8'd255; ab = 8'd255;
                    for (wy = -1; wy <= 1; wy = wy + 1) begin
                        for (wx = -1; wx <= 1; wx = wx + 1) begin
                            p = pad_img[(iy+1+wy)*PW + (ix+1+wx)];
                            if (p[23:16] < ar) ar = p[23:16];
                            if (p[15:8]  < ag) ag = p[15:8];
                            if (p[7:0]   < ab) ab = p[7:0];
                        end
                    end
                    gold_img[iy*IMG_W + ix] = {ar, ag, ab};
                end
            end

`elsif ALGO_SHARPEN
            // 锐化：out = clamp(2*中心 - 高斯模糊)，模糊核 (1,2,1;2,4,2;1,2,1)/16
            for (iy = 0; iy < IMG_H; iy = iy + 1) begin
                for (ix = 0; ix < IMG_W; ix = ix + 1) begin
                    for (ch = 0; ch < 3; ch = ch + 1) begin
                        for (wy = -1; wy <= 1; wy = wy + 1)
                            for (wx = -1; wx <= 1; wx = wx + 1)
                                w9[(wy+1)*3 + (wx+1)] =
                                    chan(pad_img[(iy+1+wy)*PW + (ix+1+wx)], ch);
                        s0  = w9[0] + (w9[1] << 1) + w9[2];      // 行内加权 a+2b+c
                        s1  = w9[3] + (w9[4] << 1) + w9[5];
                        s2  = w9[6] + (w9[7] << 1) + w9[8];
                        bl  = (s0 + (s1 << 1) + s2) >> 4;        // 三行 1:2:1 后 ÷16
                        cen = w9[4];
                        sv  = $signed({1'b0, cen}) + ($signed({1'b0, cen}) - $signed({1'b0, bl[7:0]}));
                        ch3[ch] = clamp8(sv);
                    end
                    gold_img[iy*IMG_W + ix] = {ch3[0], ch3[1], ch3[2]};
                end
            end

`elsif ALGO_GRAY
            // 灰度：Y=(77R+150G+29B)>>8，且 R=G=B=Y（真灰度图）
            for (iy = 0; iy < IMG_H; iy = iy + 1) begin
                for (ix = 0; ix < IMG_W; ix = ix + 1) begin
                    r = src_img[iy*IMG_W + ix][23:16];
                    g = src_img[iy*IMG_W + ix][15:8];
                    b = src_img[iy*IMG_W + ix][7:0];
                    yv = (77*r + 150*g + 29*b) >> 8;
                    gold_img[iy*IMG_W + ix] = {yv, yv, yv};
                end
            end

`elsif ALGO_THRESHOLD
            // 颜色识别：命中颜色区间输出白，否则黑（区间参数与例化处保持一致）
            for (iy = 0; iy < IMG_H; iy = iy + 1) begin
                for (ix = 0; ix < IMG_W; ix = ix + 1) begin
                    r = src_img[iy*IMG_W + ix][23:16];
                    g = src_img[iy*IMG_W + ix][15:8];
                    b = src_img[iy*IMG_W + ix][7:0];
                    if ((r >= 8'd230) && (g >= 8'd230) && (b >= 8'd230))
                        gold_img[iy*IMG_W + ix] = 24'hFFFFFF;
                    else
                        gold_img[iy*IMG_W + ix] = 24'h000000;
                end
            end

`else
            // 直通（以及任何未识别的情况）：参考输出 = 输入
            for (ix = 0; ix < DEPTH; ix = ix + 1) gold_img[ix] = src_img[ix];
`endif
        end
    endtask

    // 逐像素比对
    wire cmp_in_range = (x_algo < OUT_W) && (y_algo < OUT_H);
    wire [PIX_W-1:0] cmp_ref = cmp_in_range ? gold_img[y_algo*OUT_W + x_algo]
                                            : {PIX_W{1'b0}};
    wire [7:0] cmp_err_now = max3(abs8(pix_algo[23:16], cmp_ref[23:16]),
                                  abs8(pix_algo[15:8],  cmp_ref[15:8]),
                                  abs8(pix_algo[7:0],   cmp_ref[7:0]));
    wire cmp_bad_now = (!cmp_in_range) || (cmp_err_now != 8'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            cmp_cnt     <= 32'd0;
            cmp_bad     <= 32'd0;
            cmp_maxerr  <= 8'd0;
            cmp_first   <= 1'b0;
            cmp_fx      <= 16'd0;
            cmp_fy      <= 16'd0;
        end else if (dv_algo) begin
            cmp_cnt <= cmp_cnt + 32'd1;
            if (cmp_bad_now) begin
                cmp_bad <= cmp_bad + 32'd1;
                if (!cmp_first) begin
                    cmp_first <= 1'b1;
                    cmp_fx    <= x_algo;
                    cmp_fy    <= y_algo;
                end
            end
            if (cmp_err_now > cmp_maxerr) cmp_maxerr <= cmp_err_now;
        end
    end

    // golden 图输出流
    always @(posedge clk) begin
        if (!rst_n) begin
            gs_run <= 1'b0;
            gs_dv  <= 1'b0;
            gs_idx <= 32'd0;
            gs_pix <= {PIX_W{1'b0}};
            gs_x   <= 16'd0;
            gs_y   <= 16'd0;
        end else begin
            gs_dv  <= gs_run;
            gs_pix <= (gs_idx < OUT_PIX) ? gold_img[gs_idx] : {PIX_W{1'b0}};
            gs_x   <= gs_idx % OUT_W;
            gs_y   <= gs_idx / OUT_W;
            if (gs_run) begin
                gs_idx <= gs_idx + 32'd1;
                if (gs_idx == OUT_PIX-1) gs_run <= 1'b0;
            end else if (gs_start) begin
                gs_run <= 1'b1;
                gs_idx <= 32'd0;
            end
        end
    end

`endif

endmodule
