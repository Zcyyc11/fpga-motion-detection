#!/usr/bin/env python3
# mmio_readout.py —— 线一/线三 用：PS 侧经 AXI-Lite 读 PL 寄存器（甲通路 · Jupyter 跑）
#
# 用法（板子 Linux 里）：
#   from pynq import Overlay
#   ov = Overlay('board_top_axi.bit')          # 含 PS7 + AXI 互连的版本（当前 main 还没有）
#   %run mmio_readout.py
#
# ★ 前提：此脚本依赖"PS 存在"的构建。当前 main 的 bit 是纯 PL（无 PS/无 .hwh），
#   须先按 docs/axi_min_verify_plan.md 把 PS7 + AXI Interconnect + axi_lite_slave
#   接进工程、出 board_top_axi.bit + .hwh 后才能用。
# ★ 基址 BASE 由 Vivado Address Editor 分配，构建后从 .hwh 读，这里留占位。
import sys
from pynq import MMIO

# 寄存器偏移（与 docs/interface_freeze_table.md I4 + line1_uart_field_table_draft.md 一致，字节地址）
REG = {
    "THRESH":      0x00,   # 16 可写 绝对阈值（和域）
    "THRESH_REL":  0x04,   # 16 可写 相对阈值%
    "ALPHA_SHIFT": 0x08,   # 5  可写 背景学习率
    "LINE_X":      0x0C,   # 11 可写 警戒线 X（大像素域）
    "DWELL":       0x10,   # 16 可写 停留告警帧数
    "ENABLE":      0x14,   # 1  可写 1=背景建模 0=帧差法
    "STATUS":      0x18,   # 32 只读 bit31=UART丢包 / 低31位=状态(位分配见草案)
    "BBOX_X1":     0x1C,   # 16 只读 包围盒左上 X（大像素域）
    "BBOX_Y1":     0x20,   # 16 只读
    "BBOX_X2":     0x24,   # 16 只读
    "BBOX_Y2":     0x28,   # 16 只读
    "BBOX_CNT":    0x2C,   # 16 只读 前景像素计数（16位饱和）
    "BBOX_VALID":  0x30,   # 1  只读 本帧有目标
    "BBOX_FRAME":  0x34,   # 16 只读 所属帧号（与快照同锁存，伟博硬要求①）
}

BASE = 0x43C00000   # 占位：以构建后 .hwh 的 axi_lite_slave 实际基址为准


def u32(v):
    return v & 0xFFFFFFFF


def main():
    mmio = MMIO(BASE, 0x1000)
    print(f"[mmio] base=0x{BASE:08X}")

    # --- ① 写回读验证（§5.3 路线成立判据）---
    mmio.write(REG["THRESH"], u32(0x1234))
    rd = mmio.read(REG["THRESH"])
    print(f"[mmio] THRESH 写 0x1234 读回 0x{rd:08X} -> {'PASS' if rd == 0x1234 else 'FAIL'}")

    # --- ② 读 bbox 快照（线二加好 BBOX_* 后自动有效）---
    valid = (mmio.read(REG["BBOX_VALID"]) & 1)
    if valid:
        x1 = mmio.read(REG["BBOX_X1"]); y1 = mmio.read(REG["BBOX_Y1"])
        x2 = mmio.read(REG["BBOX_X2"]); y2 = mmio.read(REG["BBOX_Y2"])
        cnt = mmio.read(REG["BBOX_CNT"]); frm = mmio.read(REG["BBOX_FRAME"])
        # 大像素域 -> 像素坐标 ×2
        print(f"[bbox] frame={frm} box=({x1*2},{y1*2})-({x2*2},{y2*2}) "
              f"cnt(前景像素)={cnt} valid=1")
    else:
        print("[bbox] 本帧无目标 (valid=0) —— 记跳帧")

    # --- ③ 连续采样 N 帧，交 CSV（伟博要：CSV+帧号+运行记录配对）---
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    print(f"[mmio] 采样 {N} 帧...")
    with open("bbox_readout.csv", "w") as f:
        f.write("frame,x1,y1,x2,y2,cnt,valid\n")
        for _ in range(N):
            frm = mmio.read(REG["BBOX_FRAME"])
            x1 = mmio.read(REG["BBOX_X1"]); y1 = mmio.read(REG["BBOX_Y1"])
            x2 = mmio.read(REG["BBOX_X2"]); y2 = mmio.read(REG["BBOX_Y2"])
            cnt = mmio.read(REG["BBOX_CNT"])
            v = mmio.read(REG["BBOX_VALID"]) & 1
            f.write(f"{frm},{x1},{y1},{x2},{y2},{cnt},{v}\n")
    print("[mmio] 已写 bbox_readout.csv（与输入抓帧、bit 哈希、源码 SHA 配对交线三）")


if __name__ == "__main__":
    main()
