# fpga-motion-detection

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道（AMD）
> 赛道 **3.3 自主选题 · 初级组** ｜ 团队 **GGBOND** ｜ 大连理工大学

**作品名称：《基于 FPGA 的运动目标检测》**

**本页只讲「现在是什么状态」和「去哪儿看」，不重述规则与技术方案。** 权威源分工见 §4。

---

## 1. 这个作品现在是什么

PL 内的一条实时像素流水线。**测试激励由 PL 自己产生**，不接 HDMI 输入：

```
pattern_gen      PL 内造黑底白块激励（每帧右移 DX，到头回绕）
  → downsample2x2  2×2 求和压缩 8bit → 10bit（640×360）
  → frame_buf      缓存「上一帧」/「背景图」
  → diff_stage     帧间差分（MODE_BG=1 时切背景建模 B←B+(I−B)/2^SHIFT）
  → threshold      absdiff > 70（2×2 和域阈值，≈单像素 17.5 灰阶）
  → morph_open     3×3 开运算
  → bbox           运动区域**包围盒** x1/y1/x2/y2 + 面积门限
  → overlay        把框画回画面（红框）
  → rgb2dvi → HDMI J11 输出
```

**三条边界（别搞错）：**

- **输出是包围盒，不是质心。** `centroid.v` 从未实现，也不在计划内。
- **没有 HDMI 输入通路。** `dvi2rgb` 尚未生成，J10 未接线；「HDMI 采集视频流」尚未成立。
- **没有灰度转换、没有 VDMA、没有 PS↔DDR 搬运。** 激励本身即灰度图；整条链是 PL 内纯 RTL。

## 2. 当前位置（实测，非声称）

| 项 | 状态 | 证据（都在仓内，可自行复核） |
|---|---|---|
| RTL 仿真 | ✅ 通过 | `build/scripts/run_sim.py` —— 判据按**日志内容**，不按退出码（xsim.bat 恒返回 0） |
| 与硬件模型逐位对齐 | ✅ **11/11 帧逐帧逐字段完全一致** | `sim/logs/model_vs_rtl.txt`、`sim/wave/bbox_rtl.csv` |
| 从零构建到 bitstream | ✅ 通过（exit 0，2026-10-06 18:02） | `build/bitstream/board_top.bit`（4,045,764 B）、`build/logs/vivado_build.log` |
| 时序 | ✅ 满足 | `build/reports/impl_timing_summary.rpt`（Routed）：All user specified timing constraints are met |
| 资源占用 | LUT **19.24%**（10237/53200）｜FF 5.62%｜BRAM **57.14%**（80/140）｜DSP 0.45% | `build/reports/impl_utilization.rpt` |
| 板上实测 | ⚠️ 画面已跑通（2026-10-06），但**证据未落盘** | `board/logs/` 与 `board/overlay/` 目前只有 `.gitkeep` —— **这是「须交实测日志」的缺口** |
| 设计报告正文 | ⬜ 未开始 | 大纲见 `技术文档\报告大纲.md` |

> ⚠️ **判时序只认 impl 报告。** `synth_timing_summary.rpt` 报 WHS 为负（失败端点全在跨 `rgb2dvi` 内部时钟域的路径：综合阶段没有真实布线延迟、估计偏悲观），Routed 后收敛。**两阶段结论相反不代表设计有问题。**

## 3. 怎么复现（四步，全部不需要 GUI）

```bat
:: 环境：Vivado / Vitis 2026.1；PYNQ-Z2 官方镜像 v3.1.1（加载 overlay 须 ignore_version=True）

:: 1) RTL 仿真（xvlog → xelab → xsim）
python build\scripts\run_sim.py

:: 2) 与硬件模型逐位对照（必须报「完全一致」）
python src\ps\rtl_golden.py --compare sim\wave\bbox_rtl.csv --report sim\logs\model_vs_rtl.txt

:: 3) 出对比图 + 演示视频（H.264，Windows 自带播放器可直接打开）
python sim\view_sim.py

:: 4) 从零构建到 bitstream（参数：0=帧差法 v1 / 1=背景建模 v2）
build\scripts\build_vivado.bat 0
:: 产出 build\bitstream\board_top.bit 与 build\reports\（资源 / 时序 / 时钟）
```

