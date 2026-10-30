# 2026-10-08 参考作品「代码级」精读（不是扫描）

## 为什么有这一篇

用户第二次追问同一句：「你去看一看其他项目，至少得学到硕士水平吧」。
第一次（09-25/09-28）我做的是 **clone + 一个工程精读 + 一份"算法本体审计"（看 README）**；
10-08 上午我做的是 **`_ref_scan.py` 正则扫描**。
**扫描 ≠ 学习。** 用"扫出来的架构表"冒充"学出来的结论"是错的，这一篇是补课。

## 一、我这次真的读了哪些文件（逐行读，不是 grep）

| 文件 | 行数/大小 | 读到了什么 |
|---|---|---|
| `Frame_Difference/src/fdma_hdmi_top.v` | 654 行 / 17.9 KB | 同题同板作品的**完整顶层**：4 个 FDMA、DDR 帧缓冲、双差分、阈值按键调、双窗显示 |
| `Frame_Difference/src/boundary_tracking.v` | 395 行 / 8.9 KB | 包围盒用 **FIFO 存 x/y 坐标、下一帧求 min/max** 的四级状态机 |
| `1.Motion-Detection-.../IP/image_process_1.0/src/u_block_value_generator.v` | 361 行 / 7.4 KB | 同题作品 #1 的**全部算法装在一块**：2×2 均值 → 上一帧差 → 阈值 70 → 包围盒 → 就地叠加 |
| `PYNQ-ComputerVision/boards/Pynq-Z1/notebooks/filter2d_and_dilate.ipynb` | 25 个有效格 | **官方 overlay 的完整使用范式**（壳的活样板） |
| `PYNQ-OpenSource-Template/yolo_ukf_track/src/overlay/vivado_bd.tcl` | 93 行 | **自建 PYNQ overlay 的配方**（含 `.hwh` 怎么来） |
| `PYNQ-ComputerVision/boards/Pynq-Z2/**` | 11 个文件 | 目录真相（见下 §4） |

## 二、★ 纠错：`Frame_Difference` 不是"纯帧差"

我 09-28 的审计写的是「灰度 + 中值 + 帧差 + 边界跟踪 / ❌ 纯实现」。**"中值"与"纯帧差"两条都站不住**：

```
lcd_Y1 = |sys_data_out2 − sys_data_out1|      // 帧 t-1 与帧 t-2 之差
lcd_Y2 = |sys_data_out3 − sys_data_out2|      // 帧 t   与帧 t-1 之差
lcd_Y  = lcd_Y1 & lcd_Y2                       // 两次差分取「与」
lcd_T1 = (lcd_Y > Frame_Threshold) ? 0x00 : 0xff
```
→ 这是 **双差分取与（two-frame difference with AND）**：连续两帧都在动才算前景。
**这是对单帧差法的实质改进**（单帧差对噪声/单帧抖动敏感，双差分取与能压掉）。
→ 而且阈值 **`Frame_Threshold` 由 `Key_Frame_Threshold.v` 用板上的 key0/key1 实时调**（`Frame_Grade` 分档），**不是硬编码**。
→ 显示用 `lcd_driver_dualwin`：**左半屏原灰度、右半屏二值前景，同屏对比**；key3 用 `Key_Filter` 消抖后切换"显示帧差/显示灰度"。

**对我们的意义**：我们 09-28 用它当"反面教材"（"同题作品还停在帧差法"）——措辞红线要收紧：
**它是"帧差 + 运动一致性(双差分取与) + 运行时阈值 + 双窗演示"，比我们记的强。**
报告里那句「同题目作品均停留帧差法」要么删，要么改成「同题公开作品采用双差分取与的帧差变体」。

## 三、★ `Frame_Difference` 的架构（同题同板，最有参照价值）

