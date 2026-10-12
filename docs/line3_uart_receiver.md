# 线三串口接收与真实样本验收

正式协议入口为 [f15fbce 定稿](protocol_and_interface_requirements.md)。本工具接收
UART 二进制三包，旧 `pc_receiver.py` 保留为 JSONL/TCP 历史模拟入口。

## 安装与最快试运行

在仓库根目录执行。Python 3.11 或以上；无需 Vivado。

```powershell
python -m pip install -r sim/line3/requirements-uart.txt
python sim/line3/check_uart_receiver.py --out D:/uart_check_new
python sim/line3/check_uart_evidence.py --out D:/uart_evidence_check_new
python sim/line3/uart_receiver.py --file D:/uart_check_new/simulated.bin --source simulated --out D:/uart_replay_new --show
```

所有输出目录必须尚不存在。路径含中文可以使用；不要复用历史输出目录。
检查工具生成的是模拟报文；最后一条显示坐标画布和告警，**均不是板测**。

本机本次隔离安装仅补 pyserial：运行前设置
`$env:PYTHONPATH='D:/line3_uart_20261012/deps'`，Python 使用
`D:/666666/Anaconda/python.exe`。其他机器按上面 requirements 安装即可。

## 接真实串口

```powershell
python sim/line3/uart_receiver.py --list-ports
python sim/line3/uart_receiver.py --port COM7 --out D:/uart_board_capture_new --duration 60 --idle-timeout 5 --show --metadata board_capture_metadata.json
```

`COM7` 只是示例，请依据板端接线及设备管理器选择实际端口。不要把本机蓝牙 COM
端口当板卡。串口设置固定 115200、8 数据位、无校验、1 停止位、无流控；工具只读串口。
具体 USB-UART 转接与板端 TX 引脚由线一/线二确认，不猜板卡接线。

默认采集 60 秒，空闲 5 秒判为连接异常；不自动重连或猜测板端复位。
采集中断、按 Esc/Ctrl+C、丢帧、坏包或达到数据上限均记录异常并非零退出。
正常到时仍可能截断包或缺少最后一个目标，出现这种情况应保留本次记录并另开目录重采。
默认最多 10000 帧、16 MiB 原始流；只保存前 100 帧 PNG，但全部帧/事件继续写 JSONL。
可用 `--save-images 0` 只存原始流与结构化记录；`--show` 独立控制实时显示。
画布是 1280×720 坐标区域，上方 80 像素提示，不是同步摄像头/输入视频。

`board_capture_metadata.json` 建议内容：

```json
{
  "operator": "实际操作人",
  "board": "实际板卡及器件",
  "source_sha": "实际构建源码完整 SHA",
  "bit_sha256": "实际烧录 bit 的完整 SHA256",
  "tx_connection": "实际 TX 引脚、转接器、COM 端口",
  "input_video": "输入视频文件及 SHA256",
  "frame_mapping": "帧号与输入画面对应方式，注明一帧滞后及复位时点"
}
```

这些是人工声明，程序仅保存，不认证实机来源。没有真实数据时不要把示例占位值当证据。
旧 HDMI bit `9F506BEF4132…` 是 HDMI 功能验证版，不能假定它已含新 UART 通路。

## 解析规则及结果

| 项目 | 行为 |
|---|---|
| 帧头 0x5A / 目标 0xA5 / 事件 0xC3 | 分别 5 / 14 / 8 字节，含末尾校验 |
| 字节序与校验 | 小端；除 CHK 外所有包字节之和取低 8 位，含 MAGIC |
| 拆包、粘包、坏校验 | 保留原始流，逐字节找 MAGIC 重同步；出现异常本次仍判失败 |
| 帧边界 | 新帧头关闭上一帧；最后一帧在采集结束时核对目标数 |
| 目标数量、坐标 | OBJ_CNT 0–16；640×360，含右下端点；不能越界或倒置 |
| FLAGS | 原样保留；线二当前发送 0，0 不表示目标无效；未定义非零值记异常 |
| 帧号 | 16 位，65535→0 接受；重复、倒序、缺帧记错；≥32768 的模差视作倒序/复位歧义 |
| 事件 | TYPE 1 越界、2 停留，独立实时日志及终端提示；归到对应帧 |
| 还原坐标 | 左上 `(2*x1,2*y1)`，右下 `(2*x2+1,2*y2+1)`；覆盖完整 2×2 像素块 |

