# vehicles_final 场景 · 板端验收证据

对应韦博 PR#3 回传清单 ②（HDMI 视频 + 起播位置）与 ④（复位 / 断开重连现象）。
板子：PYNQ-Z2（XC7Z020-1CLG400C）；验收 bit SHA256 `e4f1e25c`（Tier1 候选）。

## 文件清单
- `HDMI_video_evidence.md` —— 验收证据总说明（起播位置、红框视觉证据、连续视频 mp4、10 分钟长稳、复位 / 断开重连）
- `acceptance_record.json` —— bit 下载 / 时钟（125/100）/ MMIO 回读记录
- `stability_report.json` / `.txt` —— 连续 10 分钟长稳结果（600.2s / avg 29.73fps / 仅 1 次 1.09s 瞬时中断）
- `reset_reconnect_report.json` / `.txt` —— 复位 / 断开重连测试（两段均 RECOVERED）
- `summary.txt` —— 连续视频采集统计
- `vehicles_final_*.png` —— 连续帧截图（首 / 中 / 末 / 红框像素峰值帧）
- `vehicles_final_hdmi_out.mp4` —— 板端 HDMI 输出连续视频（采集卡 640×480，mp4v 封装，60s / 1376 帧 / 94% 红框）

## 如何观看视频
原始 `vehicles_final_hdmi_out.mp4` 为 OpenCV `mp4v`（MPEG-4 Part 2）封装，部分播放器 / VLC 解不出。
本机另存了一份 VLC 可直接播放的镜像 `vehicles_final_preview.avi`（MJPEG 封装，与本 mp4 内容一致）；
若仓库内无该 avi，可用 `output\reencode_mjpeg.py` 由 mp4 重新生成。

## 功耗说明
团队判定功耗非验收必要指标（验收看真实硬件跑通 + 实测 + 声明芯片型号），板子 12V 无内置功耗传感器，
故本次不实测；`stability_report.json` 中 `power_w=0.0` / `power_measured=false` 为真实状态。
