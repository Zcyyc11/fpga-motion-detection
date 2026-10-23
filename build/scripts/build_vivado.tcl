# =============================================================================
#  build_vivado.tcl —— 从源码到 bitstream 的分阶段自动构建
#
#  用法：
#    vivado -mode batch -source build/scripts/build_vivado.tcl -tclargs [MODE_BG] [INPUT_SEL] [STAGE]
#
#    MODE_BG  : 0 = 帧差, 1 = 背景建模
#    INPUT_SEL: 0 = 自测激励, 1 = 真实 HDMI 输入
#    STAGE    : setup | synth | impl | bit | all（默认 all）
#      setup = 建工程 + HDMI IP + 源码约束（工程已存在则 open 复用，跳过 IP 生成）
#      synth = 多线程综合 + post-synth checkpoint + 综合三报告
#      impl  = opt/place/route（RuntimeOptimized 提速），内部断点可续跑
#      bit   = 出 bit + 拷到 build/bitstream + 实现四报告 + WNS/WHS
#
#  ★ 为什么分阶段（2026-10-14 实测数据，不是拍的）：
#    整套一把梭要 2-3 小时；本机 24 逻辑核，而 launch_runs -jobs 2 远没喂满。
#    拆分后：setup 约 7 分钟（复用工程约 2 分钟）+ synth 8 线程约 20 分钟 +
#    impl RuntimeOptimized 约 25-35 分钟 + bit 约 3 分钟 ≈ 一小时内出 bit。
#    且每阶段落 checkpoint（build/checkpoints/post_synth.dcp，impl 的 opt/place/route
#    断点由 Vivado 自己存在 runs/impl_1 下），任何一阶段死了不用从头再来：
#      synth 死了 → 重跑 synth（约 20 分钟）
#      impl 死了 → 直接重跑 impl，Vivado 从最后一个完成的 step 续
#
#  ★ 为什么不建 Block Design：同旧版说明——核心价值是 PL 流水线本身，
#    纯 RTL 表达最清楚；唯一 IP 是 Digilent 的 HDMI 收发器。
#
#  ★ 路径纪律：工程路径与用户名不能含中文，工程建在仓库内的 build/vivado
#    （被 .gitignore 忽略）；工程根目录由脚本按自身位置推算，不写死机器路径。
# =============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR .. ..]]
set RTL_DIR    [file join $ROOT src rtl]
set RTL_BOARD  [file join $ROOT src rtl board]
set BOARD_DIR  [file join $ROOT board]
set BUILD_DIR  [file join $ROOT build]
if {[info exists ::env(MOTION_BUILD_DIR)]} {
    set BUILD_DIR [file normalize $::env(MOTION_BUILD_DIR)]
}
set PROJ_DIR   [file join $BUILD_DIR vivado]
set REPORT_DIR [file join $BUILD_DIR reports]
set CKPT_DIR   [file join $BUILD_DIR checkpoints]
# ★ IP 缓存（2026-10-16 新增）：放工程外（仓库根的上一级），删 build/vivado 重建也不丢。
#   原理：Vivado 按「IP配置+器件+工具版本」指纹存取 IP 综合结果（.dcp），命中即跳过
#   IP 生成 + OOC 综合（实测该段约 50 分钟）。不命中自动退回重综合，零正确性风险。
set IP_CACHE_DIR [file normalize [file join $ROOT .. fmd_ip_cache]]

# IP 仓库路径不写死 —— 换台机器改环境变量即可，不用动脚本（build/README.md 的纪律）。
if {[info exists ::env(MOTION_IP_REPO)]} {
    set IP_REPO $::env(MOTION_IP_REPO)
} else {
    set IP_REPO [file join $ROOT .. libs vivado-library]
    puts "提示：未设置 MOTION_IP_REPO，使用默认位置 $IP_REPO"
}

set MODE_BG 0
if {$argc >= 1} { set MODE_BG [lindex $argv 0] }
if {$MODE_BG ni {0 1}} { error "MODE_BG must be 0 or 1" }

set INPUT_SEL 0
if {$argc >= 2} { set INPUT_SEL [lindex $argv 1] }
if {$INPUT_SEL ni {0 1}} { error "INPUT_SEL must be 0 or 1" }

