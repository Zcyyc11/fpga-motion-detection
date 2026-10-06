# Skill 1 · PYNQ overlay 上板加载与校验流程

## 适用范围

- **什么条件下能用**：PYNQ 系列板卡（本项目为 PYNQ-Z2 / XC7Z020-1CLG400C）+ **PYNQ 3.1.1 镜像**
  （`pynq_z2_v3.1.1.img`，内核 6.6.10-xilinx-v2024.1，对应 Vivado 2024.1）+ 一根 Micro-USB 线
  （FTDI FT2232HL，一根线同时供 **供电 + JTAG + 串口**）。不需要网线、不需要显示器。
- **解决什么问题**：把板子从"刚拿到手"推进到"**确认 overlay 真的加载成功**"，
  并给出一条**不看报错、只看可核验数据**的判据。

> 这是官方硬门槛「须板上跑通实测、不收纯仿真」的第一步 —— 先证明 PS→PL 链路是通的。

## 使用方法

1. **烧卡**：Rufus 4.9 → 选 `pynq_z2_v3.1.1.img` → **必须选「DD 映像」模式**（分区模式会失败）→ 开始。
2. **插卡拨跳线**：SD 卡槽在板子**底面**（SD1）；`JP1` 拨到 SD 启动；`J9` 拨 USB 供电。
3. **接线上电**：Micro-USB 接电脑（供电+JTAG+串口）。
4. **登录**：串口 **115200-8N1**，**自动登录**（直接落到 `xilinx@pynq:~$`，无需账号密码）。
5. **加载 overlay**：base overlay 在 `/home/xilinx/pynq/overlays/base/`（`base.bit` + `base.hwh` 齐全）。
6. **校验（关键一步，别只看有没有报错）**：
   | 查什么 | 期望值 |
   |---|---|
   | `pynq.__version__` | `3.1.1` |
   | 加载后 `ip_blocks` 个数 | base = **21** |
   | `/sys/class/fpga_manager/fpga0/state` | `operating` |
   | 肉眼可见 | 4 个 LED 灭 1 秒 → 闪 4 下 → 停在亮 |

- **关键参数说明**：
  - 串口：115200-8N1，本板 COM 口认 **FTDI `VID_0403+PID_6010`**（本机为 **COM4**，序列号 `1234-TULB` 是该板出厂烧的）
  - 板子默认静态 IP `192.168.2.99`；Jupyter 端口 **9090**
  - 命令行跑代码前：见下「从哪些失败总结」第 1 条

## 已验证的效果

- **测试环境**：PYNQ-Z2 / 镜像 `pynq_z2_v3.1.1.img` / PYNQ 3.1.1 / 内核 `6.6.10-xilinx-v2024.1` (armv7l)
- **结果**：**2026-10-03 一晚走通全部六步**
  - 烧卡：Rufus 4.9.2256，设备 `NO_LABEL (E:) [16 GB]`，**耗时 05:37**，卷标由空白变为 `PYNQ`
  - 开机并串口登录成功（`xilinx`，自动登录）
  - base overlay：**`OVERLAY_OK`，`ip_blocks = 21`**，`fpga0/state = operating`
  - 可见验证：**`leds= 4` / `BLINK_DONE`**（4 个 LED 灭 1 秒 → 闪 4 下 → 停亮）
  - 附带实测：`REVISION = Release 3.1 (Carlisle) 2025_09_24 1d2ac96`；eth0 = `192.168.2.99/24` 且 `NO-CARRIER / state DOWN`（没插网线，符合预期）；rootfs 已自动扩到整卡（14 G，已用 5.9 G，余 7.4 G）
- **证据文件**：本仓库 `board/logs/`；`board/overlay/`（交付 overlay 的落点）

## 从哪些失败或观察中总结得出

1. **现象**：命令行跑 `python3 xxx.py` 时 `pyxrt.device(0)` 报
   `Could not open device with index '0'`；**加了 `sudo` 仍然报同样的错**（所以极易误判成权限问题）。
   **原因**：不是权限 —— PYNQ 3.1.1 的 XRT 运行环境靠**环境变量**注入，`sudo` 反而把当前环境清掉了。
   **结论**：命令行必须先
   `source /etc/profile.d/pynq_venv.sh; source /etc/profile.d/xrt_setup.sh`，
   且**不要用 `sudo python3`**，要用 `/usr/local/share/pynq-venv/bin/python3`。
   Jupyter 里不受影响（内核自己注入了环境）。
2. **现象**：读卡器插上电脑后"设备不出现"（物理层看不到 USB 盘）。
   **原因**：先插 USB、后插卡，读卡器没有重新枚举。
   **结论**：**先插卡再插 USB**；不行就换端口。
3. **观察**：烧完卡后 Windows 只显示一个 **0.13 GB** 的分区，剩下 ~8 GB"不见了"，一度以为烧写失败。
   **原因**：另有一个 **ext4** rootfs 分区，Windows 不认。
   **结论**：判烧写成功看 **卷标是否为 `PYNQ`** + **BOOT 分区内容**是否为标准 PYNQ
   （`BOOT.BIN` / `image.ub` / `boot.py` / `boot.scr` / `REVISION`），
   **不要以"总容量对不对"为准**。

## 失效条件

- **PYNQ 版本变了**：2.7 及更早没有 `/etc/profile.d/xrt_setup.sh`，`pynq_venv.sh` 路径也不同 →
  source 这两行会报"找不到文件"，表现为 `pyxrt` 依旧报 `Could not open device`。
- **走 Jupyter 时**本流程的 source 步骤不适用（环境由内核注入），照抄反而多此一举。
- **非 FTDI 串口芯片的板子**：COM 口号与 VID/PID 都不同（本板是 `VID_0403+PID_6010`），需重新认口。
- **已知未覆盖的边界**：本流程只证明「**overlay 能加载、PL 被配置**」。
  若加载的是**纯 PL 的 bitstream（没有实例化 PS）**，则**串口这条路用不上** ——
  没有 PS 在跑，不会有点位打印，只能看 LED 与 HDMI。
  **「overlay 加载成功」≠「PS 侧程序能跑」≠「算法算得对」**（后两者分别需要本技能包第 3 项与板卡实测）。
