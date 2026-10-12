# =============================================================================
#  create_dvi2rgb.tcl —— 在 Vivado 工程里生成 HDMI 输入解码 IP（dvi2rgb_0）
#
#  用法（在已打开工程的 Vivado 里，或由 build 流程 source）：
#     source create_dvi2rgb.tcl
#   需要先有 IP 仓库（MOTION_IP_REPO 环境变量或 D:/FPGA/libs/vivado-library），
#   与 build_vivado.tcl 同一套路径纪律：不写死机器路径。
#
#  为什么这些参数是这些值（每个都有出处，不是拍的）：
#    kClkRange = 3   —— 覆盖 <80 MHz 档（component.xml 枚举：1=≥120M/1080p、
#                        2=<120M、3=<80M/720p）。IP 内部 MMCM 取 MULT_F = kClkRange*5 = 15，
#                        VCO = 74.25×15 = 1113.75 MHz ∈ [600,1200]（Artix-7 -1 级）。✅
#                        文档 3 Performance 明说：TMDS_Clk 应约束到实际分辨率时钟。
#    kEdidFileName = dgl_720p_cea.data —— 官方自带 720p60 首选时序 EDID（文档 6.4），
#                        与我们的 1280x720@60 目标一致，DDC ROM 合成时嵌入该文件。
#    kAddBUFG = true —— 文档 6.2：PixelClk 由 BUFR 驱动仅限单时钟区，re-buffer 到
#                        BUFG 后下游逻辑（我们的流水线+rgb2dvi）可放全器件任意位置。
#    kRstActiveHigh = true —— 只暴露 aRst（高有效异步复位），与 rgb2dvi_0 的
#                        复位极性完全对称，board_top 里接统一的 ~rst_n。
#    kEmulateDDC = true —— 启用 DDC ROM，电脑才能读到 EDID 并按 720p 输出。
#    kDebug = false —— 关掉文档 7 说的两块调试 ILA（省资源、免去 ILA 子 IP 依赖）。
# =============================================================================

set IP_REPO ""
if {[info exists ::env(MOTION_IP_REPO)]} {
    set IP_REPO $::env(MOTION_IP_REPO)
} else {
    # 与 build_vivado.tcl 的默认一致：仓库同级 libs/vivado-library
    set SCRIPT_DIR [file dirname [file normalize [info script]]]
    set ROOT       [file normalize [file join $SCRIPT_DIR .. ..]]
    set IP_REPO    [file join $ROOT .. libs vivado-library]
    puts "提示：未设置 MOTION_IP_REPO，使用默认 $IP_REPO"
}

if {![file exists [file join $IP_REPO ip dvi2rgb component.xml]]} {
    error "IP 仓库里没有 dvi2rgb：$IP_REPO。请设置 MOTION_IP_REPO 指向含 ip/dvi2rgb 的 vivado-library。"
}

set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog -rebuild

create_ip -name dvi2rgb -vendor digilentinc.com -library ip -version 2.0 -module_name dvi2rgb_0

set_property -dict [list \
    CONFIG.kEmulateDDC     {true}  \
    CONFIG.kRstActiveHigh  {true}  \
    CONFIG.kAddBUFG        {true}  \
    CONFIG.kClkRange       {3}     \
    CONFIG.kEdidFileName   {dgl_720p_cea.data} \
    CONFIG.kDebug          {false} \
] [get_ips dvi2rgb_0]

generate_target all [get_ips dvi2rgb_0]

puts "dvi2rgb_0 关键参数（人工复核用）："
foreach p {CONFIG.kClkRange CONFIG.kEdidFileName CONFIG.kAddBUFG CONFIG.kRstActiveHigh CONFIG.kEmulateDDC CONFIG.kDebug} {
    catch { puts "   $p = [get_property $p [get_ips dvi2rgb_0]]" }
}
puts "dvi2rgb_0 生成完成。"
