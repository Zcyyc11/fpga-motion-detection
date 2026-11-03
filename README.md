# FPGA 运动目标检测系统（PYNQ-Z2）

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · **3.3 自主选题赛道 初级组**
> 器件：**AMD Xilinx Zynq-7000 XC7Z020-CLG400-1（PYNQ-Z2）**
> 版本：**r3（HDMI 数码管位选修正版）· 纯 PL 设计**

本系统基于 FPGA 实现运动目标检测：对 HDMI 输入（1280×720@60Hz）做帧差、形态学、阈值与跟踪，
叠加红色检测框与警戒线/停留报警，并驱动板载 9 位数码管、WS2812 灯环、蜂鸣器与按键。

## 设计性质说明（重要）

**本提交为纯 PL 设计，无 PS / AXI / HWH 加载接口。** 模式预置显示不改变固定检测阈值（100）；
LCD、触摸与传感器接口未实现采集功能。源码整理未改变 FPGA 功能逻辑，实板表现以相应硬件环境测试为准。

## 目录结构（对应赛事 3.3.5.4 推荐结构）

| 目录 | 内容 |
| --- | --- |
| `src/` | 运动检测、目标框叠加与外设交互 RTL（`rtl/` 子目录含板级顶层 `combined_top` 与 HDMI 控制） |
| `sim/` | 流水线、HDMI 数字接口与 Attach 外设仿真 |
| `build/` | 可复现构建脚本（`build/scripts/`）+ 综合与实现报告（`build/reports/`）+ 比特流（`build/bitstream/`） |
| `board/` | 管脚与时序约束；当前工程使用 `pynq_z2_combined.xdc` |
| `data/` | 测试数据与参考结果（黄金测试集、实测比对） |
| `skill/` | 与大模型协作沉淀的技能包（含 README 说明适用范围/用法/失效条件） |
| `report/` | 设计报告 + 大模型协作记录（`llm_log/`） |
| `ip_repository/` | Digilent dvi2rgb / rgb2dvi 第三方 IP 源码、配置、文档与许可证 |
| `VideoTools/` | 电脑端视频播放与采集 Python 脚本、依赖清单与使用说明 |

### 不在推荐结构内的附加目录（保留并说明，符合"非强制、须给出目录对照"）

| 目录 | 内容 |
| --- | --- |
| `docs/` | 设计过程文档、会议纪要、复盘与评审材料 |
| `deliverables/` | 阶段交付与队友验收包 |
| `evidence/` | **板上实测证据**（视频、截图、JSON 日志），对应赛事 3.3.3.2"作品须在板上跑通并提供实测输出" |
| `tools/` | 电脑端辅助脚本 |

## 创建与构建 FPGA 工程

目标器件 `xc7z020clg400-1`。Windows 需安装支持该器件的 Vivado（推荐 2026.1 或 2025.2）；
Python 脚本需 Python 3。在 Vivado Tcl Shell 切换到 `src/`（或仓库根）后执行：

```tcl
source build/scripts/create_project.tcl
```

脚本使用包内 IP 库，生成工程；已有工程可直接打开。完整构建：

```text
vivado -mode batch -source build/scripts/build_vivado.tcl
```

构建结果位于 `build/` 对应子目录；通过脚本中的时序与 DRC 检查后生成比特流。
需保存独立源码快照时可改用 `build/scripts/run_gated_build.py`。

## 上板运行

1. 安装并连接 PYNQ-Z2、Attach-Z2。HDMI 信号源接 J10，显示器或采集卡接 J11。
2. 用 Vivado Hardware Manager 通过 JTAG 加载 `build/bitstream/combined_top_r3.bit`。
3. 输入设为 1280×720、60 Hz（本设计不含缩放器或 DDR 视频帧缓存）。
4. 电脑端播放 / 采集命令见 `VideoTools/README.md`。

## 校验与复现

- `SHA256SUMS.txt`：包内关键文件 SHA-256 校验清单。
- `data/`：黄金测试集与实测比对数据，用于功能正确性确认。
- `evidence/`：板上实测输出证据。

## 第三方源码

Digilent IP 保留原始版权与 `ip_repository/License.txt`。Vivado、Python、OpenCV 等运行软件需另行安装；
视频素材不属于源码，未随包重复收录。

## 开源协议

本项目以允许再分发的开源协议发布（推荐 MIT / Apache-2.0），符合赛事 3.3.3.3 开源要求。
