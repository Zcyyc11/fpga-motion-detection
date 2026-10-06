# src/rtl/ — 自研 RTL

**分层**：
- `*.v`（本目录）＝**设备无关的算法流水线**，仿真与综合都用
- `board/*.v`（子目录）＝**板级外壳**（时钟、IO），只综合不仿真
  （它实例化 MMCME2_BASE / BUFG / rgb2dvi 这些只在 Vivado 工程流程里存在的原语与 IP，
   xsim 直接编译会因缺库报错，所以必须分层）

**命名约定**：小写 + 下划线。每个模块的头部注释写清「它在整机里是哪一环、为什么需要它」。

## 模块清单（与代码同步维护）

| 文件 | 五步链位置 | 功能 |
|---|---|---|
| `video_timing.v` | ① 时序 | 产生 hs/vs/de 与像素坐标 x,y；`SYNC_POS` 决定同步极性（720p 用 1=正极性） |
| `pattern_gen.v` | ② 激励 | 复刻 `data/golden/make_test_clip.py` 的合成片段（黑底白矩形、每帧右移 DX） |
| `downsample2x2.v` | ③ 压缩 | 8bit 像素 2×2 **求和** → 10bit 大像素（640×360×10bit ≈ 64 块 BRAM36，720p 整帧放不下 BRAM 的解法） |
| `frame_buf.v` | ④ 缓存 | 1 张「大像素图」；帧差模式存上一帧、背景模式存背景图，两者行为相同（读旧写新） |
| `diff_stage.v` | ⑤ **差分** | `|I − 缓存|`；**唯一与参考作品 #1 不同的一步**。背景模式另算 `B ← B + (I−B)/2^SHIFT` |
| `threshold.v` | ⑥ 阈值 | `absdiff > 70`（照抄 #1 硬编码值，**2×2 和域**，≈单像素 17.5 灰阶） |
| `morph_open.v` | ⑦ 形态学 | 开运算 = 腐蚀 → 膨胀（两级 `morph3x3` 串联） |
| `morph3x3.v` | ⑦ 形态学 | 3×3 单步腐蚀/膨胀；零扩展、居中锚点、每帧独立 |
| `bbox.v` | ⑧ 包围盒 | 全局并集框 x1/y1/x2/y2 + 面积门限 |
| `overlay.v` | ⑨ 叠加 | 把包围盒画回画面（红框）+ 左上角状态灯（绿=检出） |
| `md_pipeline.v` | 整机 | 把①~⑨串成一条流水线，输出视频 + 包围盒 + 掩码探针 |

## 板级（`board/`）

| 文件 | 功能 |
|---|---|
| `board_top.v` | 顶层：125 MHz → MMCM → 74.25 MHz → `md_pipeline` → `rgb2dvi` → HDMI J11；4 个 LED 当状态灯 |
| `clock_74m25.v` | MMCME2_BASE 参数：`M=37.125 / Dv=4 / D0=15.625` → 像素时钟**精确** 74.25 MHz（VCO 1160.16 MHz）。参数由 `build/scripts/mmcm_search.py` 解出，不是估的 |

## 与「计划版模块名」的对应（避免有人拿旧清单找不到文件）

| 旧计划名 | 实际文件 |
|---|---|
| `timing_ctrl.v` | `video_timing.v` |
| `hdmi_in_ctrl.v` | **未实现**（HDMI 输入侧尚未接入） |
| `gray_conv.v` | **未实现** —— 曾以 `gray.v` 存在过，但**全仓没有任何模块例化它**（只是被 `*.v` 通配符搭便车编进仿真与综合），已于 2026-10-06 移出仓库；接 HDMI 输入时需重写（BT.601 整数近似，不复杂） |
| `frame_buffer.v` | `frame_buf.v` + `downsample2x2.v`（压缩与缓存拆成两个模块） |
| `frame_diff.v` | `diff_stage.v`（帧差与背景建模共用，靠 `MODE_BG` 切换） |
| `thresh_bin.v` | `threshold.v` |
| `morph_erode.v` / `morph_dilate.v` | `morph3x3.v`（一个模块两种模式）+ `morph_open.v` |
| `centroid.v` | **未实现**，当前只要包围盒，不要质心 |
| `bbox_overlay.v` | `overlay.v` |