```
OV7725 摄像头 ──cmos_pclk 域──▶ CMOS_Capture_RAW_Gray ──▶ Video_Image_Processor(RAW→8bit灰度)
                                                            │
                     ┌──────────────────────────────────────┘
                     ▼  frame_cnt 每 2 帧循环：帧A 写 FDMA0/FDMA2，帧B 写 FDMA1/FDMA3
              ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
              │ FDMA0  DDR   │   │ FDMA1  DDR   │   │ FDMA2  DDR   │   │ FDMA3  DDR   │
              │ 0x0100_0000  │   │ 0x0200_0000  │   │ 0x0300_0000  │   │ 0x0400_0000  │
              │ BUF_SIZE=3   │   │ BUF_SIZE=3   │   │ BUF_SIZE=3   │   │ BUF_SIZE=3   │
              └──────┬───────┘   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
                     │  clk_hdmi 域读（读时钟 ≠ 写时钟 = 跨时钟域，由 FDMA 内部 FIFO 承担）
                     ▼                  ▼                  ▼                  ▼
              lcd_gray(原图)      sys_data_out1      sys_data_out2      sys_data_out3
                                 └──────── 三次比较 → lcd_Y → lcd_T1 ────────┘
                                                     ▼
                              rgb2dvi ──▶ HDMI OUT（挂在我们同样的 tmds_* 口上）
```

**关键点**：
1. **全部帧都过 DDR，不塞 BRAM** —— 4 个 FDMA × 3 缓冲。**这就是我 MEMORY 里"我们一直在最小的那间屋子里干活"的活证据**：同题同板的作品用自定义 DMA + DDR 起三条帧通路，我们用 BRAM 起两条。
2. **写时钟 `cmos_pclk`、读时钟 `clk_hdmi` 是两个时钟域**，跨时钟域握手**由 FDMA 内部 FIFO 吃掉**，顶层只写 `.W0_wclk_i / .R0_rclk_i`。
3. **PS 侧（`system` = PS7）在这个设计里只提供 DDR 控制器与 `ui_clk`/复位**，算法全在 PL。→ **"用不用 ARM"和"算法放不放 PL"是两件事**：它用了 PS，但算法仍在 PL。
4. 640×480（不是 720p），`clk_hdmi` + `clk_hdmi_5x`（5× 串行时钟）**和我们一模一样**。

## 四、★★ 官方 overlay：我们"壳"的活样板（这一篇最值钱）

`boards/Pynq-Z1/notebooks/filter2d_and_dilate.ipynb` 的 25 个有效格，完整范式：

```python
from pynq import Overlay
bareHDMI = Overlay(".../xv2Filter2DDilate.bit")     # ① 一个 overlay 同时含 video + 加速器
from pynq import Xlnk
Xlnk.set_allocator_library(".../xv2Filter2DDilate.so")
mem_manager = Xlnk()

hdmi_in  = bareHDMI.video.hdmi_in                   # ② video 子系统就挂在 overlay 里
hdmi_out = bareHDMI.video.hdmi_out

from pynq.lib.video import *
hdmi_in.configure(PIXEL_GRAY)                       # ③ 直接要灰度，RGB→灰由硬件做
hdmi_out.configure(hdmi_in.mode)                    # ④ 输出跟随输入分辨率 = 自适应
hdmi_in.cacheable_frames  = False                   # ⑤ 免 cache 一致性麻烦
hdmi_out.cacheable_frames = False
hdmi_in.start(); hdmi_out.start()

inframe  = hdmi_in.readframe()                      # numpy uint8 (h,w)
outframe = hdmi_out.newframe()
xF = mem_manager.cma_array((h, w), np.uint8)        # 连续物理内存
xv2.filter2D(inframe, -1, kernel_g, dst=xF, borderType=cv2.BORDER_CONSTANT)
xv2.dilate(xF, kernelVoid, dst=outframe, borderType=cv2.BORDER_CONSTANT)
inframe.freebuffer()
hdmi_out.writeframe(outframe)

hdmi_in.close(); hdmi_out.close()                   # ⑥ 不 close → 下次画面错位
```

