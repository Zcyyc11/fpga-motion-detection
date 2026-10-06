# =============================================================================
#  build_vivado.tcl —— 从源码到 bitstream 的全自动构建（官方要求的"可复现构建脚本"）
#
#  用法：
#    vivado -mode batch -source build/scripts/build_vivado.tcl -tclargs [MODE_BG]
#
#  做四件事：
#    1) 建工程（器件 xc7z020clg400-1，就是 PYNQ-Z2 上那颗 XC7Z020-1CLG400C）
#    2) 从本地 IP 仓库引入 Digilent 的 rgb2dvi（HDMI 发送：TMDS 编码 + 串化）
#    3) 加 RTL / 约束，跑综合 → 实现 → 出 bit
#    4) 把资源、时序、时钟三份报告写到 build/reports/（对应评分项"资源·时钟·性能"）
#
#  ★ 为什么不建 Block Design：
#    本设计的核心价值是 PL 里的那条流水线，用纯 RTL 表达最清楚、最容易复核；
#    为了用 IP 而套一层 BD 只会让"到底哪段是我们写的"变模糊。
#    唯一的 IP 是别人写好的 HDMI 发送器（rgb2dvi），它本身就是 RTL 形式调用的。
#
#  ★ 路径纪律：Vivado 工程路径与用户名不能含中文，所以工程建在 D:\FPGA 下。
# =============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR .. ..]]
set RTL_DIR    [file join $ROOT src rtl]
set RTL_BOARD  [file join $ROOT src rtl board]
set BOARD_DIR  [file join $ROOT board]
set BUILD_DIR  [file join $ROOT build]
set PROJ_DIR   [file join $BUILD_DIR vivado]
set REPORT_DIR [file join $BUILD_DIR reports]

# IP 仓库路径不写死 —— 换台机器就能改，不需要动脚本（build/README.md 的纪律）。
# 优先取环境变量 MOTION_IP_REPO，没有才退回本机路径。
if {[info exists ::env(MOTION_IP_REPO)]} {
    set IP_REPO $::env(MOTION_IP_REPO)
} else {
    set IP_REPO {D:/FPGA/libs/vivado-library}
    puts "提示：未设置 MOTION_IP_REPO 环境变量，使用本机默认 $IP_REPO"
}

set MODE_BG 0
if {$argc >= 1} { set MODE_BG [lindex $argv 0] }

set PART xc7z020clg400-1
set TOP  board_top

puts "=============================================================="
puts " 构建 FPGA 运动目标检测"
puts "   仓库根   : $ROOT"
puts "   器件     : $PART (PYNQ-Z2 = XC7Z020-1CLG400C)"
puts "   顶层     : $TOP"
puts "   MODE_BG  : $MODE_BG  (0=帧差法 v1 / 1=背景建模 v2)"
puts "   IP 仓库  : $IP_REPO"
puts "=============================================================="

file mkdir $REPORT_DIR

# ---------------------------------------------------------------- 1) 建工程
# ★ 旧工程目录的清理**不在这里做**，交给 build_vivado.bat 里的 `rmdir /s /q`。
#   原因（实测，不是推测）：Vivado 自己的 `file delete -force` 一旦碰到残留的
#   文件句柄，会弹出一个**隐藏的模态对话框**然后永远等下去 —— 现象是进程还活着、
#   只占 15 MB 内存、窗口标题 OLEChannelWnd、CPU 时间 10 分钟一动不动，
#   日志停在"旧工程目录已存在"那一行。同一棵目录树改用 OS 原生删除只要 ~2 秒。
#   同理这里也**不调 close_project**：batch 模式下此刻没有打开的工程，
#   它会抛 ERROR [Common 17-53] No open project，而这个 ERROR 会直接终止
#   Vivado（catch 也拦不住），表现就是脚本刚开始就死。
#   所以：清理由 bat 负责，这里只管建工程。
create_project -force fpga_motion_detection $PROJ_DIR -part $PART
set_property target_language Verilog [current_project]
# 允许在 xdc 里用 TMDS_33 这类差分电平（部分版本默认禁止）
catch { set_property enable_vhdl_2008 1 [current_project] }

