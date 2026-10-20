# 板端实测记录 · 2026-10-20（HDMI 跳锁定位与解决）

操作人：线一（主城要）　器件声明：**XC7Z020-1CLG400C**（PYNQ-Z2，Zynq-7020）

bit：`board_top_hdmiin.bit`（INPUT_SEL=1 真实 HDMI 输入），**SHA256 前 12 位 `9F506BEF4132`**——与 10-12 PASS 记录同一块 bit。
构建/烧录：Vivado 2026.1，JTAG。

链路：电脑 HDMI 输出（1280×720@60）→ J10　｜　J11 → UGREEN 25854 采集卡 → OpenCV（设备 1）
信源：`vehicles.mp4` / `people-walking.mp4`（cv2 窗口摆板子屏 2560,0）

---

## 一、跳锁现象（插网线前）

同一链路 60 秒逐秒采样（MSMF + 1280×720 + MJPG），连续三轮形态一致：

| 状态 | 亮度 | 帧内容 | 占比 |
|---|---|---|---|
| 纯黑 | 0.0 | 无 OSD，纯黑 | ~50% |
| 半锁 | 5.2 | 采集卡 OSD "Video Format Not Supported" | ~40% |
| 满锁 | 210–217 | 完整灰度场景 + 检测框 | 4–5 个孤点 / 分钟 |

结论：**90% 时间采集卡锁不上板子输出的时序格式**。物理层未断（黑帧无 OSD logo = 有同步）。

## 二、排除项（详见 `docs/hdmi-lock-instability-postmortem-20261020.md`）

bit / 显示栈 / 外接 USB Hub（不存在）/ HDMI 线（对调照跳）/ USB 口（直插 OK）/ 视频源 / 采集参数矩阵（20 组全部无效）——**均无罪或非主因**。

## 三、判决与验证

**根因**：板载 125 MHz 参考时钟不稳 → `clock_200m`（VCO 1000 MHz）→ 200 MHz RefClk → dvi2rgb IDELAY 相位对齐余量不足 → pLocked 周期性重锁 → 输出断续。
同源病例：PYNQ 官方论坛 `[HDMI output signal issue on the Z2]`（darren：*"the 125MHz clock isn't stable unless I have the ethernet connected or a loopback plug inserted"*）。
代码依据：`board_top.v:85`（输入模式整链跟恢复时钟走，本地 74.25 组不参与）、`board_top.v:258`（LED0 = pLocked）。

**解法：板子插网线。**

## 四、插网线后实测（60 秒，参数同前）

```
s00 131.2  s01 131.4  s02 131.3  s03 130.6  s04 131.1  s05 131.2
s06 131.0  s07 131.3  s08 130.9  s09 127.7  s10 129.4  s11 129.6
...（61 帧全程无 0.0 / 5.2）...
s60 130.9
```

| 指标 | 结果 |
|---|---|
| 亮帧数（亮度>20） | **61 / 61** |
| 亮度范围 | **126.5 – 131.5**（与 10-12 的 125.8 同一水平） |
| 跳锁现象 | **消失** |

证据：`lock_contact_sheet.jpg`（60 帧 5×12 总览，全亮）存于本机 `D:\FPGA\output\`。

---

## 五、本次新增铁律

**运行 HDMI 视频通路前，板子必须插网线。** 已同步进 `docs/power_cycle_sop.md`、`docs/board_runbook.md`。

## 六、遗留

- 六场景验收采集（vehicles / market-square / people-walking 可自动；空 / 单目标 / 多目标需真人配合）
- 串口验收：CH340（COM3/COM5）仍 Unknown，待重插
- 《板端验收回填模板》八项待回填
- 仓库 private → public（截止 2026-11-04 18:00）
