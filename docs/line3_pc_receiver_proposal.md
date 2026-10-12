<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4; scope: engineering instructions, no invented metrics. -->

# 电脑端接收与画框：可运行的协议提案

> **状态（2026-10-12）**：本文为 2026-10-10 的**草案历史**，回传协议已于 `main@f15fbce` **定稿生效**（UART 115200 + 帧头/目标/事件三包 0x5A/0xA5/0xC3，BBOX 快照 0x1C 起）——接收端请以 `docs/protocol_and_interface_requirements.md` 为准，本草案仅作背景。

2026-10-10。用户确认队友尚未提供板端回传方式和包格式，先完成电脑端模拟接收与画框。本工具没有改动 `docs/interface_freeze_table.md` 或任何 RTL。

已完成的是电脑端接收、数据检查、按编号画框和证据保存。两个独立 Python 进程通过本机 TCP 发送、接收了60帧模拟目标数据，编号、坐标、原始字节和60张输出图片均经过核对。最终检查23/23通过。图上写有 `SIMULATED INPUT | NOT A BOARD TEST`。

这不是板卡回传测试。背景是坐标画布，尚未与摄像头或输入视频同步。网络抓包也不能单凭数据里的来源字段证明来自板卡。串口适配尚未实现，需先拿到队友协议。

## 直接运行

以下命令从仓库根目录运行。本机 Python 为 `D:/666666/Anaconda/python.exe`，需有 NumPy、OpenCV。输出目录必须是新的，程序不覆盖已有结果。

最快检查（无需板子，不弹窗）：

```powershell
& 'D:/666666/Anaconda/python.exe' -X utf8 sim/line3/check_pc_receiver.py --out 'D:/line3_receiver_check_new'
```

若想看到接收窗口，在第一个终端启动接收程序：

```powershell
& 'D:/666666/Anaconda/python.exe' -X utf8 sim/line3/pc_receiver.py --listen --port 8765 --out 'D:/line3_receiver_demo_new' --show
```

看到 `LISTENING` 后，15秒内在第二个终端发送模拟数据：

```powershell
& 'D:/666666/Anaconda/python.exe' -X utf8 sim/line3/pc_receiver_simulate.py --port 8765 --frames 60 --record 'D:/line3_receiver_sent_new.jsonl'
```

模拟器会快速发送；窗口随接收结束关闭，图片保留在输出目录。可省略 `--show` 只保存图片。也可用 `--file` 重放已保存的 JSONL 文件。

默认只监听 `127.0.0.1`，供本机检查。默认接收一条连接，15秒无数据结束；最多接收1000帧、64MiB原始流，超限非零退出。`--timeout`、`--max-frames`、`--max-bytes` 可显式调整。缺帧、重复帧、乱序、坏包、空流、未完整结束的行都会导致非零退出，详情保留在 `summary.json`、`rejected.jsonl`。`raw_stream.bin` 保留收到的字节；超过总字节上限的最后一块不落盘。

## 拟定的数据格式

这只是电脑端适配层的 JSON Lines 提案，每帧一行 UTF-8 JSON，必须以换行符结束。TCP 可以拆包、粘包，接收器自行拼接。单行上限65,536字节；超长行丢弃到下个换行，随后恢复解析。

```json
{"version":1,"source":"simulated","frame_id":1,"width":640,"height":360,"coordinate_space":"i3-2x","targets":[{"id":1,"valid":true,"x1":33,"y1":90,"x2":63,"y2":160}]}
```

| 字段 | 本提案的约定 |
| --- | --- |
| `version` | 整数1 |
| `source` | 默认只接受 `simulated`；显式 `--source board-unverified` 仅改变来源标记，仍不算板测证据 |
| `frame_id` | 0至2³²−1，严格递增；本提案不自动处理计数器回卷 |
| `width`、`height` | 固定640、360，沿用冻结表I2/I3坐标域 |
| `targets` | 每帧完整目标列表，最多256项；空列表表示本帧没有目标 |
| `id` | 0至255，同一帧不能重复 |
| `valid` | JSON布尔值；false的项不画框，但字段和坐标仍要合法 |
| `x1/y1/x2/y2` | 整数，0起点、右下端点包含在框内，不能倒置或越界 |

“每帧列表”、帧号、传输来源及端点包含关系是本提案新增的封装约定，未经队友确认。冻结表I3并没有完整定义传输封包，不能把这里的约定当成板端已经支持的接口。

大像素坐标放大两倍：左上角为 `(2*x1, 2*y1)`，右下角为 `(2*x2+1, 2*y2+1)`。1280×720坐标画布上方另留48像素提示栏，因此输出PNG为1280×768；目标不被提示栏遮挡。没有报警位、时间戳或CRC字段；本提案只验证目标元数据传输，不能验收报警或端到端延迟。

## 队友接入前需要提供

请提供实际串口或网口连接方式、帧边界与目标列表结束语义、字段位宽/字节序、坐标端点含义、编号是否来自跟踪、复位/回卷规则，以及一份原始输出样本。拿到后在线三适配层转换，不私改冻结接口。若实际连接为串口，应先根据真实包格式补串口适配，再复用这里的验证与绘图。

真实联调记录应包含板卡、bitstream/源码版本、连接参数、原始接收流、连续帧号、目标身份和可对应的视频帧。板端功能和完整视频链路仍由线一/线二协同确认；这次电脑端测试不能代替他们的上板记录。
