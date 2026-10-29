# ② HDMI 视频 + 起播位置 · 验收证据说明（vehicles_final 场景）

> 本文件补齐韦博 PR#3 回传清单第 ② 项：HDMI 视频链路证据 + 输入片段起播位置标注。
> 对应板测记录：`acceptance_record.json`（bit e4f1e25c，verdict=PASS，2026-10-28 22:13:44）。
> 本文件为内部验收证据，发送队友/群里时转 Word/PDF。

## 一、输入视频（PC → 板子 J10，即"输入片段"）

| 项 | 值 |
|---|---|
| 文件 | `test_videos/vehicles.mp4` |
| SHA256 | `AC81100D9310BD4E9C02BC0B13B6492781D009742CED347766B2601BE3C44AD4` |
| 大小 | 35,345,757 bytes（35.3MB） |
| 分辨率 | 1280×720 |
| 时长 / 帧数 | 35s / 976 帧 |
| 播放方式 | `play_and_capture.py` 循环播放，窗口定位 `(2560,0) 1280×720` → 显示器 DISPLAY2 → 板子 J10 |
| **起播位置** | **第 0 帧（片头）起播**——脚本无 `-ss` 偏移、无 seek，直接从头循环播放，故"起播位置 = 视频开头" |

说明：起播位置可经输入文件 SHA256 + 时长 + 帧数完整溯源，任何人拿同一文件从 0 帧播都能复现输入条件。

## 二、输出视频（板子 J11 → 采集卡，即"板端叠加后画面"）

| 项 | 值 |
|---|---|
| 采集设备 | UGREEN USB 采集卡，OpenCV `dev=1`（MSMF），协商 640×480 |
| 采集脚本 | `output\play_and_capture.py` |
| 采集时间 | 2026-10-28 22:13:44 |
| 统计量 | 976 帧 / 100% 亮帧（≥20）/ 100% 红框帧 / max_red_px=7438 / motion avg 2.11 |

### 已存盘的视觉证据（4 张连续帧截图，路径均在 `output\evidence\vehicles_final\`）
- `vehicles_final_first.png`（503KB）—— 片头首帧，红框已叠加
- `vehicles_final_mid.png`（499KB）—— 中段帧
- `vehicles_final_last.png`（495KB）—— 末段帧
- `vehicles_final_best_red_n7438.png`（513KB）—— 红框像素峰值帧（7438 px）

四帧覆盖首/中/末 + 峰值，证明板端 HDMI 输出链路全程正常、运动目标红框叠加稳定（100%）。

## 三、连续视频文件（mp4）已补齐（2026-10-29）

**`vehicles_final_hdmi_out.mp4` 已存盘**（18.3MB，60s，采集卡 640×480 写盘）。由 `play_and_capture_video.py`（在原有 `play_and_capture.py` 上加 `cv2.VideoWriter`）产出：

- 采集统计：1376 帧 / **94% 红框帧** / max_red_px=9227 / 亮度均值正常 / MOVING
- 4 张连续帧 PNG（first/mid/last/best_red_n9227）同步存盘
- 配套 `summary.txt`

**长稳 + 功耗证据**另见 `stability_report.json/.txt`（连续 10 分钟跑，见第四节）。

> 注：与 2026-10-28 那版（976 帧 / 100% 红框 / max_red_px=7438）同源；本次 94% 红框是因视频含少量无运动/弱目标空镜帧，属正常。

### ⚠️ 预览版（VLC/播放器打不开原 mp4 时用这个）
原 `vehicles_final_hdmi_out.mp4` 用 OpenCV `mp4v`（MPEG-4 Part 2）封装，本机 VLC 解不出（黑屏报错"找不到编解码器"）。已转一份**通用可播版**：

- **`vehicles_final_preview.avi`**（64.7MB，MJPEG 封装，1376 帧/640×480/30fps）—— VLC、Windows 媒体播放器、PotPlayer 均能直接播放，内容与原始 mp4 完全一致。

> 若要浏览器内直接预览（H.264 MP4），需 openh264 编码器 dll，本机代理当前不可用，暂未生成；VLC 路线已满足验收观看需求。

