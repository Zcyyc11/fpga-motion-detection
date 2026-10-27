# 断电重启与上板 SOP（HDMI 输入方案）

> 定位：满足《硬件产品级审查》🔴 红项 3（断电重启流程）——bitstream 是 JTAG/网络下载，**断电即丢**，比赛/演示前必须走本流程重载。配合 §5.1 上板验收第 4 项使用。
> 状态：2026-10-11 立档。当前 bit 未固化 QSPI（见 §4 可选路线），一切以本 SOP 为准。

---

## 1. 一句话

**任何一次断电之后，先重载 bit，再插 HDMI 输入，再确认画面。** 顺序错了 = 白屏/花屏然后怪板子。

## 2. 标准流程（每次断电后照做）

1. **上电前接线**（按《硬件连接说明》第 2 节核对）：
   - 电源 12V 3A（J9=REG，极性核对过）
   - TF 卡（断电插卡，插完再上电）
   - Micro-USB（PROG + 串口，COM4/FTDI）
   - **网线（RJ45 → 路由器/交换机，或插环回头）—— 🔴 必须插。不插 → 输出周期性跳锁（见 §2.1）**
   - HDMI 输出线 → 采集卡 → 电脑（自测/输入版都要）
   - **输入版再加**：电脑 HDMI 输出 → 板子 J10
2. **上电**，等 LED0 亮 = 时钟锁定（自测版 = 板内 MMCM 锁；输入版 = 输入时钟恢复锁）
3. **重载 bit**（二选一，见 §3）
4. 确认画面正常后，**再插 HDMI 输入线**（输入版）
5. 看画面：黑底白块+红框（自测版）／真实画面里目标被红框框住（输入版）
6. 断电重启验证：**连测 3 次**，每次结果一致才算过（§5.1 验收 4 的判定标准）

## 2.1 🔴 网线是硬条件，不是可选项（2026-10-20 实测确立）

**不插网线，PYNQ-Z2 的板载 125 MHz 参考时钟不稳**，导致视频输出周期性跳锁：画面在
「纯黑 / 采集卡报 *Video Format Not Supported* / 正常」三态间约 10 秒一轮跳变，
正常画面每分钟只出现 4–5 次。**插上网线后 60 秒采样 61/61 全亮，跳锁彻底消失。**

机理（`INPUT_SEL=1` 输入模式）：

```
125 MHz(sys_clk, H16) ──clock_200m(VCO 1000MHz)──▶ 200 MHz RefClk
        └─▶ dvi2rgb IDELAYCTRL 相位对齐 ──▶ pLocked ──▶ 整条链（输出也跟它走）
```

输入模式下流水线与 rgb2dvi 跟 dvi2rgb 恢复的 PixelClk 走（`board_top.v:85`），
本地 74.25 MHz 那组不参与，故 125 MHz 影响链路的唯一通路就是 `clock_200m → RefClk`。

- 抖动小 → 数据眼够宽 → 锁定稳（**这解释了为何 10-12 曾连续 PASS 数轮**）
- 抖动漂大 → 眼不够宽 → 相位对齐周期性失败重锁 → 采集卡锁不上格式

**属余量（margin）问题，非硬件损坏**：抖动随温度 / 12 V 供电 / 连续运行时长漂移，
故"同一块 bit 昨天好使今天抽风"。完整定位过程见
`docs/hdmi-lock-instability-postmortem-20261020.md`，实测数据见 `board/logs/board_test_20261020.md`。

> 同源病例：PYNQ 官方论坛 `HDMI output signal issue on the Z2`（2019），
> darren 原话 *"the 125MHz clock isn't stable unless I have the ethernet connected or a loopback plug inserted"*。

### 2.1.1 环回头（loopback plug）替代网线 —— 更便携，但需实测

不想拖一根网线到路由器时，可用 RJ45 环回头插在板子网口上，让 PHY 认为链路已建立。
（引脚编号：水晶头金属触点朝自己、卡扣朝下，从左往右 1~8）

| 目标速率 | 短接引脚 | 说明 |
|---|---|---|
| 10/100M | **1↔3、2↔6** | 只环回发送/接收两对 |
| 千兆 | 1↔3、2↔6、**4↔7、5↔8** | 四对全环回 |

⚠ **已知风险（务必实测）**：千兆 PHY 带 **NEXT（近端串扰）检测**，可能把环回头判定为"极端串扰"而拒绝建立链路，
表现为插上后网口灯不亮。公开资料显示此现象在千兆网卡上常见（部分网卡驱动/BIOS 也不提供关闭 NEXT 的开关）。

