# Tier1 CDC follow-up — 2026-10-26

The regs_r3 synthesis interruption coincides with a Windows shutdown: System event 1074 at 11:18:16, synthesis error marker at 11:18:17, followed by shutdown events 6006/109/13. No synthesis checkpoint exists for that attempt. Retain the attempt; do not call it a hardware design failure or claim a completed synthesis.

The snapshot ack synchronizer had no reset assignment. The old RTL fails `snapshot_reset_red` with `FAIL ack synchronizer not reset`; adding the reset and ASYNC_REG attributes makes `snapshot_reset_green` pass 100 independent-clock snapshots including mid-run reset. `snapshot_independent_reset` also passes 100 snapshots with pixel-only, both-domain and AXI-only reset/recovery. Reset does not promise preservation of an in-flight snapshot. These tests are digital simulation, not metastability or board validation.

The Tier1 XDC bounds only first-stage synchronization D pins (10 ns datapath-only) and the req/ack-held snapshot bus (10 ns datapath-only, 5 ns skew). It does not suppress entire clock groups. The constraints are read late during implementation; the actual routed design must retain the endpoint coverage, ASYNC_REG and drop status chain, have no user-pipeline Critical CDC, and satisfy the skew report. Original setup/hold/DRC gates remain mandatory. Existing dvi2rgb reset/fanout Critical findings are reported and remain an explicit limitation.

The skew-report command and reporting semantics were checked against AMD UG835: https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/report_bus_skew . Local Vivado 2025.2 documentation and retained report formats were additionally checked by the test reviewer.

Four independent AI review roles covered context applicability, breaking changes, testing, and change size. Context-injection-specific checks were not applicable to RTL. No additional compatibility or size finding was reported. This is not a human cross-check signature.

One actionable review finding was addressed: the original patch placed the gate only in the full-build entry point, so the public bit-only resume entry could bypass it. The common `stage_bit` now reads the actual project top and invokes the Tier1 gate before writing a bit. The full-build wrapper no longer duplicates it. The running r4 frozen source retains its earlier full-build gate; it is not modified during execution. Later resume scripts must use the corrected common entry, with their own provenance recorded.

Gate parser tests using retained report text and mocked Vivado queries reject the user Critical, negative skew, missing skew report, and missing ASYNC_REG. Independent review also exercised missing drop stage and insufficient endpoint coverage. These are parser/control-flow tests and do not replace the r4 routed checks.

At this checkpoint, `full_tier1_cdc_r4` is still running. No Tier1 bit, positive timing or all-CDC closure is claimed. The source build manifest and eventual release summary are authoritative. Pure PL's previously gated bit remains unchanged.

Runtime multi-bit configuration is synchronized per bit and is not atomic. Configure before starting video; ENABLE selects the algorithm and is not a pause control. After changing settings, restart/re-warm the test before scoring. Board SD/PYNQ/MMIO, HDMI/UART, long-run, power and human signoff remain external acceptance tasks.
