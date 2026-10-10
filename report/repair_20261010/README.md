<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual repair evidence. -->

# 已确认问题的修复记录（最终回归进行中）

2026-10-10。基线为 `08b944790b629546a584ade37e77818535f72c57`，修复分支 `codex/verified-repairs-20261010`。本记录区分开发中验证与最终固定提交验收；当前不得写成全部完成。

## 已修改及开发中验证

- AlarmRule 同时处理进入、离开、重新进入，事件流水与计数一致。状态跟随观测；速度零或矛盾时不报跨线。缺帧、帧号跳跃或离区重置连续停留；真实 fps 换算秒数并向上取整阈值；zone=None 按全画面。打印和视频支持 EXIT。
- 默认 testbench 等到 FRAMES 次 bbox 结算再停止，无法完成或出现未知态会失败。默认帧差、bg、兼容 drain=1 的开发中运行均有完整 0–11 帧。后续 morph3x3 改动后需要重跑，不沿用这些结果代替最终验收。
- rtl_golden 拒绝空表、重复、缺失、额外帧及末帧值错误；9 项修复检查通过，旧五项失败在旧提交模块上再次复现。
- 观察器仍直接调用原跟踪器；新增 assignment_audit.csv（含未匹配目标）、target_audit.csv 中心与真值坐标。24 项工具检查通过；整体重编号通过，真实交换、重建和掉检被检出。
- 新软件独立输出位于 [clean](tool_checks/software_rerun/clean/) 与 [algo](tool_checks/software_rerun/algo/)。各 120 帧，召回 210/210 与 186/210，身份交换/断航均 0；第 34 帧 cross_out、第 43 和 102 帧 cross_in，显示事件帧与 CSV 一致。仅覆盖指定合成视频。完整命令、源码哈希、观察数据都在同一次 software_rerun 内。

## 贴边测试新发现

[contracts01](contracts01/results.json)：10×10 全前景，真实两级流式 RTL 输出 49 格，旧模型误算 64。已把模型输出范围修正为 x=1..W-3、y=1..H-3；末端没有额外样本排空，不能当作对称完整图像开运算。

[contracts02](contracts02/results.json)：进一步使用四边宽 4 的矩形，旧 morph3x3 在左侧转右侧的第 4 帧 x=1,y=1 失败。原因是行首水平寄存器与帧首读行数据残留。局部修复初始化、行首清零、帧首旧行屏蔽；没有改 md_pipeline.v 或端口。

[contracts03](contracts03/results.json)：7 帧 × 49 个输出坐标全部核对，独立固定几何答案与模型、RTL 一致。阈值 6 次判定与回绕 384 次像素检查通过；阈值 70→69、提前回绕、取消回绕、坐标偏移均触发明确断言。xsim 在断言失败时可能仍返回 0，因此测试入口同时检查失败日志与完成标记。最终回归另增旧 morph3x3 整体回退反例。

## 保留的失败与待办

software_first 的新增 cross_out 打印触发 KeyError，已修复；software_second 行为通过但旧告警 CSV 比较失败，现保留差异作历史，改以固定事件时刻、类型、逐帧计数一致性验收，未修改旧 CSV。

首次边界回归 174/174，但完整性退出 1：[差异清单](first_integrity_failure.json)。4 个变化文件全是实时日志，145 个新增文件全是并行输出。此次仍记失败，不能将子测试通过冒充整体通过。

最终待做：从固定 Git 提交隔离运行全部回归与真实 RTL、汇总结果、复核 UTF-8/视频、同步 GitHub 修复分支并提审。`sim/line3/run_repair_regressions.py` 提供完整入口，输出须在仓库外新英文目录。

真实 CDnet 输入、板端回传和硬件实测仍缺。未重跑综合资源和时序；morph3x3 的小改动也必须经相应 owner 复核后合并。无 main 合并或人工换手验结论。旧原始报告、视频、CSV 均保留；完整基线 ZIP 已校验 CRC，见 [备份清单](backup.json)。
