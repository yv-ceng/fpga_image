# 基于图像处理的仿真验证平台 —— 方案汇报

> 技术栈：Verilog-2001 + Vivado 2018.3 自带仿真器 xsim（Tcl 8.5）
> 运行环境：**只需 Vivado 图形界面**，不需要 Python、不需要 PowerShell
> 代码规模：RTL 9 个文件 750 行、testbench 3 个文件 1099 行（Verilog 共 1849 行）+ Tcl 脚本 343 行

---

## 0. 摘要

本方案在 FPGA 上用 Verilog 实现了一条完整的图像处理链路：
**图像输入 → 片上帧缓存（RAM）→ 逐像素顺序读出 → 算法处理 → 输出 BMP 位图文件**，
并把"验证"也做进了仿真内部：testbench 自带测试图案发生器、自带参考模型、自带逐像素比对与
判定输出，因此**七种算法的正确性判定完全在 Vivado 仿真里闭环完成**，不依赖任何外部脚本工具。

配套的两个 Tcl 脚本分别负责"把图片转成仿真能读的数据文件"（`img2mem.tcl`）与"切换算法/数据源、
修正工程路径"（`set_algo.tcl`），它们都在 Vivado 的 Tcl Console 里运行，因此整条链路
**从图片准备、算法切换、仿真运行到结果判定，全程只用到 Vivado 一个软件**。

实测结果：**7 个算法 7/7 通过**；仿真内参考模型比对结果为 **不一致像素 0 个、最大通道误差 0**；
另外，与一个独立的 Python 定点模型做**可选的外部交叉复核**时，结果达到 **逐字节一致（PSNR 99.00 dB）**

---

## 1. 设计目标与规格

| 项目    | 规格                         | 说明                                                                               |
| ----- | -------------------------- | -------------------------------------------------------------------------------- |
| 图像分辨率 | 128 × 128                  | `IMG_W=128`、`IMG_H=128`                                                          |
| 像素格式  | RGB888（24 bit）             | `PIX_W=24`，每通道 8 bit                                                             |
| 帧缓存容量 | 16384 × 24 bit             | `DEPTH=IMG_W*IMG_H`，地址位宽 `ADDR_W=14`                                             |
| 处理吞吐  | 1 pixel / clk              | 100 MHz 时钟（周期 10 ns）                                                             |
| 算法选择  | 宏（compile-time）切换，7 选 1    | `ALGO_PASS / GRAY / THRESHOLD / MORPH_DILATE / MORPH_ERODE / SCALE_2X / SHARPEN` |
| 输出格式  | 24 位未压缩 BMP                | 54 字节头 + 自下而上 + 行 4 字节对齐                                                         |
| 验证方式  | **仿真内自参考**                 | testbench 内置参考模型 + 逐像素比对 + `[TB][REF]` 判定                                        |
| 外部依赖  | 无（零 Python / 零 PowerShell） | 图片转换、算法切换、结果判定都在 Vivado 内完成                                                      |

---

## 2. 文件组成与职责

```
fpga_image_platform/
├── rtl/                        ← 可综合的设计代码（9 个文件，750 行）
│   ├── img_ram.v               帧缓存（行为级双口 RAM 模型，同步读 1 拍延迟）
│   ├── rd_scan.v               消隐光栅扫描读出：产生 de/dv/x/y 与 RAM 读地址（★核心）
│   ├── win3x3_gen.v            3×3 邻域窗口生成（2 个行缓存 + 3 个移位寄存器）（★核心）
│   ├── algo_pass.v             算法①：直通（接口模板，1 拍寄存）
│   ├── algo_gray.v             算法②：灰度化 Y=(77R+150G+29B)>>8
│   ├── algo_threshold.v        算法③：颜色识别 + 目标包围盒统计
│   ├── algo_morph.v            算法④⑤：3×3 膨胀 / 腐蚀（MODE 参数切换）
│   ├── algo_sharpen.v          算法⑥：高斯模糊 + 锐化（有符号饱和）
│   └── algo_scale.v            算法⑦：最近邻 2 倍放大 / 0.5 倍缩小
├── tb/                         ← 仅用于仿真的验证代码（3 个文件，1099 行）
│   ├── tb_image_top.v          顶层 testbench：宏配置、三段式流程、参考模型自检（788 行）
│   ├── pattern_gen.v           内置测试图案发生器（象限+棋盘+渐变+标记）
│   └── bmp_writer.v            BMP 文件写出器（54 字节头 + 自下而上像素写入）
├── scripts/                    ← 只在 Vivado 的 Tcl Console 里运行的脚本（343 行）
│   ├── img2mem.tcl             24 位 BMP → data/image.mem（纯 Tcl）
│   └── set_algo.tcl            set_algo / set_src / set_paths（切算法、切数据源、修路径）
└── data/
    ├── image.mem               图片数据：16384 行，每行 6 位十六进制 RRGGBB
    └── in/*.bmp                源图（128×128、24 位未压缩 BMP）
```

---

## 3. 总体数据通路

