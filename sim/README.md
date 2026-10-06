# sim/ — 仿真与验证

**职责**：证明功能正确性，并留下**可复核的证据**。官方硬门槛是"须板上跑通实测、不收纯仿真"，
所以这一层不是终点，而是**上板之前的过滤器** —— 先把逻辑错全部挡在这里。

| 子目录 | 放什么 |
|---|---|
| `tb/` | testbench |
| `wave/` | 仿真产物：逐帧包围盒 CSV、输出画面 PPM、掩码 PPM、对比图、演示视频 |
| `logs/` | 三步（xvlog/xelab/xsim）日志、与硬件模型的对比报告 |
| `xsim.dir/` | Vivado 仿真快照（生成物，可删） |

## 一键复现

```bat
python build\scripts\run_sim.py          :: 编译 + 仿真 + 判据
python src\ps\rtl_golden.py --compare sim\wave\bbox_rtl.csv --report sim\logs\model_vs_rtl.txt
python sim\view_sim.py                    :: 出对比图 + H.264 演示视频 + 叠加体检
```

必须按这个顺序：仿真要在模型之后对比，而对比图和视频都依赖仿真产物。

## 这一版仿真的产物与判据（当前实测结果）

| 产物 | 内容 | 判据 |
|---|---|---|
| `wave/bbox_rtl.csv` | 逐帧 `valid,x1,y1,x2,y2,cnt`（大像素坐标） | 与 `rtl_golden.py` **逐帧逐字段完全一致**（11/11 帧） |
| `wave/frame_*.ppm` | 流水线输出画面（含红框） | 画面里红框的实测像素范围 == CSV 行 `k-1` ×2（12/12 帧吻合） |
| `wave/mask_*.ppm` | 3×3 开运算后的运动掩码 | 数量等于 2 条带 × 8 宽 × 15 高 = 240 |
| `wave/sim_montage.png` | 每帧「输出画面 + 掩码」两联，纵向排列 | 人眼复核 |
| `wave/sim_demo.mp4` | 同上的 H.264 视频 | 人眼复核（Windows 自带播放器可直接打开） |
| `logs/model_vs_rtl.txt` | 模型对比报告 | 必须显示"完全一致" |

**为什么必须两路对照**（数字 + 画面），而不是只留一个：
- 只对数字 → 不知道红框有没有真的画到画面上（"算出来了"≠"显示出来了"）
- 只看画面 → 差 2 个像素肉眼看不出来，会把 bug 当成功

## 仿真尺寸与上板尺寸的关系

仿真用 **320×180**，上板用 **1280×720**，几何参数同比例缩小（`OBJ 40×30 / DX=16` ↔ `OBJ 160×120 / DX=16`）。

- **小尺寸定功能**：xsim 是事件驱动仿真，一帧 720p 要 100 万个时钟，跑几十帧就是上亿事件，会从秒级涨到分钟级
- **大尺寸定规模**：BRAM 占用、时序收敛要按 720p 在综合实现里看（见 `build/reports/`）
- ★ 两边的激励参数必须一致，否则比的是两段不同的输入，对照失去意义

## 纪律

1. 任何 RTL 改动后**必须**重跑 `run_sim.py`，且 `X 检查` 必须报 `x_hits=0`（流水线里不能有未知态）
2. 改动 `pattern_gen.v` / `downsample2x2.v` / `threshold.v` / `morph3x3.v` / `bbox.v` 任意一处，
   必须同步改 `src/ps/rtl_golden.py` 的对应函数 —— 两边的整数运算约定必须逐条一致
3. `xvlog` 用 `-sv`，所以模块名/端口名不能撞 SystemVerilog 关键字（`ref`、`bit`、`int` … 都踩过）
4. `run_sim.bat` 与 `.bat` 文件**必须纯 ASCII** —— cmd.exe 按 GBK 读 .bat，UTF-8 中文注释会把脚本拆散
