# 视频播放与采集工具

Windows 上运行，建议使用 Python 3.10。安装依赖：

```powershell
python -m pip install -r requirements.txt
```

将板卡工程生成的 r3 bit 文件通过 Vivado Hardware Manager 的 JTAG 接口下载到 PYNQ-Z2。工具负责视频输出与采集预览，不执行烧录。

连接 PC HDMI 输出至板卡 J10，板卡 J11 至 USB 采集卡，再将采集卡连接到 PC。Windows 显示模式设为扩展，板卡对应显示器设为 1280×720、60 Hz。

在本目录执行，替换视频路径、扩展屏坐标和采集卡编号：

```powershell
python live_view_board.py --video "./test.mp4" --dev 1 --x 2560 --y 0 --shotdir "./captures"
```

按 `s` 保存快照，按 `q` 退出。扩展屏不在 `(2560, 0)` 时，按 Windows 显示器布局修改 `--x`、`--y`。视频文件由使用者提供，本源码包不附带测试视频。

独立播放视频，按 `Esc` 退出：

```powershell
python play_test_video.py --video "./test.mp4" --x 2560 --y 0 --w 1280 --h 720 --fps 30
```

仅预览采集卡，按 `Q` 或 `Esc` 退出：

```powershell
python preview_capture.py --device 1 --label "Tier1 HDMI r3"
```

检查采集信号：

```powershell
python check_hdmi_input.py --device 1 --width 1280 --height 720 --thresh 100
```

检查程序按分辨率、亮度和帧间变化给出提示。暗场景、静态视频或采集卡输出分辨率不同也会触发提示，应结合实际画面判断。检查时先关闭正在占用同一采集设备的其他程序。

两个播放脚本默认读取当前工作目录的 `vehicles.mp4`，也可用 `--video` 指定相对或绝对路径。一体查看工具默认把快照存入当前工作目录的 `captures` 文件夹，可用 `--shotdir` 更改。`preview_capture.py` 不传 `--device` 时会尝试设备 0 至 3。OpenCV 叠加标签使用英文字母与数字，以免出现缺字方块。
