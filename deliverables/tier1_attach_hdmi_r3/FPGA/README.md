# FPGA 工程

顶层为 `src/rtl/board/combined_top.v`，器件为 `xc7z020clg400-1`。当前构建使用 `board/pynq_z2_combined.xdc`，其中 `attach_digit[0..8]` 已按 r3 修正为反向位选映射。`pynq_z2_hdmi_out.xdc` 为单独 HDMI 输出约束，当前工程不加载它。

创建工程和常规构建方法见包根目录 README。脚本会使用本目录的 `ip_repository`；设置 `MOTION_IP_REPO` 可覆盖 IP 库位置。

## 保存源码快照并构建

以下命令均在本目录执行。先将 Vivado 的 `bin` 目录加入 `PATH`，或将环境变量 `VIVADO_BIN` 设为本机 Vivado 的 `bin` 目录：

```text
python build/scripts/run_gated_build.py build/run_submission
```

输出目录必须尚不存在。脚本保存源码快照、构建日志、状态、报告和 bitstream。也可通过 `--vivado-bin` 和 `--ip-repo` 显式指定软件与 IP 目录。

## 运行仿真

在 Windows 上配置 `VIVADO_BIN` 或 `PATH` 后执行：

```text
python sim/run_attach_protocol.py attach_check
python sim/run_combined_checks.py combined_check
```

结果写入 `evidence/attach_check` 和 `evidence/combined_check`；重复运行时更换标签，避免覆盖已有结果。

- `run_attach_protocol.py`：数码管扫描、WS2812 数据与复位间隔、蜂鸣器。
- `run_combined_checks.py`：检测流水线、顶层元数据连接、720p 数字视频输入接口。
- `tb_attach_z2_interaction.sv`：额外保留的基础交互测试源。

仿真中 HDMI 接收与板级时钟使用替代模型，用于数字接口检查。完整构建使用真实 Digilent IP；仿真结果不代表 TMDS 电气链路或实板稳定性已经验证。

## 随包 bitstream

`bitstream/combined_top.bit` 保留原 r3 文件，未在源码整理时重新生成。

SHA-256：`c3c3a16c91e31a8044704aa959cbbbcf55844f9e3aa4e343b5abe8c246c8e8c8`。
