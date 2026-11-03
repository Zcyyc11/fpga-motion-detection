# r3 视频链路、播放与采集代码

本页对应 `deliverables/tier1_attach_hdmi_r3/`。以下工具负责信源播放和采集查看，不烧录 FPGA，不生成最终参赛剪辑，也不负责连续录像。

## 硬件视频链路

```text
PC HDMI（1280×720@60Hz） → J10 → dvi2rgb
 → hdmi_in_ctrl 坐标/帧首 → gray_conv 灰度 → Tier1 检测与多框叠加
 → rgb2dvi → J11 → 显示器 / USB 采集卡 → PC 预览或截图
```

| 代码 | 职责 |
| --- | --- |
| [combined_top.v](../deliverables/tier1_attach_hdmi_r3/FPGA/src/rtl/board/combined_top.v) | HDMI 收发 IP、恢复像素时钟、检测与 Attach 外设的板级连接 |
| [hdmi_in_ctrl.v](../deliverables/tier1_attach_hdmi_r3/FPGA/src/rtl/board/hdmi_in_ctrl.v) | 输入数字视频的坐标与帧首恢复 |
| [gray_conv.v](../deliverables/tier1_attach_hdmi_r3/FPGA/src/rtl/board/gray_conv.v) | RGB 转灰度 |
| [tier1_md_pipeline.v](../deliverables/tier1_attach_hdmi_r3/FPGA/src/rtl/tier1_md_pipeline.v) | 背景建模、差分、固定阈值、滤波、多框与叠加 |
| [attach_z2_interaction.v](../deliverables/tier1_attach_hdmi_r3/FPGA/src/rtl/attach_z2_interaction.v) | 数码管、8 灯 WS2812、蜂鸣器、模式显示 |

输入链路使用 HDMI 恢复的像素时钟，无输入缩放器、无 DDR 视频帧缓存。输入须由操作系统设为 720p60。
`combined_top.v` 直接实例化 `tier1_md_pipeline`（INPUT_SEL=1）。包内 `md_pipeline.v` 是 INPUT_SEL=0 的内部测试图案兼容封装，不在当前外部 HDMI 路径中。
参数为背景模式、THRESH=100、SHIFT=6、Q4、前景 SHIFT=10、FILTER_MODE=1。
模式显示预置 70/90/45/35 不会改变实际检测阈值。LCD 为空闲占位，触摸/传感器采集未实现；编码器/五向键在顶层固定为 0，不能宣称可用其调参。
背景初始化包含运动目标时可能有残影，框存在帧间发布延迟，不能保证与高速目标逐像素重合。

r3 修正在 `FPGA/board/pynq_z2_combined.xdc`：九位数码管的位选反向映射，修复左右镜像，未因此改变检测 RTL。
本次通过独立目录提供 r3，未改仓库原 `src/rtl/md_pipeline.v` 或原冻结接口。
旧 UART、PS/AXI/HWH 文档属于其他工程路径，不是当前 r3 的可用接口。

## 安装与连接

Windows、Python（源码包建议 3.10）、OpenCV、NumPy；视频文件由使用者提供。
在仓库根目录执行：

```powershell
cd deliverables/tier1_attach_hdmi_r3/VideoTools
python -m pip install -r requirements.txt
```

先通过 Vivado Hardware Manager/JTAG 加载 r3 bit。PC HDMI 输出接 J10，J11 接 USB 采集卡，采集卡 USB 接 PC。
Windows 显示模式设为“扩展”，板卡对应屏幕设为 **1280×720、60 Hz**。
以下 `(2560, 0)` 仅为扩展屏坐标示例，设备编号 `1` 也仅为示例；按本机实际布局和设备修改。
同一采集卡通常只由一个脚本占用，运行另一个前先关闭当前采集程序。

## 四个脚本

| 脚本 | 作用 | 退出/操作 |
| --- | --- | --- |
| `play_test_video.py` | 循环播放视频到扩展屏；可指定坐标、尺寸和内容更新 fps | Esc |
| `live_view_board.py` | 同时送视频、预览采集卡、保存快照 | s 截图；q 退出 |
| `preview_capture.py` | 单独预览采集设备 | Q / Esc |
| `check_hdmi_input.py` | 根据分辨率、平均亮度、帧间差提示可能的信号问题 | 完成指定帧检查后退出 |

独立播放：

```powershell
python play_test_video.py --video "./test.mp4" --x 2560 --y 0 --w 1280 --h 720 --fps 30
```

**`--fps 30` 控制视频内容的播放节奏，不设置 HDMI 刷新率。** 即使内容 30 fps，Windows 的输出模式仍应为 720p60。
未指定屏幕坐标时，独立播放器尝试选择首个非主屏；多屏环境建议显式给坐标。

同时播放、预览和截图：

```powershell
python live_view_board.py --video "./test.mp4" --dev 1 --x 2560 --y 0 --shotdir "./captures"
```

此脚本没有定帧率播放或采集同步；采集阻塞会影响播放速度。预览及截图会缩放为 1280×720，
因此截图不能证明采集设备原始分辨率，也不能据此严格测量端到端延迟。
两个播放脚本省略 `--video` 时默认使用当前工作目录的 `vehicles.mp4`，素材未随源码提供。

仅采集预览：

```powershell
python preview_capture.py --device 1 --label "Tier1 HDMI r3"
```

省略 `--device` 会在 0–3 中尝试首个可出图设备，可能选到电脑摄像头；请先确认画面来源。

信号检查：

```powershell
python check_hdmi_input.py --device 1 --width 1280 --height 720 --thresh 100
```

这里 `--thresh 100` 是**采集平均亮度阈值**，与 FPGA 的检测阈值无关。
READY、暗场、静态、疑似桌面等输出仅用于排查；暗视频、静态画面和板卡透传桌面都可能影响判断，不能直接推定线缆错误或认定板测通过。
`--preview` 会把窗口放到 `(2560, 0)`，可能遮挡信源屏上的视频；上述环回示例不启用它。

## 验证边界

本次同步验证 105 文件与整理包逐字节一致、7 个 Python 语法、4 个工具 `--help`、说明链接和 bit 哈希。
已有证据包括工程创建和原 r3 物理构建；本次未重新跑综合实现、未执行 GUI 播放/真实采集、未新增完整实板验收。
数字视频仿真使用接收 IP 与时钟替代模型，不能代表 TMDS 电气链路和稳定性。
断线重锁、重复上电、外设显示、车辆框对齐及至少 10 分钟稳定性，仍由持板方记录当前 bit 哈希后测试。
详见[版本与验证证据](../report/r3_update_20261103/README.md)。
