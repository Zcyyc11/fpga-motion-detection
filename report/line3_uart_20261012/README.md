# 线三 UART 适配交付报告

2026-10-12。电脑端已具备正式协议三包接收、原始流重放、目标画框、越界/停留事件显示、
原始证据保存及精确对照能力。**本轮验证全部使用模拟输入；真实板卡联调未验证。**

使用入口：[接收与样本验收说明](../../docs/line3_uart_receiver.md)。

## 版本与保护范围

- 代码基线：main `4e075bf17be99e72b0804376aaf60d7eb0bb3fdf`。
- 协议：`f15fbcebd721ad0883b551d1497fd2a2454e1672` 定稿，115200-8N1、小端、累加和、5/14/8 字节三包。
- 发送格式对照：线二 `22e881d4b6d23c77df316fc3b4cf050aa1b8846e` 的 `uart_tx.v`。
  核查时该分支尚未合入 main；`regs.v` 的 6 位地址、BBOX 快照实现也在线二分支。
- `dc9f05f` 已是上述 main 的祖先，“候选未合入”的旧状态不再适用；历史审计文件保留。
- HDMI bit SHA256：`9f506bef41320b3d0428e38d18d87087cde35fd5d9b1c72a28ccc0347d1f275b`；
  `build/reports/hdmiin/` 中 WNS 0.932 ns。它是既有 HDMI 版，不能据此声称新 UART 通路已上板。
- 本轮不改 RTL、算法、冻结协议、历史评分或旧 JSONL/TCP 接收器；没有重跑 CDnet 或整机综合。
- 独立分支 `codex/line3-uart-20261012`；main 不由线三合并。最终发布状态见本机交付回执。

## 已实现

| 文件 | 作用 |
|---|---|
| `sim/line3/uart_protocol.py` | 分包、校验、重同步、帧/目标/事件归属、16 位回卷与异常检查 |
| `sim/line3/uart_receiver.py` | 串口/二进制文件入口、坐标画布、即时事件、原始流及 JSONL 日志 |
| `sim/line3/verify_uart_capture.py` | 从原始字节重解码并验证帧表，再逐字段对照独立参考表 |
| `sim/line3/check_uart_receiver.py` | 48 项协议/接收/图像/串口库模拟回环检查 |
| `sim/line3/check_uart_evidence.py` | 19 项参考表正反例、原始流绑定和关闭异常回归 |

目标 FLAGS=0 按正常目标处理，非零保留并记未定义语义异常；TYPE 1/2 分别显示越界/停留。
坏校验、缺帧、重复、倒序、目标数不符、孤立包、异常断开都使本次采集非零退出。
输出目录禁止覆盖；图像数量、总字节、帧数和采集时长有上限。回卷后图像文件不会重名。

## 验证证据

环境：Python 3.13.5、pyserial 3.5、OpenCV 4.13.0、NumPy 2.1.3，Windows。
以下命令均从仓库根目录执行，输出目录每次取新名字。

```powershell
python -X utf8 sim/line3/check_uart_receiver.py --out D:/uart_check_new
python -X utf8 sim/line3/check_uart_evidence.py --out D:/uart_evidence_check_new
python -X utf8 sim/line3/check_pc_receiver.py --out D:/legacy_receiver_check_new
```

| 检查 | 结果 | 证据 |
|---|---|---|
| 最终协议/接收检查 | 48/48，退出 0 | `evidence/uart_checks.json` |
| 最终证据对照/关闭异常回归 | 19/19，退出 0 | `evidence/evidence_checks.json` |
| 旧接收器回归 | 23/23 | `evidence/legacy_checks.json` |
| 独立协议复核 | 12/12，含 200 种随机拆包 | `evidence/review_context_checks.json` |
| 独立测试复核 | 21/21 正反例，另发现原始流与帧表未绑定问题 | `evidence/review_testing_results.json` |
| 独立兼容性/异常复核 | 8/8，另发现资源关闭失败丢汇总问题 | `evidence/review_breaking_checks.json` |
| 图像核查 | 1280×800 可解码，边角坐标映射检查；人工视觉查看模拟来源提示及告警行 | `evidence/sample_simulated.png` |

独立复核针对初版源码，源码哈希在各证据内；不能把旧版审阅算作对最终版重新全审。
发现的问题由主执行者修复并新增针对性回归。复核服务随后发生额度限制，两个子任务的
最终总结和变更大小子任务未返回；已经落盘的复现证据仍保留，未虚构完整独立签字。

## 复核发现与处理

1. **原始流与保存帧表可能混用（已修复）**：仅检查原始流哈希仍允许错误帧表与错误参考表
   相互匹配。现在重新解码原始流、核对保存帧表，再对独立参考逐字段比较。
   复现及修复后拒绝结果分别为 `evidence/mixed_before.json`、`evidence/mixed_after.json`。
2. **关闭资源失败绕过汇总（已修复）**：串口/显示清理各自捕获异常，仍写汇总和错误记录。
   `check_uart_evidence.py` 的 close failure 检查验证原始流及 summary 留存。存储介质本身
   不可写时不能保证完整落盘，命令会报错；没有声称可抵御磁盘故障。
3. **手写基准报文校验值错误（测试已修正）**：首轮 47/48；目标包校验由错误的 0x46 改为
   正确的 0x56，失败报告在 `evidence/initial_failed_checks.json`，未删除或改写失败。
4. **变更大小（主执行者补充检查）**：交付含核心解析/接收、独立对照、两套测试和文档，
   总行数超过 800。建议按“协议与接收核心 → 对照及反例 → 文档证据”三个部分审阅；
   最小可运行阶段是 protocol + receiver + requirements 与接收测试。既有入口未改行为，
   不为缩小行数牺牲异常路径或测试。未将此项冒充独立审阅结论。

## 尚未验证及外部输入

- 实际 COM 端口、物理串口电平/线缆、真实报文、视频帧映射、实际传输延迟均未验证。
- 10/13 上板、10/14 零/单/多目标报文是队内排期；线一/线二提供最终 UART 集成源码与 bit
  哈希、原始二进制流、帧号/目标/事件对照、对应画面和运行记录后，按使用指南验收。
- 协议没有事件数量或结束包，`events_complete` 永远为 false；事件日志完整性不能仅靠
  本工具证明。真实回卷长测和 STATUS bit31 丢包记录仍需板端提供。
- 60 fps×16 目标需 13740 B/s（未计事件），超过 115200-8N1 的 11520 B/s；
  队友须以实际帧率/限速策略验证带宽，不能沿用无帧率前提的“约 3 KB/s”。
- 人工换手评审和负责人签字仍需队友；AI 模拟检查及独立复核不替代。

线三当前可自主实现与模拟验证已交付，真实样本到位后才可完成联调结论。