```
   ┌───────────────── ① 装载阶段（把一帧图像写进片上 RAM）─────────────────┐
   │                                                                          │
   │  tb/pattern_gen.v ──(GUI 模式：RTL 边生成边写)──┐                        │
   │  data/image.mem ──$readmemh──(脚本模式：读文本)─┴──→  img_ram 写口       │
   │                                                        │                  │
   └────────────────────────────────────────────────────────┼─────────────┘
                                                            ▼
                                            ┌──── img_ram（帧缓存 16384×24bit）────┐
                                            │  写口：装载阶段写入                   │
                                            │  读口：处理阶段按地址读出（1 拍延迟） │
                                            └───────────────┬───────────────────┘
   ┌──────────────── ② 处理阶段（读出 → 算法）───────────────┼─────────────────────┐
   │                                                        │ rd_data                   │
   │   rd_scan（消隐光栅：16641 个时隙）──rd_en/rd_addr──────┘                         │
   │      │ de（时隙有效，含消隐） / dv（真实像素） / x / y                             │
   │      ▼                                                                             │
   │   ┌──────────── 7 选 1 算法层（由宏在编译期选择）────────────┐                   │
   │   │ 逐像素类：pass / gray / threshold                           │                  │
   │   │ 3×3 邻域类：dilate / erode / sharpen  ← win3x3_gen 提供窗口 │                  │
   │   │ 坐标变换类：scale2x  ← 自己驱动 img_ram 读口（不用 rd_scan） │                  │
   │   └───────────────────────────┬─────────────────────────────┘                 │
   └───────────────────────────────┼──────────────────────────────────────────────┘
                                   ▼ dout_dv / dout_pix / dout_x / dout_y
   ┌──────────────── ③ 写出阶段（BMP 落盘 + 自检判定）────────────────────────────┐
   │   tb/bmp_writer.v（主路）──→ out/out_<算法>.bmp                                  │
   │   参考模型 gold_img（TB 内）─→ out/out_ref.bmp（标准答案图）                     │
   │   流式比对（按坐标取参考像素）──→ [TB][REF] 判定 = PASS / FAIL                   │
   └───────────────────────────────────────────────────────────────────────────┘
```

三个阶段的衔接靠两个"状态信号"：装载完成 → 启动扫描；写出完成（`bmp_done`）→ 打印汇总与判定。
全流程没有 CPU 干预、没有总线握手，是一段确定性的硬件流水。

## 4. RTL 核心模块实现（帧缓存 / 扫描读出 / 3×3 窗口）

### 4.1 img_ram.v：帧缓存行为模型

**参数**：`PIX_W=24`（RGB888 打包像素）、`IMG_W=128`、`IMG_H=128`、`DEPTH=IMG_W*IMG_H`（16384）、
`ADDR_W=14`、`INIT_FILE=""`（可选的预载文件路径）。
**端口**：写侧 `wr_en / wr_addr / wr_data`（供 testbench 装载），读侧 `rd_en / rd_addr / rd_data`；

存储本体是一维数组，二维坐标按 `y*IMG_W + x` 压成一维地址：

```verilog
    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;        // 写：一个时钟沿写入一个像素
        if (rd_en) rd_data       <= mem[rd_addr];  // 读：数据比地址晚 1 拍有效
    end
```

**这条"读延迟 1 拍"是全链路时序设计的出发点**：凡是要与像素同拍的伴随信号（有效标志、坐标）
都必须镜像同样的延迟，否则下游会把像素与其坐标错配 —— 这正是 `rd_scan` 两级流水存在的原因。

### 4.2 rd_scan.v：消隐光栅扫描读出

**端口**：输入 `clk / rst_n / start`（单拍脉冲启动一帧）；输出 `de`（时隙有效，含消隐）、
`dv`（真实像素有效）、`rd_en / rd_addr`（驱动帧缓存读口）、`x / y`（坐标）、`frame_done`（帧末脉冲）。

**（1）两级流水把坐标、有效标志对齐到 RAM 的 1 拍读延迟**

```verilog
    wire real_pix = busy && (cx < IMG_W) && (cy < IMG_H);
```

```verilog
            de <= slot_d1;
            dv <= rd_en;                        // rd_en 是上一拍寄存的"是否真实像素"
            x  <= ax;
            y  <= ay;
```

第 k 拍计数器给出 `(cx,cy)`；第 k+1 拍把地址与使能交给 RAM，同时锁存 `ax/ay` 与 `slot_d1`；
第 k+2 拍 `rd_data` 有效，而 `de/dv/x/y` 也已经过同样的两级打拍，**四者与读数据严格同拍**。

**（2）(W+1)×(H+1) = 129×129 = 16641 个时隙的"消隐光栅"**

1×1 算法只需扫 16384 拍；但 3×3 邻域算法在行末与图底需要"不存在的邻居"，必须额外冲刷。
本设计把扫描栅格扩成每行 W+1 个时隙（末格为行消隐）、每帧 H+1 行（末行为场消隐）：

* `de`：标记"本拍是一个时隙"（含消隐），供 `win3x3_gen` 决定移位寄存器是否推进；
* `dv`：标记"本拍是真实像素"，供逐像素算法与 BMP 写出器使用；
* 消隐时隙的像素值按 **0** 处理，于是**边界补零天然发生**，不需要任何额外的补零状态机；
* `rd_en` 只由 `real_pix` 驱动，消隐时隙不读 RAM，避免越界地址。

帧结束脉冲用流水后的坐标判断，使脉冲恰好落在最后一个时隙被送出的那一拍：

```verilog
    frame_done <= slot_d1 & (ax == IMG_W) & (ay == IMG_H);
```

### 4.3 win3x3_gen.v：3×3 邻域窗口生成

**结构**：两块行缓存 `lb0/lb1`（各 128×24bit，"组合读 + 时钟写"，综合为 LUTRAM），
加三组三位移位寄存器 `b_r*`（下一行/当前流入）、`m_r*`（中心行 y-1）、`t_r*`（上一行 y-2）。