# ---------------------------------------------------------------- 2) 引入 rgb2dvi
set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog -rebuild
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -version 1.4 -module_name rgb2dvi_0
# kClkRange 的取值不是随便填的：rgb2dvi 内部要用一个 MMCM 把像素时钟倍频出 5x 串行时钟，
# MULT_F = kClkRange * 5，而 FVCO = 像素时钟 * MULT_F 必须落在 [600, 1200] MHz（Artix-7 -1）。
# IP 自带注释就点了名：720p 的 74.25 MHz → FVCO = 74.25 * 10 = 742.5 MHz。
# 所以这里取 2（MULT_F=10）。取 3 会变成 74.25*15 = 1113.75 MHz，虽然也没越界，
# 但白白把 VCO 顶到接近上限；取 1 则只有 371 MHz，低于下限不合法。
set_property -dict [list \
    CONFIG.kGenerateSerialClk {true} \
    CONFIG.kClkPrimitive      {MMCM} \
    CONFIG.kClkRange          {2} \
    CONFIG.kRstActiveHigh     {true} \
    CONFIG.TMDS_BOARD_INTERFACE {Custom} \
] [get_ips rgb2dvi_0]
generate_target all [get_ips rgb2dvi_0]
puts "rgb2dvi 关键参数（人工复核用）："
foreach p {CONFIG.kClkRange CONFIG.kClkPrimitive CONFIG.kGenerateSerialClk CONFIG.kRstActiveHigh} {
    catch { puts "   $p = [get_property $p [get_ips rgb2dvi_0]]" }
}

# ---------------------------------------------------------------- 3) 加源码与约束
add_files -norecurse [concat [glob -nocomplain [file join $RTL_DIR *.v]] \
                              [glob -nocomplain [file join $RTL_BOARD *.v]]]
# 约束文件**只加真正生效的那一份**。board/ 下另有 pynq-z2_v1.0_official.xdc ——
# 那是官方原件的完整留存，**整份都是注释行**（按需取消注释），用途是逐条对照、不是生效约束。
# ★ 之前这里用 `glob *.xdc`，会把那份注释件也塞进 constrs_1：虽然是空操作（一行有效约束都没有），
#   但会让人误以为工程里有两份约束在生效，排查引脚/时序问题时先被自己误导一轮。
add_files -fileset constrs_1 -norecurse [file join $BOARD_DIR pynq_z2_hdmi_out.xdc]
set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1
puts "加入的 RTL："
foreach f [get_files -of [get_filesets sources_1]] { puts "   $f" }

# ---------------------------------------------------------------- 4) 综合 → 实现 → bit
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "!! 综合失败，日志：$PROJ_DIR/fpga_motion_detection.runs/synth_1/runme.log"
    exit 1
}
open_run synth_1
report_utilization    -file [file join $REPORT_DIR synth_utilization.rpt]
report_timing_summary -file [file join $REPORT_DIR synth_timing_summary.rpt]
report_clocks         -file [file join $REPORT_DIR synth_clocks.rpt]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "!! 实现失败，日志：$PROJ_DIR/fpga_motion_detection.runs/impl_1/runme.log"
    exit 1
}

# bitstream 要落到一个**不会被下次构建清掉**的地方：
# build/vivado/ 是每次构建开头就被 bat 的 rmdir 干掉的工作目录，不能当交付位置。
set BIT_SRC [file join $PROJ_DIR fpga_motion_detection.runs impl_1 ${TOP}.bit]
set BIT_DIR [file join $BUILD_DIR bitstream]
set BIT_DST [file join $BIT_DIR ${TOP}.bit]
file mkdir $BIT_DIR
if {[file exists $BIT_SRC]} {
    file copy -force $BIT_SRC $BIT_DST
} else {
    puts "!! 没有生成 bitstream：$BIT_SRC"
    exit 1
}

open_run impl_1
report_utilization      -file [file join $REPORT_DIR impl_utilization.rpt]
report_timing_summary   -file [file join $REPORT_DIR impl_timing_summary.rpt]
report_clock_interaction -file [file join $REPORT_DIR impl_clock_interaction.rpt]
report_drc              -file [file join $REPORT_DIR impl_drc.rpt]

set WNS [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set WHS [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
puts "=============================================================="
puts " 综合实现结果"
puts "   时序  WNS(setup) = $WNS ns   WHS(hold) = $WHS ns"
puts "   bit 流：$BIT_DST"
puts "   报告  ：$REPORT_DIR"
puts "=============================================================="

# 时序没收敛就把这次构建判成失败 —— bit 虽然生成了也不可信，
# 不能让它安安静静地流到"上板看画面"那一步再炸。
if {($WNS < 0) || ($WHS < 0)} {
    puts "!! 时序未收敛：WNS=$WNS  WHS=$WHS。先生修时序，别拿这个 bit 上板。"
    exit 1
}
puts "时序收敛：所有用户约束均满足（All user specified timing constraints are met）。"

exit 0
