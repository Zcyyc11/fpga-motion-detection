# Full 16 target takeover plan

Baseline: build16 at 556d3fa96b8d4498ca9601d696343002ed8c469c. Work branch: codex/full16-resource-20261017.

1. Intake and acceptance (10%): preserve three captain documents and patch hashes outside repository; verify claims against source. Capacity ceiling 53200 LUT, setup and hold timing >=0, functional regressions, actual board evidence. 26600 is a team aspiration. No fabricated board sign-off.
2. RTL (40%): independently verify line_buf patch; serialize track and UART; repair duplicate/live ID allocation and lifecycle alarm; repair independent AXI channels; diagnose long 16-target input overload and enforce bounded throughput/capacity behavior. Preserve external ports/protocol defaults. Optional high-baud build requires explicit deployment coordination.
3. Regression and review (20%): fail-before/pass-after evidence; full16 including MIN_CNT64, overflow/bridge/reuse, zero frames, 257 lifetimes, live IDs, AXI ordering/backpressure, raw UART decode, integrated real video timing. Separate specification and implementation review; human teammate sign-off remains external.
4. Build (20%): module OOC for area/timing then frozen full HDMI source build, synth/place/route/DRC/setup/hold checks, bit hash and reproducible command. Historical reports/bit are never accepted for new RTL. Keep full tools output outside repository.
5. Delivery/board (10%): English-named source-repository docs, Chinese forwarding copies outside source repo; line-one/line-two collaboration and hardware evidence instructions. Push personal branch, review before merging main. Actual hardware belongs to captain and must return original captures/logs.

Context usage cannot be read reliably. Checkpoint at natural milestones before creating a continuation chat; record active processes/output directories, current SHA, failures and next action. Progress is weighted milestones, not elapsed time.

Risks discovered at intake: default MIN_CNT64 continuous 16-run rows exceed sample FIFO service rate; captain USB-UART claim does not establish PMOD TX connectivity; latest captain reply says scoring rubric not obtained, so older numeric weights are not authoritative.
