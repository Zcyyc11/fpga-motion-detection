<!-- Hallmark · pre-emit critique: P5 H4 E4 S5 R5 V4; scope: direct inspection evidence. -->

# 补充检查记录

2026-10-09，本轮新结果。

- 已实际打开并检查 clean/keyframes.png、algo/keyframes.png。第 20 帧显示两个独立目标及 id1/id2；第 33 帧连成一块时没有检测框；第 42、68、95 帧重新显示两个编号，第 114 帧再次合并。原程序左上角黑字落在黑底上，帧号/统计不易看清；新增拼图底部附有清晰帧号。最终视频检查仍需补看第 43 和 102 帧的 ALARM 字样，当前拼图未包含这两帧。
- 直接读取 clean_observed/observations.json：cross_out 计数只在第 67 帧从 0 变 1。真值离开帧为 32。这是时间错误，不能因总次数恰为 1 就验收通过；需要对照代码和该帧速度进一步写入问题单。
- 运行前后复核 manifest.json 的全部 124 个基线跟踪文件 SHA256，无变化。
- 5 份新增 Python 源文件均通过 ast.parse；新增源码与两份线三 Markdown 未发现 Unicode 替换字符 U+FFFD。
- 捕获日志用二进制 stdout 解码后存为 UTF-8，Windows 换行经过文本写入留下 CRCRLF；字符内容可读。原日志保留，不为消除 Git 空白提示改写证据。局部 .gitattributes 保留这些日志原始字节并关闭其空白检查；后续入口宜用 newline='\n' 或先统一换行，新增运行目录另存。
- 新 RTL 执行时长为 27.435 秒，仅指本机 xvlog/xelab/xsim 的总运行时间。日志明确写出 Vivado 2025.2；这不是板卡性能。