set STAGE all
if {$argc >= 3} { set STAGE [lindex $argv 2] }
if {$STAGE ni {all setup synth impl bit}} { error "STAGE must be all|setup|synth|impl|bit" }

set PART xc7z020clg400-1
set TOP  board_top_legacy

# 综合线程数：本机 24 逻辑核，Vivado synth 多线程收益实测约 2 倍（同规模
# Zynq-7020 设计 8 线程 vs 默认）。留一部分核给系统和磁盘 IO。
set MAXTHREADS 8

# 实现阶段指令：RuntimeOptimized = 用可接受的 QoR 换显著更短的运行时间。
# 可用环境变量 IMPL_DIRECTIVE 覆盖（如 Explore 精修时序时）。
if {[info exists ::env(IMPL_DIRECTIVE)] && $::env(IMPL_DIRECTIVE) ne ""} {
    set IMPL_DIRECTIVE $::env(IMPL_DIRECTIVE)
} else {
    set IMPL_DIRECTIVE RuntimeOptimized
}

set XPR [file join $PROJ_DIR fpga_motion_detection.xpr]

puts "=============================================================="
puts " 构建 FPGA 运动目标检测（分阶段版）"
puts "   仓库根   : $ROOT"
puts "   器件     : $PART (PYNQ-Z2 = XC7Z020-1CLG400C)"
puts "   顶层     : $TOP"
puts "   MODE_BG  : $MODE_BG  (0=帧差法 v1 / 1=背景建模 v2)"
puts "   INPUT_SEL: $INPUT_SEL (0=自测激励 / 1=真实 HDMI 输入)"
puts "   STAGE    : $STAGE"
puts "   线程数   : $MAXTHREADS (synth)   实现指令: $IMPL_DIRECTIVE"
puts "   IP 仓库  : $IP_REPO"
puts "=============================================================="

file mkdir $REPORT_DIR

# ---------------------------------------------------------------- setup 阶段
proc stage_setup {} {
    global XPR PROJ_DIR PART TOP RTL_DIR RTL_BOARD BOARD_DIR IP_REPO \
           MODE_BG INPUT_SEL SCRIPT_DIR IP_CACHE_DIR
    if {[file exists $XPR]} {
        # ★ 复用半截工程是分阶段提速的关键：IP 生成 + OOC 综合约 7 分钟的活
        #   不用重复付。要强制全新构建：先删 build/vivado 再跑 setup。
        puts "复用已有工程：$XPR（跳过 IP 生成；强制全新请先删除 build/vivado）"
        open_project $XPR
    } else {
        create_project -force fpga_motion_detection $PROJ_DIR -part $PART
        set_property target_language Verilog [current_project]
        # 允许在 xdc 里用 TMDS_33 这类差分电平（部分版本默认禁止）
        catch { set_property enable_vhdl_2008 1 [current_project] }

        set_property ip_repo_paths [list $IP_REPO] [current_project]
        update_ip_catalog -rebuild
        create_ip -name rgb2dvi -vendor digilentinc.com -library ip -version 1.4 -module_name rgb2dvi_0
        # kClkRange=2：rgb2dvi 内部 MMCM 倍频出 5x 串行时钟，MULT_F=kClkRange*5，
        # FVCO=像素时钟*MULT_F 必须落在 [600,1200] MHz。720p 的 74.25MHz →
        # 取 2 得 742.5MHz（取 3 会顶到 1113.75 接近上限，取 1 只有 371 低于下限）。
        set_property -dict [list \
            CONFIG.kGenerateSerialClk {true} \
            CONFIG.kClkPrimitive      {MMCM} \
            CONFIG.kClkRange          {2} \
            CONFIG.kRstActiveHigh     {true} \
            CONFIG.TMDS_BOARD_INTERFACE {Custom} \
        ] [get_ips rgb2dvi_0]
        generate_target all [get_ips rgb2dvi_0]

        # dvi2rgb（HDMI 输入：TMDS 解码 + 时钟恢复，720p EDID）
        # 参数出处（kClkRange=3、EDID=dgl_720p_cea.data、kAddBUFG=true 等）
        # 见 create_dvi2rgb.tcl 头部注释。
        source [file join $SCRIPT_DIR create_dvi2rgb.tcl]

        add_files -norecurse [concat [glob -nocomplain [file join $RTL_DIR *.v]] \
                                      [glob -nocomplain [file join $RTL_BOARD *.v]]]
        # 约束只加真正生效的那两份：pynq_z2_hdmi_out.xdc（HDMI 输出 J11）+
        # pynq_z2_hdmi_in.xdc（HDMI 输入 J10）。board/ 下那份官方完整留存
        # 整份都是注释行，是逐条对照用的，不是生效约束，不塞进工程。
        add_files -fileset constrs_1 -norecurse [list \
            [file join $BOARD_DIR pynq_z2_hdmi_out.xdc] \
            [file join $BOARD_DIR pynq_z2_hdmi_in.xdc]]
    }
    # ★ IP 缓存：工程一打开就挂上共享缓存目录（create/open 两条路都要走这）
    file mkdir $IP_CACHE_DIR
    set_property ip_output_repo $IP_CACHE_DIR [current_project]
    set_property ip_cache_permissions {read write} [current_project]
    set_property top $TOP [current_fileset]
    # ★ 2026.1 实测：fileset 的 generic 用【空格】分隔，逗号分隔会把整个串
    #   解析成一个 generic 名。旧版本是逗号。
    set BG_FRAC_BITS 0
    if {[info exists ::env(MOTION_BG_FRAC_BITS)]} { set BG_FRAC_BITS $::env(MOTION_BG_FRAC_BITS) }
    set BG_SHIFT 6
    if {[info exists ::env(MOTION_BG_SHIFT)]} { set BG_SHIFT $::env(MOTION_BG_SHIFT) }
    set_property generic [format "MODE_BG=%d INPUT_SEL=%d BG_SHIFT=%d BG_FRAC_BITS=%d" $MODE_BG $INPUT_SEL $BG_SHIFT $BG_FRAC_BITS] [current_fileset]
    update_compile_order -fileset sources_1
    puts "setup 完成：工程就绪（top=$TOP, generic=MODE_BG=$MODE_BG INPUT_SEL=$INPUT_SEL）"
    close_project
}

