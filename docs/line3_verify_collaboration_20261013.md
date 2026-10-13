# Line 3 verification collaboration log, 2026-10-13

Actor: Codex, following the task allocation relayed by Sun Weibo. Human signature: pending.
Read origin/main@3d9f411 and two_pass_opt_plan_20261013.md before work. Created line3/verify-cleanup in the clean, dedicated line-three checkout. No line-two RTL edits and no pass-two implementation.
Authored independent tests for 16 default-capacity targets, run/label saturation, union and label reuse, natural 8-bit ID wrap, cfg_enable CDC/mode arithmetic, and AXI channel separation/backpressure. Existing testbenches are retained unchanged and rerun separately.
Independent expected components come from a Python four-neighbor flood fill, not DUT label state. Wrap stimulus creates 257 actual lifetimes without forcing the internal ID counter. Failed runs will be retained, not treated as acceptance.
Running the frozen main baseline in D:/line3_verify_cleanup_20261013_01. Per-job process.json and console.raw are authoritative for execution status. No board or resource claims.

## 实测反馈与纠正（2026-10-13，本轮执行中记录）

用户转达：“现在先干：测试补强（16目标满配/游程超限/id回绕）+ cfg_enable/协议台互验签字 + 报告推进……line3/verify-cleanup”。助手据此先fetch详细方案，未开始第二遍RTL优化。
初轮12项测试10通过2失败：自然ID回绕触发新轨迹首现误报；AXI AW/W分拍握手后丢写。cfg_enable实际寄存器写入/读回/同步与写回算术通过。旧AXI台仍通过，记录为覆盖有限，不签完整协议合格。
纠正1：最初容量场景为MIN_CNT=1诊断；随后增加MIN_CNT=64正式面积门限满配对照。main检出16目标，阶段版f2593d2仅4目标。保留两次夹具快照，没有用强制MAX_RUN=16掩盖退化。
纠正2：原文提到回绕可能漏报，本反例实际抓到首现误报；报告按实测陈述，并保留随后真正穿越恰好一次的对照。
纠正3：游程超限“通过”仅表示前4组件完整且无伪造/重复输出，第5组件碎裂仍是退化，不能宣称完整检出。检查补充重复框约束后单独复跑，旧版日志保留。
所有仿真均结束。代码、原始日志、哈希和执行命令已归档。没有综合/route/bit/板端结果；人工签字待本人确认；未向群聊或队友发消息。