```verilog
    wire        wr_sel   = din_y[0];                        // 写哪一块
    wire        mid_sel  = ~din_y[0];                       // 中心行(y-1)在哪一块
    wire [15:0] rd_idx16 = (din_x >= IMG_W) ? (IMG_W-1) : din_x;
```

**窗口三列的分工是本模块的核心思想**：
行缓存按**当前列 x** 组合读出，提供窗口的**右列**；移位寄存器里 `r0` 是列 x-1、`r1` 是列 x-2，
提供**中列与左列**。三者配成一组在同一拍寄存输出：

```verilog
            p00 <= t_left;  p01 <= t_r0;  p02 <= top_val;   // 上一行(y-2)：左/中/右
            p10 <= m_left;  p11 <= m_r0;  p12 <= mid_val;   // 中心行(y-1)：左/中/右
            p20 <= b_left;  p21 <= b_r0;  p22 <= din_pix;   // 下一行(y)  ：左/中/右
```

因此**输入时隙到窗口输出只有 1 拍延迟**，`dout_x = din_x-1`、`dout_y = din_y-1`，
输出窗口总数为 W×H = 16384 个

**边界补零分两级**：

```verilog
    wire col_pad = (din_x >= IMG_W);            // 本拍在行消隐格上（右边界补 0）
    wire [PIX_W-1:0] mid_val = ((din_y >= 16'd1) && !col_pad) ? mid_raw : {PIX_W{1'b0}};
    wire [PIX_W-1:0] top_val = ((din_y >= 16'd2) && !col_pad) ? top_raw : {PIX_W{1'b0}};
```

```verilog
    wire left_oob = (din_x <= 16'd1);
    wire [PIX_W-1:0] b_left = left_oob ? {PIX_W{1'b0}} : b_r1;
```

---

## 5. 算法层实现（7 个算法）

### 5.1 统一接口与三类算法

所有算法共用 `algo_pass.v` 定型的同一组端口：输入 `din_dv / din_pix[23:0] / din_x / din_y`，
输出 `dout_dv / dout_pix[23:0] / dout_x / dout_y`。
只有 `dv` 标记；四条输出信号必须**同拍有效**，因此它们写在同一个 `always` 块里一起寄存。

| 类别     | 模块                                 | 输入流                 | 额外需求                                           | 延迟  |
| ------ | ---------------------------------- | ------------------- | ---------------------------------------------- | --- |
| 逐像素    | `algo_pass` / `gray` / `threshold` | `rd_scan` 的像素流      | 无                                              | 1 拍 |
| 3×3 邻域 | `algo_morph` / `algo_sharpen`      | `rd_scan` 的**补边栅格** | `din_de` 时隙（消隐格像素必须为 0）                        | 2 拍 |
| 坐标变换   | `algo_scale`                       | 无（自己产生地址）           | 自己驱动 `rd_en/rd_addr/rd_data`，用 `start/done` 握手 | 2 拍 |

**新增一个算法只需要**：写一个符合该接口的模块 + 在宏配置区加一行分支，其余代码一行不动。

### 5.2 逐个算法

**`algo_pass`（接口模板）**：一级寄存器直通，把像素与三个伴随信号一起打拍：

```verilog
dout_dv  <= din_dv;
dout_pix <= din_pix;
dout_x   <= din_x;
dout_y   <= din_y;
```

**`algo_gray`**：`Y = (77R + 150G + 29B) >> 8`，三个系数全部拆成移位加法，**0 个乘法器**：

```verilog
wire [15:0] sum_y = ( (r16 << 6) + (r16 << 3) + (r16 << 2) + r16 )      // 64+8+4+1 = 77
                  + ( (g16 << 7) + (g16 << 4) + (g16 << 2) + (g16 << 1) ) // 128+16+4+2 = 150
                  + ( (b16 << 5) - (b16 << 1) - b16 );                    // 32-2-1 = 29
```

 
输出三个通道都写 Y，才是真正的灰度图：

```verilog
dout_pix <= {sum_y[15:8], sum_y[15:8], sum_y[15:8]};   // {R,G,B} = {Y,Y,Y}
```

**`algo_threshold`（颜色识别 + 目标检测）**：六个区间参数默认 230/255（三通道），即检测"接近白色"的像素；

```verilog
wire hit = (r8 >= R_LO) && (r8 <= R_HI) &&
           (g8 >= G_LO) && (g8 <= G_HI) &&
           (b8 >= B_LO) && (b8 <= B_HI);
```

包围盒统计**完全在线完成**（`found / min_x / max_x / min_y / max_y / cnt` 几组寄存器，
不需要额外存储整幅掩膜），帧末由一个延迟一拍的触发信号打印：

```verilog
if ((din_x == IMG_W-1) && (din_y == IMG_H-1)) end_d <= 1'b1;
...
if (end_d) begin
    end_d <= 1'b0;
    if (found) begin
        $display("[algo_threshold] 目标检测结果：包围盒 x=[%0d..%0d] y=[%0d..%0d]，宽=%0d 高=%0d，像素数=%0d",
```

宽高由 `max - min + 1` 直接算出，避免漏算最后一个命中像素。

**`algo_morph`（膨胀 / 腐蚀）**：参数 `MODE`（1 = 膨胀取最大，0 = 腐蚀取最小），内部例化 `win3x3_gen`
得到 `p00..p22`，归约写法是"拆三通道 → 数组 → 循环逐元素比较"：