**六条硬结论（每一条都直接改我们的方案）**：
1. **不需要 base overlay**：`xv2Filter2DDilate.bit` 这个 overlay **自带 video 子系统**（`bareHDMI.video.hdmi_in`）。我之前记的"走 base overlay 直通"只是 A 方案，B 方案是"**自己的 overlay 里把 video 子系统一起装进去**"。
2. **`configure(PIXEL_GRAY)` 直接出灰度** → 我们原计划里的 **`gray.v` 重写（BT.601 RGB→灰）不用自己写了**。
3. **`hdmi_out.configure(hdmi_in.mode)`** → **分辨率自适应是官方 API 送的**：对方给 1080p 也能跟着走。这解掉了"对方可能给 1080p"那个坑的大半。
4. **`cacheable_frames=False` + `Xlnk.cma_array`** → 连续物理内存 + 免 cache，**这是 PS↔PL 搬帧能稳的前提**。
5. **`xv2.xxx(...)` 与 `cv2.xxx(...)` 同名同参**（`dst=`、`iterations=`、`borderType=cv2.BORDER_CONSTANT` 都一致）→ **软件版本与硬件版本可以逐行对照**，这就是最好的"软/硬对照"素材（评分项「性能与资源」直接能用）。
6. **`ipywidgets.interact` 下拉菜单换 3×3 kernel** → **运行时交互调参的现成范式**（对应用户要的"场景自适应 / 能演示"），不用重综合。

**真实性能数字（官方 notebook 自报，可进我们报告做对照基线）**：
- HW dilate 单块 @100 MHz ≈ **40 fps**；filter2D + dilate 串联 ≈ **20 fps**。

**顺序铁律（官方原文强调）**：*"All overlay and python libraries should be loaded prior to assigning the HDMI input/outputs."*
→ **必须先 `Overlay()`，再碰 `hdmi_in/out`**；否则功能不正常。

**收尾铁律**：必须 `hdmi_in.close(); hdmi_out.close()`，否则"后续执行会出现画面错位（shifted output image）"。

### ⚠️ 纠错：`boards/Pynq-Z2` 的 notebook 是空的

`boards/Pynq-Z2/notebooks/filter2d.ipynb` 只有 **38 字节**，内容是**一行相对路径**：
```
../../Pynq-Z1/notebooks/filter2d.ipynb
```
→ **clone 时软链退化成了纯文本**。所以我上次记的"Z2 有 filter2d.ipynb 可直接用"**要改成"Z2 目录里 notebook 是软链残骸，真身只有 Pynq-Z1 那份"**。
Z2 目录真正有货的是 **overlay 三件套**：`xv2Filter2DDilate.{bit,hwh,so}`、`xv2Filter2DRemap.{bit,hwh,so}` —— **全是编译好的二进制，没有可改的 Vivado 工程**。要用我们自己的算法，得自己搭一个同样带 video 子系统的 block design。

## 五、★★ 自建 PYNQ overlay 的完整配方（`vivado_bd.tcl` 逐行）

```tcl
set part "xc7z020-clg484-1"                       # ⚠️ 我们的是 xc7z020clg400-1，封装不同
create_project ...
create_bd_design "design_1"
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "true"} $ps7
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} \
                         CONFIG.FCLK_CLK0_ENABLE {true} CONFIG.FCLK_CLK0_FREQ {100000000} \
                         CONFIG.PCW_USE_FABRIC_INTERRUPT {1}] $ps7
# AXI Interconnect → 自研 IP 的 s_axi_control；proc_sys_reset 接 FCLK_RESET0_N
assign_bd_address ; validate_bd_design ; save_bd_design
generate_target all [.../design_1.bd]
make_wrapper -files [.../design_1.bd] -top
launch_runs synth_1 ; wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream ; wait_on_run impl_1
write_hw_platform -fixed -include_bit -force design_1.xsa
write_hwdef -force -file design_1.hdf
file copy -force design_1.hdf design_1.hwh          # ★ 这就是 PYNQ 要的 .hwh
```

