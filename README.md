# 基于 FPGA 的运动目标检测

团队 GGBOND · PYNQ-Z2 + Attach-Z2 · XC7Z020-1CLG400C

## 2026-11-03 更新：HDMI r3 数码管位选修正版

本次提交提供最新 **r3 digitfix** 的独立完整工程与电脑端视频工具。入口为
[`deliverables/tier1_attach_hdmi_r3/`](deliverables/tier1_attach_hdmi_r3/README.md)。
该目录是本次待评审交付；原 `src/`、`board/`、`tools/` 及其历史工程继续保留，不与 r3 混用。
用户于 2026-11-03 确认 `FPGA_All_Code_r3.rar` 为已提交官方的代码包；本次交付与该附件哈希一致，见[核对记录](report/r3_update_20261103/official_package_confirmation.json)。
代码已整理，r3 原包构建证据已核对；**完整实板功能与稳定性验收仍未完成**。

| 入口 | 内容 |
| --- | --- |
| [r3 完整工程](deliverables/tier1_attach_hdmi_r3/README.md) | RTL、约束、HDMI IP、构建与仿真脚本、r3 bit |
| [视频链路和电脑工具说明](docs/r3_video_and_usage.md) | J10/J11 链路、4 个 Python 脚本、命令、帧率与截图边界 |
| [版本与验证证据](report/r3_update_20261103/README.md) | r3 哈希、时序/DRC/CDC、已有检查与未验证项目 |
| [机器可读清单](report/r3_update_20261103/manifest.json) | 105 个交付文件的 SHA-256 与准确 r3 元数据 |
| [旧版首页快照](docs/history/README_before_r3_20261103.md) | 旧主线、UART/AXI/PS 和历史验收叙述，非本次 r3 的验收结果 |

### 使用当前 r3

1. 使用 `deliverables/tier1_attach_hdmi_r3/FPGA/` 下的构建入口或随包 bit。
2. 通过 Vivado Hardware Manager/JTAG 加载 `FPGA/bitstream/combined_top.bit`。
3. PC HDMI 接 J10，J11 接显示器或 USB 采集卡；Windows 使用扩展显示，信源设为 **1280×720、60 Hz**。
4. 按[视频工具说明](docs/r3_video_and_usage.md)播放视频和预览采集结果。

当前 r3 是纯 PL：无 PS/AXI/HWH 加载接口，无 DDR 视频帧缓存或输入缩放器。
请勿用历史 Overlay/SSH/PS 启动脚本覆盖当前 bit。模式显示预置值未连接检测阈值；实际检测阈值固定为 100。

r3 bit SHA-256：

```text
c3c3a16c91e31a8044704aa959cbbbcf55844f9e3aa4e343b5abe8c246c8e8c8
```

原 r3 构建为 Vivado 2026.1，WNS +0.107 ns、WHS +0.013 ns、阻断 DRC=0；仍有 DRC Warning 和 CDC Critical。
原包根 `manifest.json` 沿用了 r2 内容，本次提供单独核实的清单，不引用其旧 bit 哈希或旧时序数值。

### 协作与许可

本分支从 2026-11-03 查询到的 `main`（`63e0e9c`）建立，通过 PR 评审后再由有权限的队友合并。
不会将旧分支历史合入重建后的 main；其他成员工作区与分支保持其原有安排。协作要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。

交付目录包含构建所必需的 Digilent dvi2rgb/rgb2dvi IP，保留原 MIT 许可及版权；这部分是 r3 的实际依赖。
第三方参考作品、视频素材、Vivado 生成工程和缓存未纳入本次更新。