```verilog
rr = wr[0];  gg = wg[0];  bb = wb[0];
for (i = 1; i < 9; i = i + 1) begin
    if (MODE != 0) begin                // ---- 膨胀：逐通道取最大 ----
        if (wr[i] > rr) rr = wr[i];
```

`MODE` 是常量，综合时该分支被固定，循环展开成每通道 8 个比较器的比较树；R/G/B 独立 max/min。

**`algo_sharpen`**：`out = clamp(中心 + K*(中心 − blur))`，`K` 默认 1（即 `2*中心 − blur`），
高斯模糊核为 (1,2,1; 2,4,2; 1,2,1)/16：

```verilog
r0 = a0 + (b0 << 1) + c0;            // 行内 1,2,1
r1 = a1 + (b1 << 1) + c1;
r2 = a2 + (b2 << 1) + c2;
blur_ch = (r0 + (r1 << 1) + r2) >> 4;// 三行 1:2:1 后 ÷16
```

两个数学坑都做了处理：负数差用显式 `$signed()`，越界用饱和函数：

```verilog
function [7:0] clamp8s;                      // 有符号 → 0..255 饱和
    input signed [16:0] v;
    begin
        if (v < 0)                clamp8s = 8'd0;
        else if (v > 17'sd255)    clamp8s = 8'd255;
        else                      clamp8s = v[7:0];
```

**`algo_scale`（缩放）**：`MODE=0` 为 2 倍最近邻放大（输出 256×256，源坐标 = 输出坐标 >> 1，
一个源像素铺 2×2），`MODE=1` 为 2 倍缩小（输出 64×64，隔点取样）：

```verilog
wire [15:0] sx = MODE ? (ox << 1) : (ox >> 1);
wire [15:0] sy = MODE ? (oy << 1) : (oy >> 1);
```

它**自己产生 `rd_en/rd_addr`**（`rd_addr <= sy*IMG_W + sx;`），因为源地址是坐标变换算出来的，
无法靠顺序扫描得到，所以它不接 `rd_scan` 的流，而是直接占用帧缓存读端口。输出像素特意**不做寄存**：

```verilog
assign dout_pix = rd_data;
```

原因：`rd_data` 已经比地址晚一拍，而 `dout_dv/x/y` 是"比地址再晚一拍"的寄存器；
若把数据再打一拍，数据就比坐标晚一格，现象是整幅输出图**整体右移一个像素**。

### 5.3 定点运算策略

* **不用乘法器与除法器**：常数乘法拆成移位加法（`(r16<<6)+(r16<<3)+(r16<<2)+r16`），
  常数除法拆成右移（`>>4`、`>>8`），固定倍数缩放拆成坐标移位（`ox>>1`、`oy<<1`）；
* **先零扩展再运算**：`wire [15:0] r16 = {8'h00, din_pix[23:16]};`
* **负差显式有符号**：`wire signed [16:0] cen_r = $signed({1'b0, p11[23:16]});`（先补成 9 位非负再转有符号）；
* **越界一律饱和而非截断**：直接取低 8 位会让白色回绕成黑色、出现黑边；
* 全链路无浮点、无除法；唯一的"乘法"是锐化的 `K * dif`，而 `K` 是编译期常量参数，会被综合成常数乘法/移位。

---

## 6. Testbench 与仿真内参考模型自检

`tb/` 下三个文件都是**仅仿真、不可综合**代码，作用是让"图案/图片 → 帧缓存 → 读扫描 → 算法 → BMP"
这条流水线在 Vivado 里一键跑通，并在**不依赖 Python**的前提下给出 PASS/FAIL 结论。

### 6.1 宏配置区：一屏之内切换全部实验

配置区集中在 `tb_image_top.v` 开头，设计原则是"只改宏、不改逻辑"。

* **运行模式**：`CFG_GUI_MODE`（图案由 RTL 内部生成，不需要外部文件）与 `CFG_SCRIPT_MODE`
  （从 `data/image.mem` 读图）二选一；打开 GUI 模式会连带定义 `PATTERN_INTERNAL` 与 `PATH_MODE_ABS`
  —— 因为 **Vivado GUI 的仿真工作目录是 `<工程>.sim/sim_1/behav/xsim/`，不是工程根目录**，
  相对路径指不到 `data/`，必须用绝对路径。
