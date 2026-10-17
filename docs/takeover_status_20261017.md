# Full-16 resource takeover status

Development checkpoint, 2026-10-17. No delivered bit or board claim. Baseline build16@556d3fa. Resource and functional changes remain on the personal codex branch; no main merge or repository visibility change is authorized.

## Changes and measured evidence

- Line buffer patch independently matched 5760 output samples; OOC 193 LUT / 50 FF.
- Sequential track/alarm: independent reference model 240 frames / 364 births, natural ID wrap and dual-bank boundary checks passed; implementation review completed for declared bounds. OOC 3656 LUT / 3921 FF, synthesized setup slack 2.601 ns.
- AXI independent AW/W slots and read arbitration; write response now follows backend sampling. Split channels, legacy and stress cases pass. Legacy master race and premature BREADY withdrawal fixed.
- multi_bbox canonicalizes run aliases before label reuse, saturates count at 65535, and serializes frame finalization. Six baseline limit scenarios and new large-object/alias/720p-cadence full16 checks pass. OOC changed from 18770 LUT / -10.791 ns to 3386 LUT / +3.021 ns, 4 BRAM tiles. New finalization initially exposed an output-index width error; retained failure was fixed by explicit zero extension.
- UART three immutable frame banks, separate object/event synchronous memories, serial packing, atomic full-frame drops on overload. Default protocol/baud unchanged. Actual TX byte tests, legacy protocol, default divider and reset/capacity cases pass. OOC 224 LUT / 295 FF, synthesized setup slack 8.853 ns.
- PC receiver allows explicit --baud, default 115200. Receiver 48/48 and evidence-boundary 22/22 checks pass after using Python with OpenCV and task-local pyserial.
- Integrated small video/PS snapshot/UART runs: normal and event scenarios each compare 30 frames against independently captured UART inputs, zero differences. Simulation only.
- Build script supports MOTION_BUILD_DIR and refuses bit delivery on missing/negative setup/hold or DRC errors/critical warnings. Actual Tcl control-flow regression passes; full physical build still pending.

## Remaining gates

Full HDMI implementation at 74.25MHz, timing/DRC/bit hash, final source freeze and resource report, UART/new bbox independent review, manual line-two sign-off, physical board/video/serial evidence and competition material finalization. OOC reports are synthesized internal-path estimates with unconstrained module I/O, not routed or board timing.

INCLUDE_PS remains 0 in the board design. UART drop and bbox overflow are not yet exposed on the current board LEDs. The legacy snapshot uses a 32-cycle timer and the overlay publishes one metadata window later; detailed frame tagging/latency must be documented or corrected before asserting same-frame video correspondence. Long overload and final-frame event completeness remain explicit protocol constraints.

Local evidence paths and hashes are in takeover_evidence_20261017.json; full tool logs are retained outside Git. Board collaboration requirements are in the separate Chinese forwarding directory under the user's FPGA materials folder. The full build started on RTL commit 02fce44; later commits only change test/docs, and frozen_manifest.json must be checked before accepting results.