# ---------------------------------------------------------------- synth 阶段
proc stage_synth {} {
    global XPR MAXTHREADS REPORT_DIR CKPT_DIR TOP
    open_project $XPR
    # ★ 多线程是本机 24 逻辑核的关键利用：不设的话 synth 默认低并行度，
    #   "Cross Boundary and Area Optimization" 一步实测能跑 41 分钟。
    set_param general.maxThreads $MAXTHREADS
    if {[info exists ::env(SYNTH_DIRECTIVE)] && $::env(SYNTH_DIRECTIVE) ne ""} {
        set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $::env(SYNTH_DIRECTIVE) [get_runs synth_1]
        puts "SYNTH_DIRECTIVE=$::env(SYNTH_DIRECTIVE)"
    }
    # ★ 若 synth_1 上次已启动但未完成（被 kill 的构建就会这样），直接
    #   launch_runs 会报 Common 17-69 "needs to be reset before launching"。
    #   synth 没有中间 checkpoint 可续，reset 重跑是唯一路径（8 线程约 20 分钟）。
    if {[get_property PROGRESS [get_runs synth_1]] ne "0% Complete"} {
        puts "synth_1 上次未完成（[get_property PROGRESS [get_runs synth_1]]），reset 后重跑"
        reset_run synth_1
    }
    launch_runs synth_1 -jobs 1
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
        error "综合失败，日志：$XPR 同级的 runs/synth_1/runme.log"
    }
    open_run synth_1
    file mkdir $CKPT_DIR
    # 手动 checkpoint 双保险：project 模式的 runs/synth_1 dcp 之外再落一份，
    # 万一 runs 目录被动过，impl 还能 open_checkpoint 接着跑。
    write_checkpoint -force [file join $CKPT_DIR post_synth.dcp]
    report_utilization    -file [file join $REPORT_DIR synth_utilization.rpt]
    report_timing_summary -file [file join $REPORT_DIR synth_timing_summary.rpt]
    report_clocks         -file [file join $REPORT_DIR synth_clocks.rpt]
    close_design
    close_project
    puts "synth 完成：checkpoint=$CKPT_DIR/post_synth.dcp，报告在 $REPORT_DIR"
}