* **算法选择**：`ALGO_PASS / GRAY / THRESHOLD / MORPH_DILATE / MORPH_ERODE / SCALE_2X / SHARPEN`
  在标记块之间**只允许打开一个**；一个都没打开时 `段 8c` 的 `` `else `` 兜底按直通例化并打印提示，
  保证工程永远能编译通过。`ALGO_SCALE_2X` 会同时改变尺寸（`OUT_W = IMG_W*2`）。
* **路径与输出名**：`IMG_MEM_PATH / BMP_PATH / REF_BMP_PATH / ALGO_TAG` 四个宏，
  在 `PATH_MODE_ABS` 下取绝对路径，否则取相对路径（以启动 xsim 的工作目录为基准）。
* **`REF_CHECK`**：仿真内参考模型自检开关，推荐常开；它被刻意定义在 `ALGO_SELECT` 与 `OUT_NAME`
  **两个标记之间**，因此批量换算法的脚本不会改动它。
* **三处 BEGIN/END 标记块**（`MODE` / `ALGO_SELECT` / `OUT_NAME`）是给 `scripts/set_algo.tcl`
  自动改写的锚点，删除标记即失效。

### 6.2 三段式仿真流程

**① 装载阶段。** GUI 模式下 TB 给 `pattern_gen` 一个单拍启动脉冲，然后等它生成完整帧，
`wr_en <= gen_dv; wr_addr <= gen_y*IMG_W + gen_x; wr_data <= gen_pix;` —— **边生成边写 RAM**，
不需要任何外部文件。脚本模式下先 `$readmemh` 再逐拍写入，并做 **X 检查**：

```verilog
        $readmemh(mem_path, img_in);
        xcnt = 0;
        for (k = 0; k < DEPTH; k = k + 1) begin
            if (^img_in[k] === 1'bx) xcnt = xcnt + 1;
        end
```

若发现 X（最常见原因就是 `.mem` 行数不足），TB 会打印错误并给出处理建议后 `$finish` ——
这比"图变成花屏再回头找原因"高效得多。

**② 处理阶段。** TB 只发一个单拍 `start_scan`。非缩放算法由 `rd_scan` 接管（产生补边栅格与读地址），
送进算法前做**消隐补零**：

```verilog
    //送进算法的像素
    wire [PIX_W-1:0] pix_scan = dv_scan ? rd_data : {PIX_W{1'b0}};
```

算法按宏例化，接线分三类（逐像素 / 邻域 / 缩放）；缩放模式下不例化 `rd_scan`，
并把 `de_scan/dv_scan/x_scan/y_scan/frame_done` 全部 `assign` 成 0，避免悬空导致 X 传播。

**③ 写出阶段。** 纯事件式等待，没有计数器轮询：

```verilog
        wait (bmp_done === 1'b1);
`ifdef REF_CHECK
        wait (bmp_ref_done === 1'b1);   // 等参考模型图也写完
`endif
```

### 6.3 仿真内参考模型自检（REF_CHECK）

**（1）三块存储**

* `src_img[]`：抓的是"**实际写进 RAM 的那份像素**"（脚本模式在写 RAM 循环里赋值，GUI 模式在写口
  那个 `always` 里赋值）。因此无论图源是 RTL 公式、`image.mem` 还是用户自己的照片，参考模型都自动跟随，
  **不存在"两处公式写不一致"的风险**。
* `pad_img[]`：四周各补一圈 0 的 `(W+2)×(H+2)` 图，语义与 RTL"消隐期补零"完全一致，
  使 3×3 邻域访问永不越界：

```verilog
                    if ((ix == 0) || (iy == 0) || (ix == PW-1) || (iy == PH-1))
                        pad_img[iy*PW + ix] = {PIX_W{1'b0}};
                    else
                        pad_img[iy*PW + ix] = src_img[(iy-1)*IMG_W + (ix-1)];
```

* `gold_img[]`：参考模型输出，尺寸为 `OUT_PIX`，由 `build_reference` 任务按算法宏分支一次性算出
  （缩放用 `>>1` 铺 2×2、形态学在补零图上取 3×3 逐通道最大/最小、锐化用 (1,2,1;2,4,2;1,2,1)/16 高斯核、
  灰度用 77/150/29 定点公式、阈值用与例化处一致的区间参数）。

**（2）按坐标流式比对 —— 最关键的设计**

RTL 每吐出一个有效像素，就按**它自己报出的坐标**去 golden 图取值，而不是顺序取下一个：

```verilog
    wire cmp_in_range = (x_algo < OUT_W) && (y_algo < OUT_H);
    wire [PIX_W-1:0] cmp_ref = cmp_in_range ? gold_img[y_algo*OUT_W + x_algo]
                                            : {PIX_W{1'b0}};
```

由此可以抓住两类"顺序比对抓不到"的问题：

* **坐标错位**：像素值本身对但坐标算错，会与 golden 的别处像素对不上；
* **多送 / 少送像素**：多送会使坐标重复或越界（`!cmp_in_range` 直接判错），少送会使 `cmp_cnt` 不足。

**（3）统计与判定**

```verilog
        end else if (dv_algo) begin
            cmp_cnt <= cmp_cnt + 32'd1;
            if (cmp_bad_now) begin
                cmp_bad <= cmp_bad + 32'd1;
                if (!cmp_first) begin
                    cmp_first <= 1'b1;
                    cmp_fx    <= x_algo;
                    cmp_fy    <= y_algo;
```

```verilog
        if ((cmp_cnt == OUT_PIX) && (cmp_bad == 32'd0))
            $display("[TB][REF]   判定 = PASS —— RTL 输出与参考模型逐像素完全一致");
```

判定严格由"**数够 + 全对**"两项决定；FAIL 时打印首个不一致位置，并给出排查提示
（最外一圈错 → 边界补零；整体错位 → 坐标对齐；个别点错 → 饱和/截断）。

**（4）参考图落地为文件**

第二个 `bmp_writer` 例化（`u_bmp_ref`）吃的是 `gs_dv/gs_pix/gs_x/gs_y`，写出的就是"标准答案图"
`out_ref.bmp`；这套信号在**同一段 `always` 里一起寄存**，保证 `dv/pix/x/y` 严格同拍：

```verilog
            gs_dv  <= gs_run;
            gs_pix <= (gs_idx < OUT_PIX) ? gold_img[gs_idx] : {PIX_W{1'b0}};
            gs_x   <= gs_idx % OUT_W;
            gs_y   <= gs_idx / OUT_W;
```

于是直通算法下 `out_ref.bmp` 与 `out_pass.bmp` 应逐字节相同，可以直接用 `fc /b` 做字节级验收。

### 6.4 计数、校验和与超时保护

* `cnt_scan` 累加 `dv_scan`，应等于 16384；`cnt_algo` 累加 `dv_algo`，应等于 `OUT_PIX`；
* 三条 32 位自然溢出校验和：`chk_gen`（写入 RAM）、`chk_rd`（RAM 读出）、`chk_out`（送写出）。
  其中 `chk_rd == chk_out` **只在直通算法下成立且可作判据**——非直通算法本来就改变像素值，
  两个校验和"不同属正常"，内容正确性一律交给逐像素自检；
* **超时保护**：上限 `400*DEPTH` = 6553600 拍，超时即报错并列出四类常见原因
  （输出像素数不足、坐标越界被丢弃、状态机卡死、3×3 窗口没收到消隐时隙）；
* 最后打印**总仿真周期数**，便于评估运行开销。

### 6.5 bmp_writer.v：BMP 文件写出器

几何参数全部由参数推导，绝不写死数字（128 宽时行尾补 0 字节为 0；101 宽时会自动补 1 字节）：

```verilog
    localparam [31:0] ROW_BYTES = ((IMG_W*3 + 3) / 4) * 4;    // 每行实际占用字节数
    localparam [31:0] PAD_BYTES = ROW_BYTES - IMG_W*3;        // 行尾补 0 字节数（0~3）
    localparam [31:0] IMG_BYTES = ROW_BYTES * IMG_H;          // 像素数据总字节数
    localparam [31:0] FILE_SIZE = 54 + IMG_BYTES;             // 整个文件大小
```

**54 字节头**在 0 时刻一次性算好（`'B','M'`、`bfSize`、`bfOffBits=54`、`biSize=40`、宽、高、
`biBitCount=24`、`biCompression=0`、`biSizeImage`、DPI=2835、保留位为 0），多字节字段一律小端逐字节写出。

**整帧缓冲 + 自动启动**：像素先按坐标攒进 `frame[]`，收满 `EXP_PIX` 个就自动开文件：

```verilog
                        if (pix_cnt == EXP_PIX-1) begin          // 第 EXP_PIX 个像素到齐
                            fd = $fopen(bmp_path, "wb");         // ★"wb" = 二进制写，不能省
                            if (fd == 0) begin
                                $display("[bmp_writer] 错误：无法创建文件 %0s", bmp_path);
                                $finish;                         // 打不开文件就没必要继续跑了
                            end
```

写出时按 **B→G→R** 的顺序逐字节写（BMP 是 BGR 排列），`wy` 从 `IMG_H-1` 递减到 0 实现自底向上，
行尾按 `PAD_BYTES` 补 0，最后 `$fclose` 刷盘并拉高 `done`（`$fclose` 绝不能省，否则文件可能不完整）。
坐标越界的像素会被主动报警并忽略，而不是静默丢失。

### 6.6 pattern_gen.v：内置测试图案发生器

图案按五层规则叠加，**每一层都对应一类待抓的缺陷**：四象限底色（识别 R/B 通道互换）→
8×8 棋盘（行列错位会退化成条纹）→ 顶部红色渐变与左侧绿色渐变（上下/左右颠倒一眼可见）→
白块 `[4..11]²`（供颜色识别算法定位与包围盒验证）→ 右下黑块（暴露翻转/裁切）。
渐变用移位实现 `min(255, 2*v)`：

```verilog
            grad2 = (v >= 16'd128) ? 8'd255 : {v[6:0], 1'b0};
```

输出侧 `dv/pix/x/y` 四者在同一 `always` 里一起寄存，保证永远同拍；`done` 脉冲正好落在最后一个有效像素那一拍，
便于 TB 用 `wait` 等待。它的接口与 `rd_scan` 完全相同，因此"内部图案写 RAM"与"扫描读 RAM"
可以共用同一套对齐规则与自检机制。

---

## 7. 配套 Tcl 脚本与数据文件

### 7.1 img2mem.tcl：24 位 BMP → `data/image.mem`

入口 `img2mem {bmpfile w h {memfile ""}}`，以二进制方式整体读入 BMP，逐字段解析 54 字节头
（`magic`、像素数据偏移、DIB 头大小、宽、高、位深、压缩方式），并做**六项校验**，
每项失败都给出可操作的提示：

| 校验                  | 失败提示（节选）                                                         |
| ------------------- | ---------------------------------------------------------------- |
| 不是 BMP              | `is not a BMP file (magic='...')`，并提示在画图里另存为 24 位 BMP            |
| 老式 BITMAPCOREHEADER | `old BITMAPCOREHEADER is not supported`                          |
| 有压缩                 | `compressed BMP (compression=...) is not supported`              |
| 非 24 位              | `need a 24-bit BMP, this one is N bpp`                           |
| 尺寸不符                | `size mismatch: the file is WxH, but the design expects 128x128` |
| 文件截断                | `file is truncated (need N bytes of pixels, got M)`              |

**像素解码一次成批取出**（比逐字节循环快得多）：`binary scan [string range $data $off end] c* bytes`，
取用时统一 `& 0xFF` 还原无符号值；行对齐按 BMP 规范 `stride = ((3W+3)/4)*4`；
高度为正表示自下而上存储，用 `ry = bottom_up ? (hh-1-y) : y` 做行翻转，
因此**无论 BMP 存储方向如何，输出都统一为 y=0 在上的光栅序**。

输出格式为每像素一行 6 位十六进制 `RRGGBB`，行号即像素索引即 RAM 地址：

```tcl
    set fh [open $memfile w]
    fconfigure $fh -translation lf
    puts $fh "// ${bw}x${h} RGB888, row order y=0 (top) -> y=H-1, one pixel RRGGBB per line"
    puts $fh [join $lines "\n"]
```

脚本用 `-translation lf` 保证只写 LF；并明确要求**纯 ASCII 编写**——Vivado 的 Tcl 以系统 ANSI
代码页读取无 BOM 脚本，中文字节会破坏语法（本工程实测踩过两次）。

### 7.2 set_algo.tcl：不改中文注释地切换实验

三个过程各司其职，且**只改写被标记包围的宏块**：

| 过程                     | 作用                                                     | 改写的标记块                     |
| ---------------------- | ------------------------------------------------------ | -------------------------- |
| `set_algo <算法>`        | 切换算法并同步输出文件名、日志标签                                      | `ALGO_SELECT` + `OUT_NAME` |
| `set_src mem\|pattern` | 切换数据源（`mem` 会同时打开 `CFG_SCRIPT_MODE` 与 `PATH_MODE_ABS`） | `MODE`                     |
| `set_paths`            | 工程被拷到新目录后，按新位置重写绝对路径（算法不变）                             | `OUT_NAME`                 |

核心是 `replace_block`：用 `string first` 定位 BEGIN/END 标记，只替换两者之间的文本，
标记本身保留，不满足条件就报错而不是静默改错：

```tcl
proc replace_block {txt mbegin mend body} {
    set i [string first $mbegin $txt]
    set j [string first $mend $txt]
    if {$i < 0 || $j < 0 || $j < $i} {
        error "marker not found: $mbegin / $mend"
    }
```

三处读写 TB 都显式声明 `-encoding utf-8 -translation lf`，这是"**不会破坏中文注释**"的关键；
而算法自动识别刻意**不用正则**（Tcl 8.5 的反斜杠转义太容易出错），改为逐行判断
"去掉空白后是否以 `` `define <宏> `` 开头"。

脚本自身位置在 **source 时**就捕获到全局变量：

```tcl
set ::DSH_PROJ_ROOT [file normalize [file join [file dirname [info script]] ..]]
```

若把这行写进过程内部，`[info script]` 返回的会是**调用者脚本**的路径（在 Tcl Console 里甚至是空串），
实测会导致工程根目录算高一层、`set_paths` 找不到 `tb/tb_image_top.v`。

### 7.3 data/image.mem：图片数据文件

格式：首行为注释（`$readmemh` 会忽略 `//` 行），其后**每行 6 位十六进制 RRGGBB**，
行号（从 0 起）= 像素索引 = RAM 地址，行序为 y=0 在上。实测统计：**16385 行**（1 行注释 + 16384 个像素）、
**114763 字节**（16384×7 + 注释 74 + 换行 1，完全吻合）、**无 CR 字节**。

TB 侧的读入与强制检查：

```verilog
        $readmemh(mem_path, img_in);
        xcnt = 0;
        for (k = 0; k < DEPTH; k = k + 1) begin
            if (^img_in[k] === 1'bx) xcnt = xcnt + 1;
        end
```

**对应关系（整条链路的闭环）**：

```
BMP（自下而上、行 4 字节对齐、可能 BGR 排列）
   │ img2mem.tcl：解析头 + 行翻转 + 通道重排
   ▼
data/image.mem（线性 RRGGBB，行号 = y*W+x）
   │ $readmemh → 逐拍写入
   ▼
帧缓存 img_ram → rd_scan → 算法层 → bmp_writer.v（重新排成 BGR/自下而上）
   ▼
out/out_<算法>.bmp（可直接双击查看）
```

实测核对：把 `data/image.mem` 与源图 `data/in/test.bmp` **16384 个像素全量逐点比对，不一致数为 0**。

---

## 8. 方案优势

### 8.1 验证闭环完全在仿真内部，零外部工具依赖

常见做法是"仿真出图 → 用 Python/Matlab 写脚本比对"，一旦换机器、缺依赖、环境不同，验证就跑不起来。
本方案把**测试图案发生器、参考模型、逐像素比对器、判定打印**全部用 Verilog 写在 testbench 里：

* 运行仿真只需要 Vivado 自带的 `xsim`，不需要 Python、不需要 PowerShell、不需要任何第三方库；
* 判定结论直接以 `[TB][REF] 判定 = PASS` 的形式打在 Vivado 的 Tcl Console 里，
  连"打开图片肉眼比对"都不是必须步骤。

### 8.2 参考模型"跟着数据走"，换成自己的图片也不用改一行

参考模型的源图不是按公式重新生成的，而是**抓取"实际写进 RAM 的那份像素"**（`src_img`）。
因此无论输入是 RTL 生成的测试图案、`data/image.mem` 里的数据、还是用户自己的照片，
参考模型都自动适配 —— 这使"用真实照片验证算法"变成零成本操作。

### 8.3 按坐标比对，能抓住"不易察觉"的错误

比对时不是"按输出顺序取下一个参考像素"，而是**用输出像素自己的坐标**去参考图里取值。
这样不仅能发现数值错误，还能发现**坐标错位、少送/多送像素、行列颠倒**这类
"图看着差不多、其实边界或对齐已经错了"的问题。

### 8.4 统一接口 + 三类算法模型，算法可插拔

所有算法共用同一套流式接口约定
（`din_dv/din_pix/din_x/din_y` → `dout_dv/dout_pix/dout_x/dout_y`），
并按"逐像素 / 3×3 邻域 / 坐标变换"三类给出模板。
**新增一个算法只需要**：写一个符合接口的模块 + 在宏配置区加一行分支，不动其他任何代码。

### 8.5 面向可综合的定点策略

* 只用**移位、加法、比较**，不使用乘法器与除法器（例如灰度权重 77/150/29 全部用移位相加实现）；
* 处理结果一律**饱和**（clamp 到 0/255），不做截断，避免亮度反转等视觉异常；
* 需要处显式使用 `$signed()` 与位宽扩展，避免隐式符号错误。

### 8.6 参数化与可扩展的存储模型

帧缓存做成行为级双口 RAM 模型，地址位宽、数据位宽、深度全部由参数决定；
`rd_scan` 的消隐光栅同样按 `IMG_W/IMG_H` 参数化，改分辨率只需同步改几个参数
（`.mem` 行数随之改变）。

### 8.7 工程可迁移、可复现

* 图片转换、算法切换、数据源切换、路径修正全部由 Tcl 脚本完成，**只改被标记包围的宏块**，
  且显式按 UTF-8 读写，不会误伤中文注释；

### 8.8 全流程可留档

每个算法都会产出三样东西：RTL 输出图、参考模型输出图、仿真日志（含像素计数、校验和、判定）。
报告的每一项结论都有可追溯的原始文件支撑。

---

## 9. 实测结果

### 9.1 七个算法的验收结果（仿真内参考模型判定）

| 算法          | 中文说明               | 算法输出像素           | 不一致像素 | 最大通道误差 | 判定       | 独立模型交叉验证             |
| ----------- | ------------------ | ---------------- | ----- | ------ | -------- | -------------------- |
| `pass`      | 直通（链路基准）           | 16384 / 16384 OK | 0     | 0      | **PASS** | 逐字节一致（PSNR 99.00 dB） |
| `gray`      | 灰度化 77/150/29 移位加法 | 16384 / 16384 OK | 0     | 0      | **PASS** | 逐字节一致                |
| `threshold` | 颜色识别 + 目标检测        | 16384 / 16384 OK | 0     | 0      | **PASS** | 逐字节一致                |
| `dilate`    | 3×3 膨胀             | 16384 / 16384 OK | 0     | 0      | **PASS** | 逐字节一致                |
| `erode`     | 3×3 腐蚀             | 16384 / 16384 OK | 0     | 0      | **PASS** | 逐字节一致                |
| `scale2x`   | 2 倍最近邻放大（256×256）  | 65536 / 65536 OK | 0     | 0      | **PASS** | 逐字节一致                |
| `sharpen`   | 高斯模糊 + 锐化          | 16384 / 16384 OK | 0     | 0      | **PASS** | 逐字节一致                |

### 9.2 目标检测（颜色识别算法）的双重验证

* RTL 在帧末打印：`x=[4..11] y=[4..11]，宽=8 高=8，像素数=64`；
* 独立模型算出的包围盒数字**完全相同**，说明目标定位正确（不是"图看着像"）。

### 9.3 输出产物与字节级证据

| 产物                 | 说明                                               |
| ------------------ | ------------------------------------------------ |
| `out/out_<算法>.bmp` | 每个算法的 RTL 输出图（`scale2x` 为 196662 字节，其余 49206 字节） |
| `out/out_ref.bmp`  | 参考模型给出的"标准答案图"                                   |
| `out/log_<算法>.txt` | 仿真日志：像素计数、校验和、`[TB][REF]` 判定                     |
| 日志摘录               | `不一致像素 = 0` / `最大通道误差 = 0` / `判定 = PASS`         |

---

## 10. 使用流程（只需 Vivado）

```tcl
# 1) 打开工程，Run Simulation 前先确认：Simulation Settings → xsim.simulate.runtime = all
cd <工程路径>/fpga_image_platform

# 2) 加载 Tcl 工具（都在 Vivado 的 Tcl Console 里执行）
source scripts/set_algo.tcl
source scripts/img2mem.tcl

# 3) 修正路径 / 选算法 / 换数据源（三选若干）
set_paths                                        ;# 迁移到新位置后修正绝对路径
set_algo gray                                     ;# 切换算法
img2mem data/in/myphoto.bmp 128 128 data/image.mem ;# 自己的图片 → 数据文件
set_src mem                                       ;# 数据源切到 data/image.mem
```

然后在 Vivado 里点击 **Run Behavioral Simulation**，在 Tcl Console 里读判定：

```
[TB] 图案来源    = image.mem 文件（.../data/image.mem）
[TB] 算法输出像素  = 16384 / 16384  OK
[TB][REF]   不一致像素   = 0
[TB][REF]   最大通道误差 = 0
[TB][REF]   判定 = PASS —— RTL 输出与参考模型逐像素完全一致
```

结果图在 `out/out_<算法>.bmp`，标准答案图在 `out/out_ref.bmp`，双击即可查看。

---

## 11. 已知限制与后续工作

| 限制              | 说明 / 后续方向                                         |
| --------------- | ------------------------------------------------- |
| 分辨率固定 128×128   | 已参数化，改 `IMG_W/IMG_H/ADDR_W` 与 `.mem` 行数即可；也可加缩放前端 |
| 仅支持 24 位未压缩 BMP | 压缩/其它位深需先转换（Windows 画图另存为 24 位 BMP 即可）            |
| 算法为整数定点实现       | 已覆盖基础图像处理算子；可扩展直方图均衡、双边/导向滤波、背景替换                 |
| 未做上板            | 当前以仿真验证为主；后续可加时序约束、综合上板与摄像/显示接口                   |
| 存储为行为级模型        | 上板前可替换为厂商 RAM IP，接口不变（读写时序一致）                     |
