<!-- Hallmark · pre-emit critique: P5 H4 E4 S5 R5 V4; scope: measured results and open failures. -->

# 第一阶段实测记录

基线：ead15e0，2026-10-09。结论：已完成合成跟踪复现与自动取证，发现告警边界缺陷；本机新 RTL 仿真能运行，但完整导出帧数不足。阶段结果不能作为整个线三已交付的声明。

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| clean 跟踪 | 120 帧，15 帧重叠；可见目标 210/210，误检 0、ID 换号 0、断航 0 | run_ead15e0_01/results.json，clean/frame_audit.csv、target_audit.csv |
| algo 跟踪 | init-frames=12；可见目标 186/210=0.885714；误检 0、换号 0、断航 0 | 同上 algo/ |
| 方向 | clean 207/208；algo 183/184，均有一次方向不符，不能称全对 | target_audit.csv、logs/clean.txt、logs/algo.txt |
| 可见期框最大误差 | clean 0 px，algo 1 px | target_audit.csv |
| algo 历史参考 | 120 行逐帧 CSV、2 行告警 CSV 与归档一致 | results.json 的 reference_*_diffs 为空 |
| 取证包装透明性 | 两模式 CSV/事件一致，解码视频逐帧哈希一致 | results.json 的 observer_* |
| 两结果视频 | 各解码 120 帧、1280×720、30 fps，ALARM 显示帧与事件帧一致 | results.json；两模式 keyframes.png |
| 小测试 | 共 25 项，20 通过、5 失败；含无目标、单目标、分离目标、短遮挡、双向越界与停留 | cases/cases.json |
| 比对工具故障注入 | 错框、错 ID、错告警、缺帧、重复帧、错帧号、空结果均检出；乱序接受，位置断言通过 | cases/*_diff.json |
| 两种 Python 整数模型 | framediff / bg 各运行 12 帧 | framediff.csv、bg.csv |
| 归档 RTL 复核 | 第 0–10 帧逐字段一致；与完整模型相比缺第 11 帧 | archive_*、results.json |
| 新 RTL framediff | Vivado 2025.2，编译及仿真完成，x_hits=0；CSV 仍仅 11 行，完整判定失败 | rtl_fd01/console.txt、result.json |
| CDnet 历史表 | 读取各存量表，主表 V43 的 12 段/7 类类别均值为 0.7367119048，舍入为 0.737 | cdnet_audit.json |
| 原始文件保全 | 本轮 Python 入口运行前后全部基线 Git 跟踪文件 SHA256 无变化 | manifest.json、results.json 的 protected_files_changed=[] |

CDnet 数字来自存量 CSV 的四位小数分数再汇总，没有运行真实视频检测，没有原始 TP/FP/FN，不能独立复算像素混淆矩阵。未配置 CDNET_ROOT；检查的 `D:\FPGA\datasets\cdnet2014` 不存在，仓库没有 temporalROI.txt。没有扫描全盘寻找数据，也没有下载数据。

## 已确认的告警问题

1. `exit_left`、`exit_right`：中心明确从禁入区走到区外，预期离开计数 1，实际 0。源码 `AlarmRule.update` 只有 moving_in 才更新 side，正常向外运动未进入该分支。
2. `reenter_left`：中心 70→40→70→40，线 x=50、左侧为内，预期进入 2/离开 1，实际进入 1/离开 0。
3. `dwell_non30fps`：10 fps 连续观察 10 帧，1 秒阈值能触发，但事件 secs 写成 0.3，因为硬编码除以 30。
4. `dwell_consecutive_gap`：在区内两帧、缺一次、再两帧，3 连续帧阈值仍触发；缺失观测没有清零计数。是否允许缺失期间保留计数须明确需求；按当前“连续停留”的说明判失败。

合成主片段控制台计数为进入 2、离开 1；CSV 只有两条 cross_in，视频也只显示这两次事件。查代码可见 cross_out 只有计数没有事件流水。**计数恰好为 1 不能推翻边界测试**：还需从 observations.json 找到该计数实际发生帧，与真值离开帧 32 对照。

## 下一步已定位的审计点

- 冻结表 I4 的 LINE_X=640 标为大像素域，但大像素 x 合法值是 0–639；PC line-x=640 是 1280 像素原图中线。需队长与线一、线二确认单位。
- 冻结表 I1/I3 11 bit，与当前 RTL 多处 16 bit 端口不同；I3 多目标协议和 I4 寄存器不能按表存在就说已落地。
- 主表 V43 分类均值：dynamicBackground 0.8432、nightVideos 0.3040、cameraJitter 0.6336。资料内 0.907、0.262、0.505 等说法可能来自旧变体，需逐项标来源，不混成同一个冠军结果。
- `docs/入门.md` 将“视频变红次数”与 CSV 行数等同不准确：检测框本身每帧都是红色，当前越界事件显示为 ALARM 文字。
- 官方指南 3.3.5.4 要求提交文件名纯英文；现有中文文档须队长统一规划发布重命名，本线只报告，不移动原件。
- `sim/view_sim.py` 会覆盖参考产物且会删除临时目录，本轮没有运行其 main。可只复用 read_ppm/red_box_bounds 做独立检查。

原有缺失/损坏图像、中文 imread 和文档命令检查器问题沿用外层 `verification_20261009/` 的同提交证据；没有重复运行以制造本轮测试数量。远程开工时 fetch 成功，origin/main 仍为 ead15e0；最终交付前还应检查一次。