**建议**：花 5 分钟试一下——先做千兆版（四对全环回），不行再试百兆版（只 1↔3、2↔6）。
成功则演示/录视频时不必拖网线；不成功就回到"接路由器"，两者效果等价（目标都是让 PHY link up）。
判定标准与网线完全相同：**看板子 RJ45 的 link 灯是否常亮、LED0 是否常亮**。

## 3. bit 重载两条路（任选）

| 方式 | 步骤 | 适用 |
|---|---|---|
| **A. Vivado Hardware Manager（推荐）** | Open Target（Micro-USB，自动识别）→ Program Device → 选 bit 文件 → Download | 有电脑、有 Micro-USB 线；下载完立即生效，不依赖网络 |
| **B. 走网络（Jupyter）** | 资源管理器 `\\192.168.2.99\xilinx` 拷 bit（账号密码均 `xilinx`）→ 浏览器 `http://192.168.2.99:9090`（密码 `xilinx`）→ `from pynq import Overlay; Overlay('board_top_xxx.bit')` | 板子已联网、嫌 Vivado 慢；纯 PL bit 不需要 hwh |

bit 文件（构建产物，已入库 `build/bitstream/`）：

| bit | 对应模式 | 现象 |
|---|---|---|
| `board_top_selftest.bit` | INPUT_SEL=0 自测 | 黑底白块被红框框住 |
| `board_top_hdmiin.bit` | INPUT_SEL=1 真实输入 | 真实画面里运动目标被红框框住 |

## 4. 演示纪律（黄项 7：热插拔）

- **先断电，再拔插**：TF 卡、HDMI 线、电源——任何线缆插拔前先断电（文档已警告带电不插）
- **运行中不要拔 HDMI 输入线**：要拔也行——输入版做了无信号兜底（拔线 0.1s 内黑屏不花屏），但**演示时主动拔线仍按"先断电"处理**，别在现场练胆
- 现场演示前：**完整走一遍本 SOP 并确认画面**，再上台

## 5. 诊断对照（出问题先看灯）

| 现象 | 先查 |
|---|---|
| LED0 不亮 | 时钟没锁：输入版 = 电脑 HDMI 没输出/线没插好/J10 接触不良；自测版 = 板内 MMCM 异常 |
| LED0 亮但花屏 | 输入信号不是 720p（EDID 锁的是 720p 首选时序）；换信源/换线 |
| 画面黑屏 | 拔线兜底生效中：插回 HDMI 输入线 |
| 画面周期性黑/闪（约 10 秒一轮）、采集卡报"格式不支持" | **网线没插**（§2.1）——125 MHz 不稳导致输入相位对齐反复重锁 |
| LED0 周期性闪/灭 | 同上：pLocked 反复重锁。先查网线，再查 12 V 供电与板子温度 |
| 一切正常但没检测框 | LED1（检测到目标）亮不亮；目标太小/阈值（THRESH=70）不合适 |

## 6. 可选路线（暂不实施，留档）

把 bit 固化到 QSPI（`set_property BITSTREAM.CONFIG.CONFIGRATE ...` + `write_cfgmem`，或 Vivado 里 Program Configuration Memory Device），断电后板子自启、无需电脑。**好处**：现场断电重启零依赖；**代价**：QSPI 分区覆盖有风险，需专门一次验证。比赛演示前若有富余时间再评估。

## 7. 来源

- 《硬件产品级审查与 HDMI 输入方案_20261011.md》§5.2 下板操作步骤 / §5.1 验收 4 / 红项 3 / 黄项 7
- 《硬件连接说明_20261011.md》第 2 节接线
- 构建提交：`b7656a8`（两版 bit 已重建为正确配置——注意 `f7d7088` 时代两版 bit 用逗号格式绑定失败、同为默认配置，已废弃；WNS 自测 0.800 / 输入 0.932）


---

## S3  PYNQ SD 卡路线（PS 后备/主力路径；2026-10-21 建立）

### S3.0 为什么有这一节
- 我们原架构是 INCLUDE_PS=0 纯 PL。要把 PS 用起来（FCLK 摆脱以太网 PHY 的 125MHz 坑、PS 接管 track/uart、PS 跑 OpenCV），必须先让 PS 启动。
- **Vitis 2026.1 禁用了 XSCT**（`xsct.bat` 直接报 `XSCT is disabled in Vitis 2026.1 release`，注意退出码仍是 0），`vitis-run.bat` 只是 HLS 入口不是 Python Console。**命令行建裸机工程这条路在 2026.1 断了。**
- → 改走 **PYNQ 官方 SD 卡镜像**：自带 FSBL + U-Boot + Linux + Python + OpenCV，**不需要 Vitis**。

