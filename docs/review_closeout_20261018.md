# Independent review closeout, 2026-10-18

Review target: build16@556d3fa..04a11f3. Four separate read-only reviews followed the installed code-review context, testing, breaking-changes and change-size skills. These are AI source/evidence reviews, not teammate or board sign-off.

1. **P2 compatibility finding** — `src/rtl/multi_bbox.v:62`: SF_DEPTH was inserted before MAX_RUN. A positional instance `#(64,16,4)` now means SF_DEPTH=4 rather than MAX_RUN=4. All in-repository instances use named parameters; the frozen board build is unaffected. Existing external positional instances must use named parameters before reuse. Kept visible rather than changing frozen RTL during physical acceptance; no claim of universal external positional compatibility.
2. **Video frame association gap** — `sim/takeover/check_cosim.py:16`: video/time columns are not part of the expected table. Existing comparisons establish UART input-to-wire fidelity, not source-video/BBOX/alert frame identity. The overlay publishes the preceding shadow window; the optional PS snapshot labels it with current fid. This remains an explicit deployment limitation; INCLUDE_PS=0 in board_top.
3. **UART congestion recovery coverage** — `sim/takeover/uart_contract_tb.sv:63`: old pressure traffic reused payloads and reset after pressure. Added `uart_recovery_tb.sv`: distinct per-frame IDs/coordinates under congestion and successful frame25 after drain without reset. `uart_recovery09/result.json` passes. Initial test-code replacement syntax failure retained in uart_recovery08, corrected without changing RTL.
4. **Review size** — 31 files / 2706 changed lines, including 1141 RTL lines; historical commit 4a834b1 mixed multiple modules. Review by subsystem: build gate, AXI, bbox, alarm, track, UART, integration, then evidence. Do not rewrite published history only to meet a review-size suggestion.

No new deterministic UART or bbox functional fault was established by these read-only reviews. UART test snapshots match current SHA. bbox_suite_green05 differs only in line endings; bbox_serial_green04 predates the explicit output-ID zero extension. Historical fixed failures are not current defects.

Additional fresh tests: standard 1280x720 / 1650x750 cycle cadence integration with UART_DIV=645 passed; 29 sealed UART frames compared field-for-field with independent UART input observation, zero differences. This test has a scaled 100MHz simulation clock but standard raster cycle counts; it does not model TMDS electrical behavior.

Physical board origin, teammate sign-off and exact arbitrary-video frame mapping remain unverified.
