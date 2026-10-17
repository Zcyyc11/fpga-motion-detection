# UART bounded frame storage

The external ports and byte formats remain unchanged. Default uart_tx BAUD_DIV is 868; md_pipeline uses 645 for approximately 115200 baud at 74.25 MHz.

Three banks hold frames in order. Each bank holds at most 16 object records and 16 event records in separate synchronous-read, single-write-port memories. Simultaneous object/event inputs and consecutive records are accepted. A frame_tick seals the preceding window; same-cycle records belong to the new window. A sealed bank is immutable until its final UART stop bit finishes. Headers precede all objects, then all events for that frame. Checksums accumulate one byte at a time.

If either record capacity is exceeded, the entire unsealed frame is discarded and drop pulses. If all banks are occupied at a boundary, the new frame is not captured; a drop pulse reports that skipped window at its closing boundary. Recovery waits for another boundary and never emits a partial header/body. Frame numbers continue through discarded frames. Reset aborts any in-flight byte/frame and restarts numbering; the receiver must start a new capture after reset.

115200 baud with 8N1 carries at most 11520 bytes/s. Sixteen targets plus a header need 229 bytes/frame, or 13740 bytes/s at 60 fps before events. Bounded buffering cannot remove that deficit; full frames are intentionally dropped under sustained overload. Higher baud is a candidate deployment configuration, not confirmed hardware compatibility. Protocol lacks event count/end-of-frame, so a receiver cannot certify complete events in the final frame without a subsequent header.

Evidence (local, not board): uart_red demonstrates original failure; uart_green_3 and uart_default_baud_2 pass actual-wire byte parsing, simultaneous bursts, tick+valid, empty frames, sustained overload, 17-record rollback and active reset. uart_legacy passes prior protocol test. uart_ooc: 224 LUT, 295 FF, synthesized internal setup slack 8.853 ns at 13.468 ns; not routed timing. Independent review of the new UART implementation is still pending after reviewer usage limit.
