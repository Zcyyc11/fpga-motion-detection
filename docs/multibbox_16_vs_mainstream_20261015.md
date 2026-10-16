# 16 目标 multi_bbox vs 主流/大佬做法 对比评估（2026-10-15）

> 面向 PYNQ-Z2（xc7z020clg400-1）。评估对象：`line2/serial-wip` @ 8e94241 的 16 目标版
> `multi_bbox.v`（MAX_LABEL=16 / MAX_RUN=16 / SF_DEPTH=256 + o_overflow）。
> 结论供线一（架构）/线二（算法）决策，是否升级由徐一夫复出后定。

---

## 一句话结论

**算法本身是主流正统（RLE + 并查集 CCL，Appiah2010 / 北理工 2010 同宗），对 PYNQ-Z2 可行；
真正偏离主流的是"串行化省 LUT"这个工程取舍——它引入了 FIFO，而 FIFO 静默丢样正是取舍的副产物。
不建议临截止（11-04）换用外部 IP；当务之急是验收我们自己的 16 版，而不是重写。**

---

## 我们的 16 目标设计到底是什么

- **算法**：游程编码（RLE）+ 并查集（parent[] 数组）+ 包围盒累积。输入是 **bbox.v 输出的游程流**
  （bbox.v 已做帧差+形态学并抽成 run），不是裸像素流。
- **状态机**：ST_IDLE（正常流式）/ ST_MATCH（串行匹配上一行游程，每拍 1 个）/ ST_ALLOC（分配/合并标签）/
  ST_FINISH（行/帧收尾）。合并判据 = 行间 x 区间重叠（`pr_s<=close_e && pr_e>=close_s`，4-连通）。
- **徐一夫的取舍**：原版 16 路并行匹配 → LUT 83,286（182% 爆）；改串行（每拍 1 次匹配）→ LUT 19,048/35.8%。
  代价：匹配期间新到的 in_valid 要缓存 → **SF_DEPTH FIFO**；原深度 32 太小 → 满时静默丢样（16 目标只出 9 框）。
- **已修**：SF_DEPTH 32→256 + 扩位 + `o_overflow` 粘存标志（丢样可见，供 PS 感知）。
- **验收现状**：只过 **OOC 资源关**（19,048 LUT/35.8%）；**16 目标满配功能从未通过**（f7f4134 复核是旧并行版 9 框；
  串行版修 FIFO 后未复跑 `tb_multi_bbox_stress`）。

---

## 主流/大佬实现对比表

| 实现 | 平台 | 核心做法 | 与我们的关系 |
|---|---|---|---|
| **niuwe/connect_domain_fpga** | FPGA/Verilog | 单遍扫描+并查集等效表，**每拍 1 像素**，流水线流处理，只缓存一行 label（simple dual-port RAM），参数化 WIDTH/HEIGH/RAM_DEPTH，算面积+质心 | **架构最像"正统在线 CCL"**：1/时钟、仅一行缓存、**无帧 FIFO**。但它吃**裸像素流**，我们吃**游程流**，接口不同不能直接换 |
| **Kryon（yinedeng / hhhhhli）** | FPGA | 并行流水线 CCL，**仅缓冲一行、不用 DDR** | 同上，证明"一行缓存就够"是在线 CCL 的常态；我们的 FIFO 是串行化特有的 |
| **KOTerra/utcn-…on-PYNQ-Z1** | PYNQ-Z1(Zynq-7000) | Verilog/VHDL CCL，~211× 快于 Python | **同族板子已验证可行**，佐证 PYNQ-Z2 跑 CCL 没问题 |
| **2cc2ic/Motion-Detection-…** | **PYNQ-Z2** | 帧差 + DMA + AXI4-stream 运动检测 | **同板参考**：可借鉴整链 AXI/DMA 组织与 Zynq-7020 资源预算，但算法路线不同 |
| **Appiah2010（CVIU）** | 论文 | **RLE-based CCL 直接与背景差分集成**，避免中间二值图，用 run 代替像素 + 等效表解析 | **我们架构的理论正源**——"帧差→游程→连通域"就是它的模型 |
| **北理工 2010（BIT 学报）** | 论文 | RLE + 并查集（加权 union + 路径压缩），O(nα(n)) | 我们算法的直接同宗 |
| **MDPI Algorithms 2025** | 综述 | RLE 合并判据：行间 x 区间重叠（4-连通） | 与我们的合并规则一字不差 |
| **面向FPGA的连通域快速标记** | 论文 | 逐像素扫描 + 游程统计，无标记表单遍 | 同类"扫描+游程"流派 |

