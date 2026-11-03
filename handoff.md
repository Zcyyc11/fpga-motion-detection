# GitHub r3 更新交接

日期：2026-11-03。分支：`codex/r3-hdmi-video-update-20261103`，基于 `main` 的 `63e0e9c`。

- 目标：同步最新 r3 digitfix 源码、bit 和视频工具，并给出准确使用及验证说明。
- 有效入口：根 README；`deliverables/tier1_attach_hdmi_r3/`；`docs/r3_video_and_usage.md`；`report/r3_update_20261103/`。
- 105 个包内文件保持字节一致；原 r3 bit SHA-256 为 `c3c3a16c91e31a8044704aa959cbbbcf55844f9e3aa4e343b5abe8c246c8e8c8`。
- 新清单纠正原包根 manifest 沿用 r2 的问题。r3 构建 WNS +0.107 ns、WHS +0.013 ns、阻断 DRC=0；DRC Warning/CDC Critical 保留。
- 验证见 `report/r3_update_20261103/verification.json`。本次未重跑综合实现、未重新生成 bit、未作 GUI/真实采集或实板验收。
- 旧工程、资料与当前 main 接口未改；原首页保存在 `docs/history/README_before_r3_20261103.md`。
- 本提交供 GitHub 独立分支与 PR 评审，未合并 main；实际推送状态、提交号和 PR 以远端及 `git log -1` 为准。
- 持板方后续核对 bit 身份，检查车辆框、外设、断线重锁、重复上电和至少 10 分钟稳定性。`board_verified=false`。
- 没有运行中的 Vivado/仿真进程。本地原目录与来源包保留；不删除文件或历史失败证据。
- 新工作树 checkout 即出现旧文件 `sim/run_sim.bat`、`src/rtl/attach_z2_interaction.v` 的换行差异；未纳入此次提交。
