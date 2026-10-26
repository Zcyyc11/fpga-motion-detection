# Q4 / UART / Tier1 review closeout (2026-10-26)

Confirmed fixes: full 16-bit threshold comparison; exact active-pixel coordinates; VS-edge and configured-height fallback; sync markers aligned with registered grayscale; new RTL reconciled on reused XPR; Tier1 auxiliary reset deasserted at its real active-low polarity.

The original Q4 update failed routed setup (-3.887ns). Narrow-width arithmetic alone still failed (-2.838ns). The selected implementation splits writeback into delta/rate, rounded-step and new-state stages, carrying address/valid with data. Read-side mask timing is unchanged. Both failed builds are retained.

Passing evidence: 262146 threshold comparisons, 17280 HDMI coordinate/data checks (normal/stuck-low/stuck-high VS), board-top sync alignment, 10000 continuous pipelined updates with exact addresses, 109011 strict mask samples over 180 frames, and actual UART bytes for one source-frame target. Source frame 3 maps to UART frame 6 with ID0 and box (8,8,15,15); normal and stuck VS variants passed. The pipelined variant was specifically repeated with stuck-low VS.

Tier1 uses PS FCLK0 125MHz / FCLK1 100MHz, AXI base 0x43C00000 and the existing registered bridge. Actual generated reset-IP simulation reproduced the old tied-low failure and passes tied-high release/reassertion/clock-loss cases. The first full PS build locked HDMI IP because board_part was selected after creation. A corrected isolated build selects PYNQ-Z2 before creating HDMI IP. Old projects and failed harness attempts are preserved. Build/timing/bit status must be read from the final release manifest.

Independent arithmetic/score oracles and protocol-field assertions supplement inspection; this is not a human review signature. Earlier context/breaking review attempts were limited and are not claimed as completed final reviews.

Evaluation is a software-model measurement, not board F1 or full CDnet RTL replay. The development stage was used to compare candidates. The later segment reuses the same scenes and is not an unseen-scene validation set. Traffic is rejected for shape mismatch; badminton has only 51 tail frames. Night performance regresses. Keep these limits with all metric statements.

Outstanding external gates: held-board HDMI/PL-UART evidence, SD/PYNQ compatibility, local startup and MMIO, long-run stability, power, actual video accuracy, and human cross-check. PMOD UART remains 115200; saturated 16-object/60fps traffic can drop complete frames. Tier1 is PS control/clock integration, without a DDR background algorithm.