**两条新知识**：
1. **`.hwh` 就是 `write_hwdef` 产出的 `.hdf` 改个名** —— 我此前不知道 `.hwh` 从哪来。
2. **PYNQ overlay 的标准三件套 = `.bit` + `.hwh` + 驱动（`.py`/`.so`）**，前两个由 Vivado 出，第三个由 PYNQ 的 overlay 框架出。

⚠️ 这个模板**不含 video 子系统**（只有 PS + HLS IP）。**要带着 HDMI 进/出，得把 video 子系统（`v_tc`/`v_axi4s_vid_out`/`dvi2rgb` 那一套）一起搭进去**，或直接以 PYNQ 官方 `boards/Pynq-Z2/base` 的 `base.tcl` 为底改建 —— 这是下一步要读的东西。

## 六、同题作品 #1（`u_block_value_generator.v`）读到的东西

一块模块把整条流水线包完，**和我们几乎一模一样**：

| 步骤 | 它的做法 | 我们的 |
|---|---|---|
| 压缩 | **2×2 求均值**（`average_value`，10 bit） | 2×2 **求和**（10 bit） |
| 参考帧 | `fifo_backframe` 深度 **76800 = 640×480/4** 个块，`wr_en` 只写偶数列组 → **它就是"上一帧"** | 缓上一帧（`fifo_backframe`，同思路） |
| 差分 | `abs_data = \|sub_data1 − sub_data2\|` | 同 |
| 阈值 | **硬编码 `abs_data > 70`**（多处出现） | 阈值 70（照抄它） |
| 包围盒 | x1/x2/y1/y2 全局 min/max，**且带边缘屏蔽 `cnt_x>5 && cnt_x<634`、`cnt_y>5 && cnt_y<474`** | 全局并集，**无边缘屏蔽** |
| 叠加 | **就地**：前景像素涂红 `{255,0,0}`、包围盒四边涂蓝 `{0,0,255}`、其余显背景灰度 | 有叠加，做法待核 |
| 8bit 还原 | `{sub_data1[9:3], sub_data1[2]\|\|sub_data1[1]}`（截位 + 舍入位） | 待核 |

**新增可学点（两条，我们都没有）**：
1. **边缘屏蔽（裁掉四周 5 像素）** —— 一行判据，白送的抗边界噪声。
2. **10bit → 8bit 的舍入位写法** `{v[9:3], v[2]|v[1]}`。
3. 它的包围盒也是**全局并集一个框**（不是多目标）→ **"同题公开作品都没有多目标"这条结论成立**（这条我原来记对了）。

## 七、这次**仍然没读**的（诚实交代）

- `Frame_Difference` 的 `Video_Image_Processor.v`（RAW→灰 具体算法）、`Key_Frame_Threshold.v`（阈值分档）、`Key_Filter.v`（消抖）
- `Frame_Difference/src/fdma_controller`（**自研 DMA 本体，最重要却还没读**）与 `make.tcl`（40 KB，它怎么把工程搭起来）
- PYNQ 官方 `boards/Pynq-Z2/base/base.tcl`（**带 video 子系统的 block design 怎么搭**，这是"壳"的最后一块）
- `FPGA-Gaussian-Filter-Accelerator` 的 `lineBuffer.v`/`line_window.v`/`conv.v`（3×3 窗口写法，7 个小文件）
- `ANLU-LOGIC`（SDRAM + HDMI 通路）、`FPGA_SocChina_2025`（`block_design_z2.tcl` + 从 0 到 1 教程）
- 10 个里的 `hlstrack2025-*` 两个（命题式赛道，与本题无关，AMD 官方参考库）

**下一篇接着读**：`fdma_controller`（自研 DMA 怎么写）+ PYNQ `base.tcl`（video 子系统怎么进 block design）。