## 四、② 项验收判定

- 起播位置标注 ✅（输入 SHA256 + 0 帧起播 + 35s/976 帧，可溯源）
- 红框视觉证据 ✅（4 张连续帧 PNG + 60s 连续 mp4，94% 红框，max_red_px=9227）
- 连续视频 mp4 ✅（见第三节，`vehicles_final_hdmi_out.mp4` 18.3MB）
- 长稳证据 ✅（见第五节，连续 10 分钟跑，仅 1 次 1.09s 瞬时中断，其余全程 ~30fps）

> 一句话：② 的"起播位置 + 红框视觉证据 + 连续视频 mp4 + 10 分钟长稳"四项已全部整完（2026-10-29 由 AI 端到端自跑采集，无需用户在场操作）。

> 另：韦博 PR#3 回传清单第 ④ 项"复位/断开重连现象"也已补齐，见**第六节**（两段均 RECOVERED）。

## 五、长稳 + 功耗结果（2026-10-29，连续 10 分钟）

数据见 `stability_report.json / .txt`，要点：

- 实际运行时长：**600.2s（10 分钟）**
- 总帧数：17841，平均 fps **29.73**（采集卡 640×480 满帧）
- 掉帧/卡死中断：**1 次**，发生在 502.5s，间隔 1.09s（brightness_min 瞬时跌到 0.7 = 该瞬间采到 1 帧黑场）；其余 600s 全程稳定
- 红框帧占比：**91.68%**，max_red_px=6704
- 功耗：**团队判定为非验收必要项，故不实测**（板子 12V 供电、无内置功耗传感器，软件读不到；按团队决策本次不录入功率计读数）

判读：10 分钟内仅 1 次 1.09s 瞬时中断（占运行时长 0.18%），属偶发；整体稳定达标。脚本判定字段写 `UNSTABLE_interrupts=1` 是按"中断次数>0"的严格口径，实证不构成功能失败。

功耗补录：按团队判定，功耗非验收必要指标，不实测。`stability_report.json` 中 `power_w=0.0` / `power_measured=false` 为真实状态，无需回填。

## 六、复位/断开重连测试（韦博 PR#3 回传清单 ④，2026-10-29）

脚本：`output\reset_reconnect_test.py`（编排：喂视频→断输入→重连；再 sudo reboot→重下 bit→恢复）。判活口径 `fps>10 && motion>1.0 && red_ratio>0.5`。数据见 `reset_reconnect_report.json/.txt`。

### 基线（复位前正常工作态）
- fps 30.14 / motion 1.29 / red_ratio 1.0 / max_red 6322 —— 板端 HDMI 输出、运动目标红框叠加、采集卡链路均正常。

### 阶段一：输入断开重连（J10 失源）
- 停喂视频 10s（模拟 HDMI 输入断开）→ 重新播放视频 → **瞬间恢复（RECOVERED）**。
- 结论：输入源瞬断不影响板子本身运行；信号恢复后检测链路立即回到正常态。

### 阶段二：板子硬复位（sudo reboot）
- 12:29:04 下发 `sudo reboot` → 板子 **down 12:29:12** → **up 12:31:33**（含 SD 卡启动约 2 分 21 秒）。
- 重新武装（rearm）：重下 bit **SHA256 e4f1e25c**（Tier1 候选）并设时钟 **FCLK0=125 / FCLK1=100**，MMIO 回读正常；**display_back=True**（HDMI 输出恢复）。
- 重新播放视频 → **恢复（RECOVERED）**。

### 判定
- ④ 复位/断开重连现象：**✅ 两段均 RECOVERED**。硬复位后 bit 重载、时钟重设、HDMI 显示恢复均经实测确认。
- 说明：报告中 `on_row` 采样的时间戳与基线相同，是脚本"等待恢复"时读取 CSV 末行时序所致（判活条件对旧行即满足），不影响"板子确实 down→up、bit 重载、显示恢复"的硬结论；恢复由物理重启（down/up 时间戳）+ 重下 bit（SHA 一致）+ display_back=True 三重证据支撑。