### S3.1 硬件与工具（★ 2026-10-03 已全部实测通过，权威源：skill/pynq_overlay_bringup/README.md）
- **一根 Micro-USB 搞定三件事：供电 + JTAG + 串口**（FTDI FT2232HL，`VID_0403+PID_6010`，COM4，序列号 `1234-TULB`）。**不需要网线、不需要显示器。**
- SD 卡（10-03 实测用 16GB）+ 读卡器
- 写卡工具：**Rufus 4.9 → 必须选「DD 映像」模式**（分区模式会失败）；10-03 实测耗时 **05:37**
- 镜像：`D:\FPGA\images\pynq_z2_v3.1.1.img`（7,951 MB，**本机 2026-09-28 就位，别再下载**）

### S3.2 烧卡判据（别看容量，容量会骗人）
- 写完后 Windows 只显示一个 **0.13 GB** 的 FAT 分区是**正常**的（另有一个 ext4 rootfs 分区 Windows 不认，开机后自动扩到整卡，10-03 实测扩到 14G）
- 判成功看：**卷标变为 `PYNQ`** + BOOT 分区含 `BOOT.BIN` / `image.ub` / `boot.py` / `boot.scr` / `REVISION`

### S3.3 跳线与接线（★ J9，不是 JP6——2026-10-21 我曾写错）
- **JP1 → SD 启动**
- **J9 → USB 供电**（走 12V 适配器时另选 REG）
- Micro-USB 接电脑 PROG/UART 口
- **读卡器：先插卡再插 USB**（顺序反了设备不重新枚举，表现为"盘符不出现"）

### S3.4 登录与校验（10-03 实测判据：不看报错，只看可核验数据）
- 串口 **115200-8N1**，**自动登录**（直接落到 `xilinx@pynq:~$`，无需账号密码）
- 板子默认静态 IP `192.168.2.99`，Jupyter 端口 `9090`；**没插网线时 eth0 = NO-CARRIER / state DOWN，属正常**
- | 查什么 | 期望值 |
  |---|---|
  | `pynq.__version__` | `3.1.1` |
  | 加载后 `ip_blocks` | base = **21** |
  | `/sys/class/fpga_manager/fpga0/state` | `operating` |
  | 肉眼 | 4 个 LED 灭 1 秒 → 闪 4 下 → 停在亮 |

### S3.5 加载我们自己的 bit
- PYNQ 3.x：`from pynq import Overlay; ol = Overlay("design_1_wrapper.bit")`（需同目录同名 `.hwh`）
- **命令行跑代码必须先 source 两行，且绝不要 sudo**（症状极易被误判成权限问题，10-03 踩过）：
  `source /etc/profile.d/pynq_venv.sh; source /etc/profile.d/xrt_setup.sh`
  然后 `/usr/local/share/pynq-venv/bin/python3 xxx.py`（**Jupyter 里不需要**，内核自己注入环境）
- ★ **PYNQ 路线下 FSBL/U-Boot 会配好 PS 的 PLL，FCLK 必然有输出 → 125MHz/PHY 时钟坑自动绕过**

### S3.6 与 ps_probe 探雷的关系（两条路别混淆）
- **JTAG 直烧路线**（`burn_ps_probe.tcl`，不跑任何 PS 软件）：LED0 闪 = FCLK 白给；灭 = 必须软件启动 PS。**这才是探雷实验。**
- **PYNQ 路线**：PS 必然起来、FCLK 必然有，是保底可通路径。
- ★ 关键洞察（10-03 技能包「失效条件」）：**加载纯 PL bitstream（没实例化 PS）时，PYNQ 的串口这条路用不上** —— 没有 PS 在跑，不会有点位打印，只能看 LED 与 HDMI。**这正是我们 board_top（INCLUDE_PS=0）一直只能用 JTAG 烧 + 采集卡看结果的原因。**
  反之 **ps_probe 例化了 PS，加载后串口立刻有输出** → PYNQ 路线下它比 LED 更早给出"PS 活着"的证据。
- PYNQ 路线真正价值：自带 Python + OpenCV → 黄金参考比对、演示可视化、参数在线调参。