`raw_stream.bin` 是原始字节；`packets.jsonl` 是成功解码的包（含字节偏移）；
`frames.jsonl` 是全部组装帧（含有效性和问题）；`events.jsonl` 是已关联的事件；
`errors.jsonl` 记录错误；`summary.json` 保存哈希、数量、来源声明与退出码。
PNG 文件名带采集序号和帧号，回卷不会覆盖旧图。

退出 0 仅表示本次接收/解析检查未发现异常；退出 1 表示数据或采集失败；退出 2
表示命令/启动错误。全部模式的 `board_test` 都为 false：实机结论需另做证据核对。

## 收到线二样本后的精确对照

线二提供原始 `.bin`、对应帧号/目标/事件表、输入画面及固件信息。参考表必须独立
来自板端记录或输入对应检查，**不能从本接收器输出复制后再拿来证明自己正确**。
格式为每帧一行 JSON，零目标帧也有记录；顺序和帧数须完全一致。示例：

```json
{"frame_id":12,"input_frame_ref":"input.mp4#frame=13；映射已人工核实","targets":[{"id":7,"x1":10,"y1":20,"x2":30,"y2":40,"flags":0}],"events":[{"id":7,"type":1,"center_x":20}]}
{"frame_id":13,"input_frame_ref":"input.mp4#frame=14；映射已人工核实","targets":[],"events":[]}
```

```powershell
python sim/line3/uart_receiver.py --file board_raw.bin --out D:/uart_real_replay_new --metadata board_capture_metadata.json
python sim/line3/verify_uart_capture.py --capture D:/uart_real_replay_new --expected expected_frames.jsonl --out D:/uart_compare_new.json
```

对照工具重新解析原始流，先核对原始字节哈希及保存的帧表，再逐帧检查帧号、目标 ID、
四坐标、FLAGS、事件 ID/TYPE/中心 X；目标顺序不要求一致，
事件重复次数要一致。输入画面的真实性、帧号映射与延迟需人或独立证据核验。

## 已知协议边界及队友所需输入

- 协议没有事件总数或帧结束包，无法仅凭字节流证明没有整包事件丢失；
  `events_complete` 始终为 false。目标数匹配也不能证明源头没有漏目标。
- 累加校验不是 CRC，无法检测所有多字节抵消错误。错误后重同步只是尽力恢复，
  不能承诺零误判；原始流和失败记录须保留。
- 采集从流中间开始可能出现孤立目标/事件，记录异常；建议板端受控启动并保留复位时点。
- 65536 帧回卷测试使用模拟数据不等于真实持续运行。60 fps 约 18.2 分钟回卷，
  实际帧率以板端为准，线一/线二需提供真实长测。
- 带宽必须结合实际帧率：60 fps、16 目标时仅帧头+目标已为
  `(5+14*16)*60 = 13740 B/s`，超过 115200-8N1 的 11520 B/s；事件还会额外占带宽。
  因此正式文档的“16 目标约 3 KB/s”不能直接用于任意帧率，需板端限速/降帧并留丢包状态。

| 外部交付 | 负责人 | 验收方法 |
|---|---|---|
| 实际接线、最终源码/bit/hash、UART 集成版 | 线一/线二 | 运行记录和原始流配对；不沿用未含 UART 的旧 bit |
| 10/14 零/单/多目标原始报文、帧号映射 | 线二，线一配合 | 新目录重放，精确对照参考表，检查所有错误 |
| 越界/停留事件样本与视频佐证 | 线二 | TYPE/ID/中心X/帧号与输入对应，不漏空帧 |
| 实机回卷、断连/复位、丢包状态与长测 | 线一/线二 | 真实连续记录；确认 STATUS bit31 和 UART 异常口径 |
| 换手评审 | 队友/模块负责人 | 固定提交运行测试并人工签字；AI 复核不能代替负责人签字 |