---

## 我们符合主流吗

- **算法：符合。** RLE+并查集 CCL 是有论文、有开源、专门为"运动检测/背景差分"场景优化的正统流派
  （Appiah2010 的核心贡献就是把它和背景差分缝在一起）。不是野路子。
- **工程：偏离了"在线 CCL 每拍 1 像素、只缓存一行"的常态。** 主流（niuwe/Kryon）连续流式、无帧 FIFO；
  我们为把 LUT 从 182% 压到 35.8% 而串行化匹配 → 引入 FIFO → FIFO 成了 bug 温床。
  **换句话说：我们为了省资源走了一条需要 FIFO 的捷径，而主流根本不需要这个 FIFO。**

---

## 能不能用大佬代码升级优化

**直接替换：不可行。** niuwe/Kryon 吃裸像素流、自带行缓存，换进来要把接口从"游程流"退回"像素流"，
并重接 bbox.v + 动已冻结的 I3 契约——离截止 11-04 太近、风险高。

**值得借鉴（按性价比排序）：**
- **先别借，先验**：我们的算法已主流，缺口是"16 版功能没验收"——这是**测试问题不是换码问题**。
  跑通 `tb_multi_bbox_stress`（16 目标满配 → 16 框全出 + 面积守恒）比换任何外部 IP 都值。
- **引用 lineage 加分**：报告里写明 RLE+并查集 CCL（Appiah2010 CVIU；北理工 2010）与背景差分集成——
  直接支撑"算法主流/有据"的评分项。
- **niuwe 的流式纪律**：若将来要"去 FIFO 化"重架构（回到每拍连续处理），拿它当参照，但那是线二的大改、涉接口冻结。
- **2cc2ic（PYNQ-Z2）**：参考整链 AXI/DMA 组织与 Zynq-7020 资源预算。
- **Vitis HLS CCL**：仅当需快速试另一路线时做原型，不进最终 RTL。

---

## 缺口与下一步

- **bit 正在出（16 目标）**：工作树已切到 `build16`（MAX_LABEL=16/16/SF_DEPTH=256），Vivado 在跑。
  但 **16-bit ≠ 能正确出 16 框**——它只证明可综合 + 资源够。
- **硬门 = 压力台验收**：徐一夫复出须复跑 `tb_multi_bbox_stress`。过了，我们的设计已主流且够用，无需换码；
  不过，再考虑借 niuwe 结构重架构（涉 I3 冻结，线一/线二共决）。
- **一个待核实的点**：所谓 "182% LUT" 是**模块级 OOC** 数字；整链真实占用要看这轮 bit 的利用率报告——
  若整链本就没超，串行化（及它带来的 FIFO）可能是**不必要的**。bit 出来后以 `report_utilization` 为准。

---

## 参考

- https://github.com/niuwe/connect_domain_fpga
- https://github.com/yinedeng/Kryon ；https://github.com/hhhhhli/Kryon
- https://github.com/KOTerra/utcn-conected-component-labeling-on-PYNQ-Z1
- https://github.com/2cc2ic/Motion-Detection-System-Based-On-Background-Reconstruction
- Appiah2010 CVIU: Accelerated hardware object extraction and labelling（RLE-based CCL）
- 北京理工大学学报 2010: New Algorithm for Binary CCL Based on RLE and Union-Find Sets
- MDPI Algorithms 2025, 18(6):344: A Novel Connected-Components Algorithm for 2D Binarized Images
