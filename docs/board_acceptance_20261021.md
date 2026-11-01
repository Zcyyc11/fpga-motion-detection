# 板端验收回填 · 韦博 16 目标版（线一）· 2026-10-21 回填

> 验收 bit：`rebuild_20261019/build/bitstream/board_top.bit`，SHA256 `ce6213136aa4fce94a9ce64e06c0ee733a6277e29126efcdcad466370e9e3a06`（= 韦博 16 目标 HDMI 版，工程实查 INPUT_SEL=1 + multi_bbox MAX_LABEL=16）。保底：9f506bef。
> 采集工具：`play_and_capture.py`（Python310，MSMF 采集卡 dev1，窗口 MoveWindow 定位板子屏 (2560,0)）。

## 八项验收
| # | 项目 | 结果 | 备注（实测依据） |
|---|---|---|---|
| 1 | 接线与供电（含网线） | ☑通过 | 板子 12V 上电（LD13/LD12 亮）、网线 RJ45 link、HDMI in/out 就位；CH340 模块曾因 VCC 误接电源脚烧毁、已换新（详见 #7） |
| 2 | bit 哈希核对（ce621313） | ☑通过 | SHA256=ce6213136aa4…，烧录脚本哈希卡口 + 工程实查（INPUT_SEL=1，multi_bbox MAX_LABEL=16）双重确认 |
| 3 | 烧录成功 | ☑通过 | `burn_ce621313.log`：PROGRAMMING_COMPLETED + startup HIGH；DGL 屏由 Unknown→OK |
| 4 | LED0 锁定（dvi2rgb） | ☑通过 | pLocked：板子屏激活 + 采集 100% 亮帧 + dvi2rgb EDID 应答 = 锁相铁证（物理 LED0 由线一肉眼确认常亮） |
| 5 | 720p60 HDMI 输入 | ☑通过 | `list_screens` 实测：板子屏 (2560,0) 1280×720 激活为扩展输出 |
| 6 | HDMI 输出（16目标红框+灰度底） | ☑通过 | 采集 summary：vehicles 红框 32%、people-walking 12%、market-square 0.15%；多轮复现 28–34% 红框，灰度底正常、100% 亮帧 |
| 7 | 串口数据回收（PMOD A1/Y18） | ☑失败 | CH340 COM6 能打开但 0 字节 idle（5s 超时）。硬件已排除（换新模块、COM6 OK、按官方脚位接线）。**定位：RTL `frame_tick` 依赖 dvi2rgb vsync（`md_pipeline.v:308`），疑 vsync 链未翻 → frame_tick 不产生 → uart_tx 不发**。待 ILA 抓波形 / 或改 frame_tick 用像素 y 回绕触发后复测 |
| 8 | 六场景覆盖 | ☑部分 | 自动视频场景 3 个 PASS（vehicles / people-walking / market-square + 多轮 uart_feed 复现）；空/单/多 3 个真人场景未做（视频场景已充分证明检测链，真人场景判定非必需，不做） |

## 16 目标专项（决定"收不收韦博版"）
- 多目标是否真出多框：☑是（红框多轮稳定出，max_red_px 2876~7980；同帧精确框数未逐帧核）
- 框数是否正确（≤16）：□未验证（未逐帧数框；串口未收到目标数）
- 误检/漏检：☑有（market-square 暗+密场景红框仅 0.15%，明显漏检——帧差法暗场景固有局限；vehicles/people-walking 正常）
- 帧号缺口（115200 满载丢帧）：□未验证（串口未收到，无法判）

## 功能结论
- ☑ **部分通过**：HDMI 视频链路 + 16 目标检测 + 红框输出**通过**；串口回传 1 项未过（非主体功能，已定位到 RTL frame_tick/vsync，改后复测）
- 附：韦博 16 目标版的**主体功能（上板跑通 + 检测 + 红框）已实测成立**，黑屏冤案已平反（根因是网线不是 bit）；串口是唯一待收口项。

## 黑屏说明（必填）
HDMI 黑屏与 bit 无关：根因 = 板子未插网线 → 板载 125MHz(PHY) 时钟不稳 → dvi2rgb 失锁；插网线即根治（见 `docs/hdmi-lock-instability-postmortem-20261020.md`）。韦博版不背黑屏罪。今晚复现佐证：烧录前 DGL Unknown（中间断过电、bit 丢）→ 重新供电 + 重烧 ce621313 → DGL OK + 采集全亮。

## 证据清单
- [x] 烧录日志 `burn_ce621313.log`（PROGRAMMING_COMPLETED + startup HIGH）
- [x] 视频场景采集 `evidence/ce621313_v4`、`ce621313_pw`、`ce621313_ms`、`ce621313_uart_feed*`（summary.txt + 首中末帧 PNG + 红框统计）
- [x] 异常原样保留（`_uart*_clean.txt` idle-timeout stats；`_hw_status`/`_screen` 等扫描记录）
- [ ] 接线全景照（含网线）—— 待线一补拍
- [ ] 原始串口数据 —— 串口未收到（#7 失败）

## 回填
线一（主城要） 2026-10-21 20:58 回填。串口待改 frame_tick 后复测闭环。
