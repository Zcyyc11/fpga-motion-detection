# Board-candidate checkpoint, 2026-10-18

Supersedes takeover_status_20261017.md for current build/review status. RTL remains frozen at 02fce44; the 04a11f3 source checkpoint and subsequent test/document work have identical frozen source/configuration files.

Full HDMI board_top, Vivado2025.2, xc7z020clg400-1, MODE_BG=0 INPUT_SEL=1 INCLUDE_PS=0, default UART_DIV645: synthesis and implementation completed; bit-stage real setup/hold and DRC query gates passed. Bitgen completed with zero errors/critical warnings. Routed WNS+0.475ns, WHS+0.033ns, TNS/THS0; LUT17475, FF15435, BRAM36-equivalent85.5, DSP1.

Bit SHA256: `67bbe9a10108b13d70b49740b3a85b8723a00bc101ed6468e6f763f81a793af3`, 4045685 bytes. Original D:/fpga_takeover_20261017/full_build02/bitstream/board_top.bit. Full logs and frozen_manifest are retained outside Git; seven reports and release manifest are committed under report/takeover_20261018. The routed DRC has Warning entries only. Two implementation log critical warnings concern absent optional dvi2rgb ILA module constraints; not silently counted as zero implementation-log warnings. Bit-stage DRC and bitgen are clear.

Fresh tests: uart_recovery09 passes varying pressure-frame payloads and non-reset recovery; cosim_720p08 passes standard1650x750 cycle cadence and UART_DIV645; cosim_720p_check08 compares29 sealed wire frames exactly. scene_720p09 independently checks12 target outputs and5 display snapshots against moving-scene geometry. In this controlled scene, source N is tracked in N+1 and displayed in N+2. Optional PS snapshot labels retain current fid; no arbitrary-video same-frame identity claim. 100MHz simulation scales timing while keeping raster/baud cycle counts; physical HDMI recovery/electrical behavior needs a board.

Independent read-only AI reviews of UART/bbox, testing, compatibility and size completed. Findings/actions are in review_closeout_20261018.md, including external positional-parameter compatibility caveat. Current repository uses named instances, so frozen deployment is unaffected. Human line-two sign-off is not supplied by AI reviews.

Handoff candidate package is in the user's materials root under 整体接手交付_20261018. It includes bit, hashes, English-named reports/logs/evidence, burn_candidate.tcl, Chinese forwarding instructions and pre-board design report. Existing repository skill package is extended with frame_budget_evidence. Complete raw AI dialogue export is still a separate submission step; the process summary is not presented as that export.

Local original guide PDF was found and page25 rendered: guide weights30/20/20/15/15 are supported by this local PDF; latest separate scoring detail and official deadline remain unverified (website timeout). No main merge, public visibility change or hardware claim.

Remaining external acceptance: exact-bit JTAG/video/UART/photos, source clip hashes and playback alignment, long lifecycle evidence, line-two manual review, latest official scoring/deadline. Default115200 full16@60 overload drops whole frames; no921600 deployment. UART drop/bbox overflow are not mapped to LEDs. OptionalPS/frame tag limitations are disclosed; this board bit uses noPS.
