# HDMI 输出周期性跳锁 · 定位与解决（2026-10-20 收官）

> 一句话：**板子没插网线 → 板载 125 MHz 参考时钟不稳 → dvi2rgb 相位对齐余量不足 → 输出周期性跳锁。插上网线即根治。**
> 影响范围：所有 `INPUT_SEL=1`（真实 HDMI 输入）场景。**这是环境硬条件，不是 bit 缺陷。**
> 作者：线一（主城要）。证据目录：`board/logs/board_test_20261020.md`。

---

## 1. 现象

采集卡（UGREEN 25854）视角，同一链路下画面在三种状态间周期性跳变，约 10 秒一周期：

| 亮度 | 实际画面（逐帧抽查确认） | 含义 |
|---|---|---|
| 0.0 | 纯黑，**无任何 OSD 字符** | HDMI 有同步，但内容全黑（物理层未断） |
| 5.2 | 采集卡 OSD 大字 **"Video Format Not Supported"** | 有时序信号，但**格式锁不上** |
| 210–217 | 完整灰度场景 + 检测框 | 正常锁定 |

60 秒采样中：黑/半锁约占 90%，满锁仅 4–5 个孤点（每次 1–2 秒）。
**即：90% 的时间采集卡根本锁不上板子输出的时序格式。**

## 2. 排除过程（全部实测，逐项留证）

| 嫌疑 | 验证方式 | 结论 |
|---|---|---|
| bit 本身 | 重烧 `9f506bef`（10-12 PASS 同款）后屏立刻回归 | 无罪 |
| Windows 显示栈 | 独显驱动整体 disable→enable（final CM_PROB_NONE）后仍跳 | 无罪 |
| bit 掉电丢失 | 补烧后恢复——这是**另一宗**独立故障（板子中途断电导致 EDID 消失） | 已修，非本次主因 |
| 外接 USB Hub | PnP 扫描：全机设备 LOC 均为 `Port_#XXXX.Hub_#0001`，无 `Hub_#0002`、无第三方集线器节点 | **不存在**（首次误判为 Hub，已更正） |
| HDMI 线 | J10/J11 两根线对调后照跳 | 无罪 |
| USB 口 / 后端 | 采集卡直插机身（Port_#0004，OK 状态） | 无罪 |
| 视频源 | 换 `vehicles.mp4`（10-12 成功场景）后当前配置仍亮帧 0% | 无罪 |
| 采集参数 | 20 组矩阵（DSHOW/MSMF × 5 分辨率 × MJPG/YUY2） | **无效**：最优组 8 秒采样 43%，同配置 60 秒复测仅 8%——是运气不是配置 |

## 3. 破案

### 3.1 社区同源病例

