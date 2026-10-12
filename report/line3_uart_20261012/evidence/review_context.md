# UART 协议专项独立复核

范围：D:/line3_uart_20261012/work 相对 4e075bf17be99e72b0804376aaf60d7eb0bb3fdf 的 uart_protocol.py、uart_receiver.py、verify_uart_capture.py；对照 docs/protocol_and_interface_requirements.md 与线二 22e881d:src/rtl/uart_tx.v。未修改源码，未删除文件，未发布评论。

## 结论

本次范围未发现可确定复现、应阻止交付的线三代码缺陷。独立构造检查 12/12 通过，含 200 种随机拆包。所有输入均为软件构造，未验证真实板卡、串口线或线二发送 RTL 的物理输出。

## 核对结果

- 三包长度、字段位置、小端与累加校验正确；帧头之后目标和事件可交错，事件在最后目标之后仍归属同帧（uart_protocol.py:109-141）。
- FLAGS 原样保存，不误当目标有效位；当前线二发送端固定 0。非零值作为 undefined_flags 拒绝帧是保守策略（uart_protocol.py:149-150）；正式协议尚未定义其语义，不应声称非零值的通用互通性已验证。
- 事件在接收时输出，错误帧号不会混入当前帧（uart_protocol.py:131-140）。事件可出现在目标数为 0 的帧，符合事件独立包设计。
- 所有帧均 events_complete=false，包括已见下一帧头的帧，准确表达 v0.2 没有事件计数、不能证明静默事件丢失不存在的边界（uart_protocol.py:101-104）。
- 65535 到 0 回卷正常；跨回卷缺帧被记录；倒序/复位被记录错误（uart_protocol.py:117-129）。
- 接收证据与独立参考表匹配时校验成功；参考遗漏已接收事件时校验失败（verify_uart_capture.py:66-70）。来源认证和视频映射仍明确不在此比较范围（verify_uart_capture.py:74）。

## 证据

- protocol_review_repro.py：独立构造报文脚本，未复用被审测试的编码器。
- review_checks.json：12 项检查及受审源文件 SHA-256。
- mixed_order_stream.bin / mixed_order_result.json：混合顺序、零目标事件、16 目标和回卷证据。
- mixed_order_capture/：接收原始字节、包、帧、事件、摘要。
- reference.jsonl / missing_event_reference.jsonl：成功和失败的对照输入。

执行：PYTHONPATH=D:/line3_uart_20261012/deps，使用 D:/666666/Anaconda/python.exe 运行 protocol_review_repro.py。退出码 0；12/12 通过。

## Skill 范围说明

已读取 code-review-context/SKILL.md。该 Skill 内容约束模型上下文注入，受审代码不包含该机制；未据此捏造上下文类问题。上述结论来自按委托要求进行的 UART 协议专项核对。
