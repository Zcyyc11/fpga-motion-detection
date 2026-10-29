# 第一类自主收尾报告

2026-10-12。基于 ec8430aade40790a49aafb0b10c4250e9ecef19c 修复电脑端工具。
全部输入和串口故障均为模拟；未修改 RTL、算法或冻结协议，未进行板测。

## 修复与验收

| 问题 | 当前行为与证据 |
|---|---|
| 坏数据错误日志膨胀 | 默认前10000条明细；保留完整总数/分类计数/抑制数及原始流，失败不变 |
| 256 KiB 0xA5 反例 | 原18763362字节明细降至698890字节；262144次错误、10000条已写、252144条抑制；退出1 |
| 对照结果来源缺失 | source、source_label、capture_metadata及summary路径/SHA256随结果保存；错误结果也保留来源 |
| 打开/采集错误混淆 | 实际open成功后建采集目录；打开失败退出2无目录；打开后读取或关闭失败退出1并保留证据 |
| 复位建议可能漏重复 | 不采纳无条件previous=fid；500,499,500,501仍为有效/无效/无效/有效；复位后另开采集 |

新回归：`python -X utf8 sim/line3/check_uart_type1.py --out <全新目录>`。
现有回归：`check_uart_receiver.py --out <全新目录>`、`check_uart_evidence.py --out <全新目录>`。
运行环境 Python 3.13.5、pyserial 3.5；本机PYTHONPATH=<DRIVE>/line3_uart_20261012/deps。

| 本轮执行 | 结果 | 保存证据 |
|---|---|---|
| 定向反例 | 22/22，退出0 | evidence/type1_checks.json |
| 接收/协议/模拟串口回环 | 48/48，退出0 | evidence/receiver_checks.json |
| 证据对照与关闭异常 | 19/19，退出0 | evidence/evidence_checks.json |
| 最终源码SHA256 | 明确列出受测文件 | evidence/source_hashes.json |

完整本机输出：<DRIVE>/line3_uart_20261012/type1_20261012_01/，其中tests01、receiver01、evidence01各自独立。
旧JSONL/TCP工具未改动，其23/23为此前版本证据，本轮未重复执行。未重跑CDnet或整机Vivado。

## 复核范围与缺口

本轮读取并核对了旧版独立审计、Claude/Gemini反馈及FEEDBACK_RECHECK。
新版独立审阅子任务type1_review因服务额度限制终止，未返回审阅结果；不宣称新版已独立签字。
主执行者完成差异检查及上述正反例，具体记录见REVIEW_STATUS.md。
负责人换手复核仍需队友完成；本分支只用于审阅与联调准备，不合main。

旧审计底层结果实际47项/45项满足（B3与C5未满足），旧正文44项有统计差异；历史原稿保留。
FIFO覆盖和帧头插队风险来自Python转写模型，是待真实RTL验证的推断，不是本轮确认的RTL缺陷。

## 不能据此宣称的结论

- 8位累加和无法识别所有抵消错误；本轮保留碰撞反例，不能宣称全部坏数据必被识别。
- 来源和metadata只是声明；摘要哈希不认证实机，board_test和source_verified均为false。
- 协议无事件总数/帧结束包，events_complete固定false。图像为坐标画布，非同步视频。
- 实际串口、电平/接线、最终UART固件、原始报文、视频帧号映射、延迟和长测均未验证。

线一/线二提供最终源码SHA和bit哈希、原始二进制报文、独立目标/事件表、输入画面映射及运行记录后，
在新目录重放并精确对照，再人工检查来源、时序和丢包状态。旧包、旧源码、失败和审计证据保留。
最终提交/远程SHA、ZIP哈希和PR状态见工作区根handoff与本机交付回执，不从历史报告推断当前状态。