PYNQ 官方论坛 [HDMI output signal issue on the Z2](https://discuss.pynq.io/t/hdmi-output-signal-issue-on-the-z2/696)（2019）：

- **ksstms**：Z2 上"显示半秒 → 丢信号 1–2 秒 → 再显示"循环，Z1 上 720p 正常——**与本例症状一致**
- **cathalmccabe**（PYNQ 项目负责人）：建议改用 PS→PL 的 FCLK
- **darren**：*"On my Pynq Z2 the 125MHz clock isn't stable unless I have the ethernet connected or a loopback plug inserted."*

> 注：该帖直连抓取返回 403，以上要点取自检索摘要，内容与本例实测吻合后方才采信。

### 3.2 代码侧责任链（本仓库源码实读）

```
板载 125 MHz (sys_clk, H16)
      │
      ├─ clock_74m25.v ──▶ 74.25 MHz   ← INPUT_SEL=1 时【不参与】，见下
      │
      └─ clock_200m.v (M=64/Dv=8/D0=5, VCO 1000 MHz)
                │
                ▼
          200 MHz RefClk ──▶ dvi2rgb 的 IDELAYCTRL（相位对齐用）
                │
                ▼
          相位对齐数据眼宽 ──▶ pLocked ──▶ 整条链
```

关键代码：

- `src/rtl/board/board_top.v:85`　`wire clk_pipe = INPUT_SEL ? pixel_clk_rx : clk_pix;`
  → INPUT_SEL=1 时，流水线与 rgb2dvi 输出**跟 dvi2rgb 恢复的 PixelClk 走**，本地 74.25 MHz 那组不参与。
  → 因此 125 MHz 影响视频链路的**唯一通路就是 clock_200m → RefClk**。
- `src/rtl/board/board_top.v:258`　`assign led[0] = locked_sel;` → **LED0 = pLocked**，即上述链路的锁定指示。
- `src/rtl/board/clock_200m.v`　MMCM 参数：`CLKFBOUT_MULT_F=64 / DIVCLK_DIVIDE=8 / CLKOUT0_DIVIDE=5`，VCO = 1000 MHz，输出精确 200 MHz。

### 3.3 为什么"以前好使过好几回"

**这是余量（margin）问题，不是硬损坏。** 抖动是随温度、12 V 供电质量、板子连续运行时长漂移的连续量：

- 抖动小 → 数据眼够宽 → pLocked 稳定 → 输出稳 → 采集卡锁住（10-12 那几轮 PASS）
- 抖动漂大 → 眼不够宽 → 相位对齐周期性失败重锁 → 输出断续 → 采集卡报"格式不支持"（10-20）

硬损坏一次都不可能好使；**好使过数回恰是余量不足的铁证**。这也解释了为何换线/换口/换视频/改采集参数全部无效——都没动那个临界量。

## 4. 解法与实测

**动作：板子插上网线（接路由器/交换机，或插环回头）。**

插线前 / 后各采 60 秒，采集参数完全一致（MSMF + 1280×720 + MJPG），数据直接可比：

| 指标 | 插网线前 | 插网线后 |
|---|---|---|
| 亮帧数（>20） | 4–5 / 61 | **61 / 61** |
| 亮度范围 | 0 / 5.2，偶发 213 | **126.5 – 131.5** |
| 采集卡 OSD | "Video Format Not Supported" | 无 |

与 10-12 成功记录（亮度 125.8、28.4 fps）在同一水平。

## 5. 沉淀：新增强制条件

**PYNQ-Z2 运行 HDMI 视频通路必须插网线。** 已写入 `docs/power_cycle_sop.md` 与 `docs/board_runbook.md`。

诊断速查：

- **LED0 常亮** → 输入锁相正常
- **LED0 周期性闪/灭** → pLocked 在反复重锁，先查网线，再查 12 V 供电与板子温度

## 6. 后续可选加固（未实施，留档）

从设计上把余量拉大，使系统不再依赖网线。改 `src/rtl/board/clock_200m.v`：

| 参数 | 现在 | 改成 | 效果 |
|---|---|---|---|
| `CLKFBOUT_MULT_F` / `DIVCLK_DIVIDE` / `CLKOUT0_DIVIDE` | 64 / 8 / 5 | **32 / 5 / 4** | VCO 1000 → **800 MHz**，抖动随 VCO 下降 |
| `BANDWIDTH` | OPTIMIZED | **LOW** | 强化对 125 MHz 源抖的滤除 |
| 输出频率 | 200 MHz 精确 | **200 MHz 精确（不变）** | 零副作用 |

验算：`125 × 32 / 5 = 800 MHz ∈ [600, 1200]`；`800 / 4 = 200 MHz` 精确。

**暂不实施的原因**：当前 `9f506bef` 是已验证基线（10-12 与 10-20 均 PASS），改 RTL 需重新综合并**重跑全部验收**，在赛程内风险大于收益。

**建议用法**：若赛后有富余，做成对照实验（A 版拔网线跳锁 / B 版拔网线仍稳），形成"现象→定位→机理→改进→实测验证"的完整闭环，可作为设计报告中的工程能力佐证。

> 队规提醒：`clock_200m.v` 属 RTL，改动前须与线三（孙伟博）确认（RTL 冻结 `02fce44`）。

## 7. 本次遗留

- 六场景验收采集待跑（vehicles / market-square / people-walking 可自动；空 / 单目标 / 多目标需真人配合）
- 串口验收未通（CH340，COM3/COM5 仍 Unknown，需重插）
- 《板端验收回填模板》八项待回填（bit SHA = `9F506BEF4132`）
- 仓库 `private → public`（截止 2026-11-04 18:00 前必须）

## 8. 附：本轮产生的工具脚本（位于本机 `D:\FPGA\output\`，未入库）

`capture_60s.py`（60 秒逐秒采样）、`stitch_contact.py`（60 帧拼总览图）、
`scan_capture_modes.py`（采集参数矩阵扫描）、`capture_60s_v2.py`（参数化采集）。