- 脚本内**不硬编码本地绝对路径**（用脚本自身位置推导）；IP 仓库路径可用环境变量 `MOTION_IP_REPO` 覆盖。
- 时序不收敛时构建脚本**主动 `exit 1`**（时序门放在 impl 之后），不让可疑的 bit 流到上板那一步。

## 4. 文档导航（每件事只有一个权威源）

| 想查什么 | 去哪（唯一权威） |
|---|---|
| 进度 / 产物 / 物料清单 | `桌面\FPGA大赛资料\计划表与产物词典.docx` |
| 官方要求怎么落地（权重·红线·提交物） | `技术文档\竞赛规则与提交要求.md` |
| 技术决策（含「帧差法 → 背景建模」论证） | `技术文档\技术方案.md` |
| 报告怎么写 | `技术文档\报告大纲.md` |
| 参考资料索引与来源可靠性分级 | `技术文档\参考作品.md` |
| 大模型协作记录（6 篇） | `report\llm_log\` |
| 技能包（6 项） | `skill\` |

## 5. 目录结构

| 目录 | 放什么 |
|---|---|
| `src/rtl/` | 自研算法流水线 **11 个 `.v`**（含整机 `md_pipeline.v`）+ `board/` 板级外壳 **2 个 `.v`** |
| `src/ps/` | ① 硬件模型的**黄金参考**（对照用）② **算法实验台** `algo_lab.py` + `cdnet_official.py`（PC 侧迭代算法，结果 CSV 就是成绩表的证据链）③ `multi_track.py`（多目标 + 跟踪 + 越界告警） |
| `src/hls/` | 空目录，只留「为什么不走 HLS」的说明 |
| `sim/` | testbench、仿真产物、与硬件模型的对照报告 |
| `build/` | 可复现构建脚本、综合实现报告、bitstream |
| `board/` | 板级约束（**生效的只有 `pynq_z2_hdmi_out.xdc`**）、overlay 与实测日志（待补） |
| `data/` | 黄金参考（合成片段 + 逐帧真值）与采集素材说明 |
| `docs/` | **给队友看的**：`入门.md`（30 分钟跑通）、`接口冻结表.md`（改接口前必读） |
| `skill/` · `report/` | 技能包 · 设计报告与大模型协作记录 |

## 6. 环境要求

| 项 | 版本 |
|---|---|
| 开发板 | PYNQ-Z2（**XC7Z020-1CLG400C**），512 MB DDR3 |
| 开发工具 | **Vivado / Vitis 2026.1** |
| 板卡运行环境 | PYNQ-Z2 官方镜像 **v3.1.1**（Python 3.x + Jupyter） |
| 工作分辨率 | **720p**（1080p 超出 Z2 的 HDMI 规范能力） |

> ⚠️ **镜像与工具版本错位**：镜像 v3.1.1 的 overlay 由 Vivado 2024.1 构建，与本工程 2026.1 不同。
> 加载时须 `Overlay("xxx.bit", ignore_version=True)` 跳过 HWH 版本校验。

## 7. 第三方代码声明

本仓库**不含任何第三方项目的代码**。唯一的外部 IP 是 Digilent 开源的 **rgb2dvi**（HDMI 发送：TMDS 编码 + 串化），
由构建脚本从本地 IP 仓库引入，**不进仓库**。参考过的开源实现与思路，出处与可靠性分级见 `技术文档\参考作品.md`。

## 8. 开源协议

**MIT License**，详见 [LICENSE](LICENSE)。
