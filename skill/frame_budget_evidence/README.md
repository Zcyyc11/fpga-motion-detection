# Frame budget and source-evidence workflow

Scope: bounded frame-based RTL with a per-frame processing window; reusable beyond motion detection. This is not a PYNQ framework bring-up skill.

1. Freeze exact source/configuration SHA256 before synthesis. Keep failures in unique directories, never overwrite old output.
2. Derive cycle throughput and byte bandwidth separately. Example: 16 targets*14+5=229 bytes; 60fps requires13740B/s, while115200/10=11520B/s. No FIFO can remove sustained excess. Specify atomic drop behavior and observable gaps.
3. Serialize per-frame state updates only after budgeting the worst-case cycles. Test tick+valid, capture while previous processing, zero records, capacity boundary, lifecycle wrap and reset mid-output.
4. Capture the physical TX pin independently of the input-record observer. Compare counts, IDs, coordinates, order and checksum. Use distinct payloads during pressure, then drain and prove recovery without reset.
5. Add a separate source-scene formula or independent image reference for frame attribution. Input-to-wire equality does not establish source-video identity. Characterize overlay/snapshot delay and label semantics.
6. Accept resource/timing only from the frozen complete design. OOC is a diagnostic. Fail closed on missing/negative setup or hold and DRC errors/critical warnings before writing bit. Hash the delivered bit and preserve logs.

Verified examples: takeover UART recovery09;720p08 input-to-wire29 frames;scene720p09 track12/snapshot5;full_build02 routed setup+0.475ns/hold+0.033ns. Initial recovery08 test compiler failure was retained. Commands and exact inputs are in sim/takeover and external manifests.

Failure boundaries: arbitrary source video needs its own reference; serial bandwidth overload means dropped frames; port/parameter changes require independent review; reported timing does not prove electrical HDMI or a physical board. Generic helpers do not certify CDC correctness or physical origin. Hardware evidence must name the exact bit SHA and original acquisition files.
