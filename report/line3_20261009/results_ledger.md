<!-- Hallmark · pre-emit critique: P5 H4 E4 S5 R5 V4; scope: measured results and provenance. -->

# 结果台账

所有帧号从0开始；源码固定ead15e0，本线只添加测试与文档。本轮日期2026-10-09。

| 证据层级 | 结果 | 判定与范围 | 文件 |
|---|---|---|---|
| 本轮PC软件 | clean 210/210=1；algo 186/210=0.885714 | 120帧1280×720@30fps，15个merged帧排除，algo预热12帧仍在主分母内 | `run_ead15e0_01/results.json`及两模式frame/target_audit.csv |
| 本轮PC软件 | 两模式误检0、换号0、断航0 | 中心匹配门限60px、最多两个目标；不代表真实监控鲁棒性 | 同上 |
| 本轮PC软件 | 方向207/208、183/184；框端点最大误差0/1px | 两模式第92帧反弹速度不一致，已定位；不能写方向全部正确 | `media_03/details.json` |
| 本轮显示 | 两视频各120帧，包装与原程序每个解码帧哈希相同；事件区域检查0错帧 | 已看普通、粘连、恢复和43/102告警邻帧；告警id2/id1与CSV一致 | `run_ead15e0_01/*/keyframes.png`、`media_03/*_alarm_frames.png` |
| 本轮行为测试 | 25项：20 PASS、5 FAIL | 离开左右、重入、非30fps停留秒数、连续停留缺口失败 | `run_ead15e0_01/cases/cases.json` |
| 本轮工具验收 | 18/18 PASS；重跑入口真实返回2 | 校验完整帧集/坐标、CLI退出/拒覆盖/错误定位/日志换行；5项真实算法FAIL保持 | `tool_acceptance_02/acceptance.json`及`software_rerun/` |
| 本轮Python整数模型 | framediff、bg各12帧运行成功 | 属于模型运行，不是RTL执行 | `run_ead15e0_01/framediff.csv`、`bg.csv` |
| 归档RTL复核 | 0–10共11行全字段一致，缺11帧 | 限定交集PASS，完整帧集FAIL | `run_ead15e0_01/results.json` |
| 本轮新RTL原参数 | xsim2025.2，0–10一致，无X，11行 | 完整12帧FAIL，27.435秒为仿真工具耗时 | `rtl_fd01/result.json` |
| 本轮扩展尝试失败 | xelab生成C文件编译失败，阶段退出3 | 沙箱内失败记录保留，无输出，不判断RTL有错；具体底层原因未获编译器细节 | `rtl_fd02/console.txt`、`result.json` |
| 本轮新RTL扩展 | framediff 12/12全字段一致、x_hits0、无ERROR | FRAMES13仅排空，模型仍0–11；9.889秒工具耗时 | `rtl_fd03/result.json`、`invocation.bat` |
| 本轮新RTL扩展 | bg 12/12全字段一致、x_hits0、无ERROR | 同上，8.991秒工具耗时；未覆盖720p或随机激励 | `rtl_bg01/result.json` |
| 本轮RTL显示 | 两模式各12张320×180图；红框与CSV k−1行×2精确一致 | 使用0px容差；各12张160×90掩码可解析，只验形状/帧集，**未逐像素比模型** | `media_fd03/details.json`、`media_bg01/details.json`；原PPM已复制到各RTL目录wave/ |
| 存量CSV审计 | V43：12段/7类宏均值0.7367119048≈0.737 | 先类内序列均值再类间均值；没有原TP/FP/FN，不是本轮CDnet复跑 | `run_ead15e0_01/cdnet_audit.json` |
| 历史实现报告 | LUT10237、FF5979、BRAM80/140、DSP1；WNS+0.695ns、WHS+0.076ns | 2026-10-06 Vivado2026.1 Routed报告；本轮只读，不证明新版本性能 | `build/reports/impl_utilization.rpt:35,38,104,118`、`impl_timing_summary.rpt:148` |
| 板卡实测 | 本轮未执行 | 缺真实板卡输入输出、帧率、时延、长稳、插拔恢复证据 | `team_evidence.md` |

说明：media_02先生成两张告警拼图，后因rtl_fd02无CSV而退出；没有完整details.json，不能当完整验收。后续media_03与两份RTL媒体验收已完整写结果。旧run_ead15e0_01日志的CRCRLF原样保留，新运行日志已修正。所有失败记录均保留。

最终远程检查：沙箱内凭据进程报0xC0000022；获准在沙箱外重试fetch成功，origin/main仍为ead15e0，未出现须回归的队长新修复。没有合并、推送、PR或板卡下载。

交付自检增加20项：原124文件哈希、18项工具结果、主片段统计、两模式RTL字段与帧集、48张随包PPM哈希、媒体结果、UTF-8/源码语法、Markdown链接及九章完整性，首轮全部通过。首次ZIP内容与CRC通过，但回执中的Path.resolve在当前Windows沙箱对含`..`路径给出错误字符串；PowerShell确认文件实际位于外层line3_delivery_20261009。原包和回执保留，最终打包改用os.path.abspath和绝对输出路径，并重新验收。Git暂存检查另发现全局忽略*.log和文本换行规范化；本报告目录新增局部规则保留验收日志和第二轮原始证据字节，不改全局配置。最终以line3_evidence_release.zip及对应receipt为准。
