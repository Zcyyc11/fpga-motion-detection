# FPGA 运动目标检测系统源码

本包包含 PYNQ-Z2 与 Attach-Z2 的 FPGA 源码、HDMI 收发 IP、约束、工程构建脚本、仿真测试，以及电脑端视频播放和采集工具。硬件版本为 HDMI r3 数码管位选修正版。

## 文件目录

| 目录 | 内容 |
| --- | --- |
| `FPGA/src/rtl/` | 运动检测、目标框叠加和外设交互逻辑；`board/` 子目录包含板级顶层及 HDMI 控制 |
| `FPGA/board/` | 管脚与时序约束；当前工程使用 `pynq_z2_combined.xdc` |
| `FPGA/ip_repository/` | Digilent dvi2rgb、rgb2dvi 源码、配置、文档及许可证 |
| `FPGA/build/scripts/` | 创建 Vivado 工程及执行构建的脚本 |
| `FPGA/sim/` | 流水线、HDMI 数字接口和 Attach 外设仿真 |
| `FPGA/bitstream/` | 随原 r3 包提供的 `combined_top.bit` |
| `VideoTools/` | 4 个 Python 播放与采集脚本、依赖清单和使用说明 |
| `SHA256SUMS.txt` | 包内文件的 SHA-256 校验清单 |

## 创建与构建 FPGA 工程

目标器件为 `xc7z020clg400-1`。Windows 环境需要安装支持该器件的 Vivado；Python 脚本需要 Python 3。先在 Vivado Tcl Shell 中切换到 `FPGA` 目录，再执行：

```tcl
source build/scripts/create_project.tcl
```

脚本使用包内 IP 库，生成 `project/combined_pynq_attach.xpr`。已有工程时可直接打开该文件。工程缓存及中间文件由 Vivado 重新生成，未作为源码重复收录。

执行完整构建可在 Vivado 命令行环境中运行：

```text
vivado -mode batch -source build/scripts/build_vivado.tcl
```

构建结果位于 `FPGA/build/run_日期_时间/`；通过脚本中的时序和 DRC 检查后生成 bitstream。需要保存独立源码快照时，可改用 `build/scripts/run_gated_build.py`，详见 `FPGA/README.md`。

## 使用

1. 安装并连接 PYNQ-Z2、Attach-Z2。HDMI 信号源接 J10，显示器或采集卡接 J11。
2. 用 Vivado Hardware Manager 通过 JTAG 加载 `FPGA/bitstream/combined_top.bit`。
3. 将输入设置为 1280×720、60 Hz。本设计不含缩放器或 DDR 视频帧缓存。
4. 电脑端播放、采集命令见 `VideoTools/README.md`。

本版本为纯 PL 设计，无 PS/AXI/HWH 加载接口。模式预置显示不改变固定检测阈值 100；LCD、触摸和传感器接口未实现采集功能。源码整理未改变 FPGA 功能逻辑，实板表现以相应硬件环境中的测试为准。

## 第三方源码

Digilent IP 保留原始版权与 `FPGA/ip_repository/License.txt`。运行所需的 Vivado、Python、OpenCV 等软件需另行安装；视频素材不属于源码，未随包重复收录。