# ---------------------------------------------------------------- impl 阶段
proc stage_impl {} {
    global XPR IMPL_DIRECTIVE
    open_project $XPR
    # ★ 断点续跑：不 reset_run。已开始过的 run 直接 launch 会从最后一个
    #   完成的 step 继续（opt→place→route 每步的 checkpoint 由 Vivado 存在
    #   runs/impl_1 下）。要彻底重来才需要 reset_run impl_1。
    foreach {step attr} {OPT_DESIGN opt PLACE_DESIGN place ROUTE_DESIGN route} {
        set_property STEPS.$step.ARGS.DIRECTIVE $IMPL_DIRECTIVE [get_runs impl_1]
    }
    puts "impl 指令：opt/place/route 均用 $IMPL_DIRECTIVE（可用环境变量 IMPL_DIRECTIVE 覆盖）"
    # impl 正常路径：不 reset，已开始的 run 从最后一个完成的 step 续跑
    # （opt→place→route 每步 checkpoint 在 runs/impl_1 下）。
    # 兜底：若 run 状态不允许直接 launch（报 17-69），reset 后从头 impl。
    if {[catch {launch_runs impl_1 -to_step route_design -jobs 1} err]} {
        if {[string match "*needs to be reset*" $err]} {
            puts "impl_1 需要 reset（$err），从头 impl"
            reset_run impl_1
            launch_runs impl_1 -to_step route_design -jobs 1
        } else {
            error $err
        }
    }
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
        error "实现失败。若已到 place/route，可直接重跑 impl 阶段从断点续；日志：runs/impl_1/runme.log"
    }
    close_project
    puts "impl complete: routed design retained; bit stage must validate timing first"
}

# ---------------------------------------------------------------- bit 阶段
proc stage_bit {} {
    global XPR PROJ_DIR TOP BUILD_DIR REPORT_DIR
    open_project $XPR
    open_run impl_1
    # bitstream 落到不会被清理的交付位置：build/vivado 是工作目录，不能当交付。
    set BIT_DIR [file join $BUILD_DIR bitstream]
    set BIT_DST [file join $BIT_DIR ${TOP}.bit]
    report_utilization       -file [file join $REPORT_DIR impl_utilization.rpt]
    report_timing_summary    -file [file join $REPORT_DIR impl_timing_summary.rpt]
    report_clock_interaction -file [file join $REPORT_DIR impl_clock_interaction.rpt]
    report_drc               -file [file join $REPORT_DIR impl_drc.rpt]
    set WNS [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set WHS [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
    # Fail closed: no deliverable bit before setup/hold and implementation DRC.
    if {![string is double -strict $WNS] || ![string is double -strict $WHS]} {
        error "Missing setup/hold timing paths; bit delivery blocked"
    }
    if {$WNS < 0 || $WHS < 0} {
        error "Timing failed: WNS=$WNS WHS=$WHS; no deliverable bit written"
    }
    set BAD_DRC [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]
    if {[llength $BAD_DRC] != 0} {
        error "Implementation DRC errors/critical warnings: $BAD_DRC"
    }
    if {[file exists $BIT_DST]} { error "Refusing to overwrite existing bit: $BIT_DST" }
    file mkdir $BIT_DIR
    write_bitstream $BIT_DST
    puts "=============================================================="
    puts " 综合实现结果"
    puts "   时序  WNS(setup) = $WNS ns   WHS(hold) = $WHS ns"
    puts "   bit 流：$BIT_DST"
    puts "   报告  ：$REPORT_DIR"
    puts "=============================================================="
    close_design
    close_project
    puts "Timing and DRC gates passed; hardware behavior still requires board evidence."
}

# ---------------------------------------------------------------- 调度
switch $STAGE {
    setup { stage_setup }
    synth { stage_synth }
    impl  { stage_impl }
    bit   { stage_bit }
    all   { stage_setup; stage_synth; stage_impl; stage_bit }
}

exit 0
