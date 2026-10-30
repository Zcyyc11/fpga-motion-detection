# -*- coding: utf-8 -*-
"""为 74.25 MHz 像素时钟解 MMCM 参数（结果硬编码在 src/rtl/board/clock_74m25.v）。

为什么要写成一个脚本而不是直接写死三个数
----------------------------------------
7 系列 MMCM 的三个参数都是 **0.125 步进**：
    CLKFBOUT_MULT_F    ∈ [2, 64]      步进 0.125
    DIVCLK_DIVIDE      ∈ [1, 106]     整数
    CLKOUT0_DIVIDE_F   ∈ [1, 128]     步进 0.125
    f_out = f_in × MULT_F / (DIVCLK_DIVIDE × CLKOUT0_DIVIDE_F)
    f_VCO = f_in × MULT_F / DIVCLK_DIVIDE，且必须落在 [600, 1200] MHz（Artix-7 -1 级）

要求 74.25 MHz 精确（720p60 = 1650×750 总时序，74.25e6/1237500 = 正好 60.00 Hz）。
"能不能整除"不是靠感觉判断的：
  只试 DIVCLK_DIVIDE=1 会得出"做不到"的错误结论；
  放开 DIVCLK_DIVIDE 之后，Dv=4 就有精确解
      M/D0 = 74.25×4/125 = 2.376 = 297/125  →  M = 37.125、D0 = 15.625
      f_VCO = 125×37.125/4 = 1160.156 MHz ∈ [600,1200] ✅
这个教训值得留着：**参数要解出来，不要靠试，也不要靠感觉说"差不多就行"。**

用法：
  python build/scripts/mmcm_search.py
"""

import io
import os

FIN = 125.0                 # PYNQ-Z2 PL 独立参考时钟
VCO_MIN, VCO_MAX = 600.0, 1200.0
TARGET = 74.25              # 720p60 像素时钟
H_TOTAL, V_TOTAL = 1650, 750


def search(target=TARGET, fin=FIN):
    best = None
    for dv in range(1, 107):
        for mi in range(16, 64 * 8 + 1):
            M = mi / 8.0
            vco = fin * M / dv
            if not (VCO_MIN <= vco <= VCO_MAX):
                continue
            for di in range(8, 128 * 8 + 1):
                D0 = di / 8.0
                f = vco / D0
                err = abs(f - target)
                if best is None or err < best[0]:
                    best = (err, M, dv, D0, vco, f)
    return best


def main():
    err, M, dv, D0, vco, fout = search()
    lines = [
        "输入时钟      : %.3f MHz" % FIN,
        "目标像素时钟  : %.3f MHz" % TARGET,
        "",
        "CLKFBOUT_MULT_F   = %.3f" % M,
        "DIVCLK_DIVIDE     = %d" % dv,
        "CLKOUT0_DIVIDE_F  = %.3f" % D0,
        "VCO               = %.3f MHz  (允许 %.0f ~ %.0f)" % (vco, VCO_MIN, VCO_MAX),
        "实际像素时钟      = %.3f MHz" % fout,
        "频率偏差          = %+.6f MHz (%+.6f %%)" % (fout - TARGET,
                                                     (fout - TARGET) / TARGET * 100),
        "",
        "总时序            = %d x %d" % (H_TOTAL, V_TOTAL),
        "刷新率            = %.4f Hz" % (fout * 1e6 / (H_TOTAL * V_TOTAL)),
        "",
        "★ 若偏差为 0，报告里可以直接写 74.25 MHz / 60.00 Hz；",
        "  若不为 0，**必须写实际值**，不能照抄标称值。",
    ]
    txt = "\n".join(lines) + "\n"
    print(txt)

    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mmcm_result.txt")
    with io.open(dst, "w", encoding="utf-8") as f:
        f.write(txt)
    print("已写出: %s" % dst)


if __name__ == "__main__":
    main()
