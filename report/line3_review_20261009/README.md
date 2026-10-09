<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual project documentation. -->

# 本轮整合后的新运行证据

日期2026-10-09；执行者OpenAI Codex。本轮自检，不是另一AI的独立反馈。受测合并提交bd10e2e40a3bc0a457143992987d607a3a5a07c4；测试时未修改源码。后续仅整理文档与复制证据，源码哈希见source_snapshot.json。

| 文件 | 说明 |
| --- | --- |
| commands.json、各*.command.json | 实际命令、目录、退出码、耗时；不是计划 |
| *.stdout.txt、*.stderr.txt | 原始控制台输出 |
| software/results.json、integrity.json | 174项软件结果、前后文件哈希/集合 |
| runner/results.json | 46项运行器构造测试 |
| line3_tools/acceptance.json | 18项工具检查；内部包含正确拒绝错误的断言 |
| line3_tools/software_rerun/ | 新的两模式视频、逐帧审计、观察记录、行为失败与模型输出 |
| rtl_default/ | 实际Vivado新运行，完整12帧检查失败，缺帧11；原始.raw保留 |
| rtl_drained_framediff/、rtl_drained_bg/ | 两种增加排空时间的仿真，各12帧严格比较及图像 |
| copied_evidence_manifest.json | 外部执行目录到仓内保留文件的字节哈希映射 |

检查结果：174/174、46/46、18/18；产品行为小测试仍5项失败。默认完整帧检查失败，延长排空的两模式通过。所有失败原样保留。两种PC输出视频均解码120帧，本次另查看了algo关键帧拼图；掩码PPM不因为能打开就视为逐像素正确。

完整构造副本仍保留在外部备份的current_checks；Git中保留结果、必要日志和可复跑脚本，避免把大量生成副本作为工程源码。真实数据、板卡、综合与时序未在本轮重新执行。
