# Q4 / UART / Tier1 review closeout (2026-10-26)

Confirmed fixes: full 16-bit threshold comparison; exact active-pixel coordinates; VS-edge and configured-height fallback; sync markers aligned with registered grayscale; new RTL reconciled on reused XPR; Tier1 auxiliary reset deasserted at its real active-low polarity.

The original Q4 update failed routed setup (-3.887ns). Narrow-width arithmetic alone still failed (-2.838ns). The selected implementation splits writeback into delta/rate, rounded-step and new-state stages, carrying address/valid with data. Read-side mask timing is unchanged. Both failed builds are retained.

Passing evidence: 262146 threshold comparisons, 17280 HDMI coordinate/data checks (normal/stuck-low/stuck-high VS), board-top sync alignment, 10000 continuous pipelined updates with exact addresses, 109011 strict mask samples over 180 frames, and actual UART bytes for one source-frame target. Source frame 3 maps to UART frame 6 with ID0 and box (8,8,15,15); normal and stuck VS variants passed. The pipelined variant was specifically repeated with stuck-low VS.

Tier1 uses PS FCLK0 125MHz / FCLK1 100MHz, AXI base 0x43C00000 and the existing registered bridge. Actual generated reset-IP simulation reproduced the old tied-low failure and passes tied-high release/reassertion/clock-loss cases. The first full PS build locked HDMI IP because board_part was selected after creation. A corrected isolated build selects PYNQ-Z2 before creating HDMI IP. Old projects and failed harness attempts are preserved. Build/timing/bit status must be read from the final release manifest.

Independent arithmetic/score oracles and protocol-field assertions supplement inspection; this is not a human review signature. Earlier context/breaking review attempts were limited and are not claimed as completed final reviews.

Evaluation is a software-model measurement, not board F1 or full CDnet RTL replay. The development stage was used to compare candidates. The later segment reuses the same scenes and is not an unseen-scene validation set. Traffic is rejected for shape mismatch; badminton has only 51 tail frames. Night performance regresses. Keep these limits with all metric statements.

Outstanding external gates: held-board HDMI/PL-UART evidence, SD/PYNQ compatibility, local startup and MMIO, long-run stability, power, actual video accuracy, and human cross-check. PMOD UART remains 115200; saturated 16-object/60fps traffic can drop complete frames. Tier1 is PS control/clock integration, without a DDR background algorithm.

## Full PS synthesis follow-up

The first board-order-corrected Tier1 synthesis reported Synth 8-6859/8-6858 on uart_drop_sticky. Inspection found that the configuration-register reset block and a separate sticky-status block both drove the same register. Post-synthesis functional simulation independently reproduced STATUS[31]=0 after a drop pulse. The fix removes the redundant assignment from the configuration reset block; the dedicated sticky block still resets, sets, holds and clears it. The same post-synthesis test passes after the fix, with no multi-driver message. Simulation-only tests before synthesis did not reveal this hardware mapping defect.

Pure PL gated bit is complete in full_q4_pipe: WNS +0.073ns, WHS +0.050ns, 17767 LUT, 15589 FF, 117.5 BRAM tiles, 1 DSP. SHA256 648c16a7a8b528e0e2cdae504714d36a79e2d147172a93e44f6b12886cb0bf74. The repaired status register is only active with INCLUDE_PS=1; the pure-PL bit remains the tested artifact. Tier1 regs_r3 is a separately frozen build and must pass its own physical gates before packaging.
