# 新顶层到线三接收器的仿真联调报告

核验时间（上海）：2026-10-12T20:08:02.740826+08:00。
结论：**已执行RTL串行输出到电脑端的联调，但整段验收未通过。线二跟踪模块输出重复ID；接收器正确拒绝。**
串行传输值与发送前独立参考信号一致，不应通过删除问题帧或放宽ID校验来取得通过。

## 固定输入与证据边界

- 线二：line2/top-integration，`15e8e21ed253ff3e5fa9a44a972ece189495bd02`。
- 线三接收器：`e30c456e8232be286ed195481608e0c5bb429ab3`；本轮未修改接收器或产品RTL。
- 原始Git blob快照与SHA256：`evidence/source_manifest.json`；本机快照在D:/line3_top_cosim_20261012_01/。
- Vivado 2025.2 xsim；320×180内部pattern_gen，像素时钟100MHz，UART分频50，即2 Mbaud加速仿真。
- 测试从md_pipeline开始，不含真实板卡、HDMI PHY、USB-UART、电平、实测115200或真人视频帧对应。
- 参考表只证明发送前tk/al元数据与串行字节相符，不证明检测算法对真实图像的准确性。

## 结果

| 检查 | 实际结果 |
|---|---|
| 原顶层测试台复现 | `--relax`下27项断言通过，完成标记存在、无FAIL/ERROR |
| 普通场景 | 30帧（0—29），32个目标，598字节；14个零目标帧、16个双目标帧 |
| 告警场景 | 30帧（0—29），32个目标，646字节；2次越界、4次停留事件 |
| 独立串行采样与发送前字段对照 | 两场景全部有序包字段一致；采样未见起止位错误、未知态、drop或tick/input冲突 |
| 线三完整接收与精确对照 | 两场景均退出1；帧4和26重复ID，各伴随target_count_mismatch；整段不通过 |
| track最小反例 | 近邻双目标ID=0,0且dwell=2,2；远邻对照ID=0,1且dwell=1,1 |
| 33字节原始采样重放 | 提取普通流偏移[20:53]的帧4；接收器准确报告重复ID及目标数不符，退出1 |

`normal01/events01`的原测试台断言仍通过（27/28项），因为其检查“某些包见过ID0和1”，
没有检查每帧ID唯一性；不能把这个PASS当整段联调通过。最小track反例中xsim本身也退出0，
但日志含FAIL，运行器正确将测试结果判为失败。

缺最后参考帧、错坐标、坏校验的额外反例输出也已保留，但因完整原始场景本来就失败，
`negative_checks_conclusive=false`，不把这些结果算作有干净基线支撑的独立反例通过。

## 已定位问题：新建轨迹没有占用本帧匹配名额

固定版本的`src/rtl/track.v:125-141`：匹配旧轨迹时会置`tr_m[best]=1`；
创建新轨迹的分支没有置对应`tr_m`，却立即把新轨迹加入可匹配表。
第二个距离在MATCH_DIST以内的目标于是又匹配上这条刚建的轨迹，两目标得到同一个ID，
同一次帧结算还把seen/dwell从1加到2。

顶层帧4实际发送前输入：

| ID | 左上 | 右下 |
|---|---|---|
| 0 | (20,40) | (27,54) |
| 0 | (40,40) | (47,54) |

帧26同样发生在ID2。独立最小场景内部状态为`near_hits=0,0 near_tr_n=1`，
远邻对照为`far_hits=0,1 far_tr_n=2`，排除了PC解码或UART打包才引入重复的解释。

建议线二修复新轨迹的“本帧已使用”标记，并核对新轨迹老化/计数语义；
修复后先运行同一最小反例，再重跑两个顶层场景，要求每帧ID唯一、两个完整采集退出0。
本轮不代线二修改track或顶层，不替负责人签字。以上为建议方向，不宣称尚未实施的修复已通过。

## 编译兼容问题

baseline01（SystemVerilog）及baseline02（Verilog）在严格模式下均因
`bbox_snapshot.v:101`使用了第114行才声明的ack而编译失败。
编译器官方`--relax`将其降为警告后，原样RTL完成测试；没有改动原文件。
这是本机Vivado 2025.2的实际编译限制，应由线二处理声明顺序后再验证严格模式。
原测试台一些中文提示受32字节定宽字符串截断，原始日志保留；ASCII FAIL和最终完整完成标记用于判定。

## 复现入口

完整本机脚本在项目根`line3_top_cosim_20261012_01/`，运行器要求新目录名。

```powershell
python -X utf8 run_simulation.py --name normal_new --scenario normal
python -X utf8 run_simulation.py --name events_new --scenario events
python -X utf8 verify_cosim.py --run normal_new --out normal_check_new
python -X utf8 verify_cosim.py --run events_new --out events_check_new
python -X utf8 run_simulation.py --name track_probe_new --scenario track
```

本机依赖D:/AMD2025.2/2025.2/Vivado/settings64.bat；脚本使用D:/line3_top_cosim_20261012_01冻结目录。
远端最小复现不需要整个视频顶层：用固定线二提交的`src/rtl/track.v`与随附`tb_track_duplicate.v`
执行xvlog --relax -sv、xelab tb_track_duplicate、xsim -runall，检查FAIL而非只看退出码。
原始串口数据可直接用线三`uart_receiver.py --file duplicate_frame4.bin --source simulated --save-images 0 --out <新目录>`重放。

增强测试台只增加串行探针、发送前信号记录、末帧排空等待；告警场景通过现有寄存器写LINE_X=55、DWELL=3。
最后一次frame_tick之后尚未提交的下一帧输入单独存于`uncommitted_tail_inputs.json`，未冒充已传输帧。
所有已提交的0—29帧完整参与对照，没有按交集删去失败帧。

## 下一步及保护

线二修复上述重复ID后，在固定新SHA上重跑同样测试；严格编译问题也需验证。
实际板卡报文、独立参考表、视频对应、最终bit/源码哈希及长测仍是第二类外部输入。
旧源码、旧包、失败证据均保留；无后台仿真/采集需接管，全部process.json为finished。
上下文占用不可可靠读取；已在冻结输入、运行中和最终阶段备份更新handoff并本地Git保存。
