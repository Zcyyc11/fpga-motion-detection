<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual onboarding updates. -->

# 入门：从零跑通

> 目标：**你自己照着敲一遍就能出结果**，不用问任何人。
> 卡住了再看文末「常见问题」，或者直接把完整报错发群里 —— 别只说「跑不了」。

---

## 先选一条路（★ 30 秒看完再往下）

| 你有 CDnet 数据集吗？ | 走哪条 |
|---|---|
| **有**（0.96 GB） | **A 路**：第 0 → 5 步全做，能跑检测评测、能算官方口径成绩 |
| **没有 / 懒得下** | **B 路**：跳过第 2 步，其余照做。**一样能理解整个项目、能干活** |

### ★ B 路：现在就能跑的三条（**不需要数据集**）

```bash
# ① 跑一遍"我们算法在硬件里的等价物" —— 帧差法（输出 bbox_rtl.csv）
python src/ps/rtl_golden.py

# ② 换成背景建模再跑一次，对比两者差在哪
python src/ps/rtl_golden.py --mode bg

# ③ 跟踪 + 越界告警 —— 用仓库自带的合成考场 track_cross.avi
python src/ps/multi_track.py --source clean --alarm --line-x 640 --outdir out_clean

# ④ RTL 仿真 + 看波形（需要 Vivado）
python build/scripts/run_sim.py
```

这四条**全都不需要 CDnet**，只需要 Python 环境（第 1 步）。
跑通它们，你就已经能看懂"这项目在干什么"了。检测评测那条（A 路）随时补上就行。

> ⚠️ **别随手跑这两个**：`data/golden/make_figures.py` 和
> `data/golden/make_test_clip.py` 会**覆盖仓库里已归档的插图与合成素材**，
> 跑完 `git status` 就会多出改动。想重新生成请先确认，或者跑完
> `git checkout -- data/golden/` 再提交。

---

## 第 0 步 · 拿到代码

**【在仓库根目录执行】**

```bash
git clone https://github.com/Zcyyc11/fpga-motion-detection.git
cd fpga-motion-detection
```

嫌麻烦也可以在网页上点 `Code` → `Download ZIP`，解压后一样用。

---

## 第 1 步 · 装 Python 环境

```bash
python -m venv .venv
.venv\Scripts\activate
pip install numpy opencv-python matplotlib
```

**验证：**

```bash
python -c "import numpy, cv2; print('OK')"
```

看到 `OK` 就过了。

---

## 第 2 步 · 准备 CDnet 数据集（★ **只有 A 路需要**，B 路跳过）

只有 `algo_lab.py` / `cdnet_official.py` / `algo_ab.py` 需要它。
**跟踪、告警、RTL 仿真、报告插图都不需要。** 没有它先走 B 路，回头再补。

### 2.1 从哪下

CDnet 2014 数据集（全集 53 段 / 11 类，约 0.96 GB）：

| 用途 | 地址 |
|---|---|
| 官网首页 | <http://changedetection.net/> |
| 数据下载页 | <http://jacarini.dinf.usherbrooke.ca/dataset/> |

本仓库只用到其中 **12 段 / 7 类**（清单见文末）。完整数据集很大，**不建议下载全的**：
只要挑下面 12 段所在的类别即可。

### 2.2 解压后应该长这样

```
cdnet2014\                          ← ★ --data-root 指的是这一级
├─ baseline\
│  ├─ highway\
│  │  ├─ temporalROI.txt            ← 有这个文件，脚本才认得出这条序列
│  │  ├─ input\                     ← 帧图（jpg）
│  │  └─ groundtruth\               ← 真值（png）
│  ├─ office\  ...
│  └─ pedestrians\ ...
├─ badWeather\snowFall\ ...
├─ cameraJitter\badminton\ ...
├─ cameraJitter\traffic\ ...
├─ dynamicBackground\canoe\ ...
├─ dynamicBackground\fountain02\ ...
├─ intermittentObjectMotion\streetLight\ ...
├─ nightVideos\busyBoulvard\ ...
├─ shadow\busStation\ ...
└─ shadow\peopleInShade\ ...
```

★ **最容易搞错的一点**：`--data-root` 要指向 **`cdnet2014\` 这一级**，
也就是**里面能直接看到 `baseline\`、`shadow\` 这些类别目录**。
不要指到它的子目录（`baseline\`），也不要指到它的上级目录。

### 2.3 告诉脚本数据在哪（两种方式，任选）

**方式一：命令行参数（优先级最高）**

```bash
python src/ps/algo_lab.py --data-root "<你的数据集目录>\cdnet2014" --list
```

**方式二：环境变量（省得每次都写）**

> ⚠️ **cmd 与 PowerShell 的写法不一样，别互相照抄。**
> 在 PowerShell 里写 `set CDNET_ROOT=...` 是无效命令（不报错，但变量没设上）。

```bat
rem ---- cmd（命令提示符）----
set CDNET_ROOT=<你的数据集目录>\cdnet2014
```

```powershell
# ---- PowerShell ----
$env:CDNET_ROOT = '<你的数据集目录>\cdnet2014'
```

> 想永久生效（新开窗口也不用重设）：
> cmd → `setx CDNET_ROOT "<你的数据集目录>\cdnet2014"`
> PowerShell → `[Environment]::SetEnvironmentVariable('CDNET_ROOT','<你的数据集目录>\cdnet2014','User')`
>
> Linux / macOS：`export CDNET_ROOT=/path/to/cdnet2014`
>
> 确认到底设上没有：cmd 用 `echo %CDNET_ROOT%`，PowerShell 用 `echo $env:CDNET_ROOT`。

> ★ **优先级：命令行 `--data-root` > 环境变量 `CDNET_ROOT`。**
> 两者都没给时，脚本会**明确报错并告诉你怎么配**（退出码非 0），不会默默跑出一个空结果。
>
> ★ 本项目**刻意不提供默认路径** —— 代码里曾经硬编码某个人的磁盘路径，
> 换个机器就静默跑不了，那是最难查的一类问题。
>
> ★ **支持中文路径和带空格的路径**，但 shell 里记得**加引号**。
>
> 这一点是**实测过**的（不是"应该可以"）：`build/scripts/test_data_guard.py`
> 会把同一份数据分别放到纯英文 / 中文 / 带空格 / 中文+空格四个目录下各跑一遍，
> 再比对逐帧指标文件，四个必须**逐字节一致**。
>
> 顺带说清一个坑：Windows 上 `cv2.imread` 遇到**非 ASCII 路径会静默返回 None**
> （不报错，就是读不到），所以本项目统一走 `cdnet_io.imread()`
> —— 先用 Python 的 `open()` 读字节、再交给 `cv2.imdecode` 解码。
> 带空格的路径反而没问题。

### 2.4 验证配置对了

**【仓库根目录】**

```bash
python src/ps/algo_lab.py --data-root "<你的数据集目录>\cdnet2014" --list
```

| 输出 | 意思 |
|---|---|
| `数据根目录：…` + `来源：…` | 它最终用了哪个目录、来源是命令行还是环境变量 |
| `可用序列 (12)：` 下面列出 12 条 | ✅ **配对了** |
| 退出码非 0 + 一段中文说明 | ❌ 目录不对、或里面没有序列 —— **照它说的改** |

---

## 第 3 步 · 跑检测实验

> 以下命令**全部从仓库根目录执行**。算法部分**不需要 Vivado、不需要板子**，
> 只要 Python + numpy + opencv 就能跑。

### 3.1 先跑一条，快

```bash
python src/ps/algo_lab.py --data-root "<你的路径>" --set r11 --seq baseline/pedestrians
```

### 3.2 再跑全量 12 条（慢，约 25 分钟）

```bash
python src/ps/algo_lab.py --data-root "<你的路径>" --set r11 --seq all
```

### 3.3 ★ 两种 F1 口径 —— 别混

`algo_lab.py` 出的是**逐帧平均 F1**，`cdnet_official.py` 出的是**官方口径 F1**。
两者能差 **0.3 以上**，因为逐帧口径会被"几乎没有目标的空帧"严重拉低。

**对外报数一律用官方口径：**

```bash
python src/ps/cdnet_official.py --data-root "<你的路径>" --set r12 --seq all
```

★ 这条会**把结果写进 `src/ps/cdnet_official_results_r12.csv`**。

### 3.4 ★ 改动前后结果一致性怎么比

```bash
# 改动后重跑，与仓库里已归档的 CSV 对照
python src/ps/cdnet_official.py --data-root "<你的路径>" --set r12 --seq all
```

仓库里已归档的冠军结果：**官方口径 0.737**（`src/ps/cdnet_official_results.csv`）。

---

## 第 4 步 · 多目标跟踪 + 越界告警

> ★ **这条命令不需要 CDnet 数据集**，用的是仓库自带的合成考场 `data/golden/track_cross.avi`。

### 4.1 两种模式分别验证什么

| 模式 | 验证的是 | 参考结果文件 |
|---|---|---|
| `--source clean` | **跟踪逻辑本身**。输入是"干净的理想掩码"，排除检测噪声的干扰 —— 断航、串号这些纯粹是跟踪器的毛病，用它来判定 | 见下方 ⚠️ |
| `--source algo` | **整条链在真实噪声下的表现**。输入换成我们自己的检测链，会带上漏检/误检 —— 这才是上板后真正会遇到的情况 | `multi_track_results_algo.csv` |

**两个都要跑**：clean 通过说明"跟踪器没毛病"，algo 通过说明"整套能用"。只看 clean 会自我欺骗。

> ⚠️ **关于 `multi_track_results.csv` 的实话**：
> 仓库里 `multi_track_results.csv` 和 `multi_track_results_algo.csv`
> **当前内容完全相同**（已逐字节归一化核对过）—— 它们都是
> `--source algo --alarm --line-x 640 --init-frames 12` 跑出来的。
> 原因是早期这两份产物是同一次运行复制出来的，**clean 版没有单独重跑过**。
>
> 要拿**真正的 clean 结果**，自己跑一次（务必带 `--outdir`）：
> ```bash
> python src/ps/multi_track.py --source clean --alarm --line-x 640 --outdir out_clean
> ```
> 跑完后 `out_clean/multi_track_results.csv` 才是 clean 的那份。
>
> 我们没有直接改仓库里那个文件 —— 宁可让它名不副实，也不篡改已归档的参考结果。

### 4.2 ★ 复现参考成绩的完整命令（**参数不是默认值，务必照抄**）

```bash
python src/ps/multi_track.py --source algo --alarm --line-x 640 --init-frames 12 --outdir out_algo
```

★ **`--init-frames 12` 是必须的**。仓库里的参考成绩就是用它跑出来的：
`--init-frames` 默认是 **1**（不做处理），而 **12** 才是"起始背景取前 12 帧逐像素最小值"。
不写这个参数，**你会得到不一样的数字，以为自己跑错了**。

> `--init-frames` 的作用：第 0 帧里往往**就含着目标**，直接拿它当背景会把目标"固化"进去，
> 结果是目标内部永远不算前景，只在前后各留一条边带。
> 取前 N 帧逐像素最小值，就能把烤进背景的那一层去掉。

**clean 模式的参考命令：**

```bash
python src/ps/multi_track.py --source clean --alarm --line-x 640 --outdir out_clean
```

### 4.3 ★ 一定要用 `--outdir`（否则会覆盖仓库里的参考结果）

不加 `--outdir` 时，产物直接写到 `src/ps/` 下，**把已归档的参考 CSV 覆盖掉**。
上面两条命令用了 `--outdir out_algo` / `out_clean`，产物落到你指定的目录，互不干扰。

产物文件名按模式自动带后缀：

| 模式 | 产物 |
|---|---|
| clean | `alarm_events.csv`、`multi_track_results.csv` |
| algo | `alarm_events_algo.csv`、`multi_track_results_algo.csv` |

### 4.4 看结果

- 打开 `--outdir` 目录里的 `track_result*.mp4` —— 应看到两个框在动，某个时刻**变红**
- 打开 `alarm_events*.csv` —— 修复版应有 **3 条数据行（不含表头）**：第 34 帧离开、第 43 和 102 帧闯入
- **★ 视频变红的次数应该和 CSV 的行数对得上**。这就是"告警"与"检测"的区别：
  检测记录每帧位置；告警记录跨线或停留达到阈值的时刻。

停留按真实帧率计时，缺一帧观测、跳过帧号或离开区域都会重置连续计时；未设区域表示全画面。跨线速度须与方向一致，状态始终跟随观测位置，线上点归右侧。视频分别显示 INTRUSION、EXIT、DWELL。

`src/ps/track_result.mp4` 与 `track_result_algo.mp4` 是字节相同的旧归档，不能用来证明两种模式分别运行。保留它们用于历史追溯；修复版的独立视频、逐目标关联表与运行命令见 [修复报告](../report/repair_20261010/README.md)。

---

## 第 5 步 · 硬件相关（★ 这部分需要 Vivado）

> **Python 算法部分（第 1~4 步）完全不需要 Vivado，也不需要板子。**
> 只有下面这些才需要：

| 想做什么 | 需要什么 | 命令 |
|---|---|---|
| RTL 仿真、看波形 | **Vivado / xsim** | `python build/scripts/run_sim.py --expect-frames 12` |
| 逐位对照硬件模型 | 同上 | `python src/ps/rtl_golden.py --compare "本次运行目录/sim/wave/bbox_rtl.csv" --report "本次运行目录/model_vs_rtl.txt"` |
| 出对比图 / 演示视频 | 同上 | `python sim/view_sim.py` |
| 从零构建到 bitstream | **Vivado**（官方推荐 2026.1） | `build/scripts/build_vivado.bat 0` |
| 上板实测 | Vivado + 板子 + 电源 + 显示器 | —— |

### 5.1 先告诉脚本 Vivado 装在哪（★ 不配就跑不了）

`sim/run_sim.bat` 里**没有任何硬编码路径**（以前写死过
`<你的 Vivado 安装目录>\Vivado\settings64.bat`（按下面的方式告诉脚本它在哪，换台机器也能跑）。
按这个优先级找：

| 优先级 | 变量 | 填什么 |
|---|---|---|
| 1 | `VIVADO_SETTINGS` | `settings64.bat` 的**完整路径** |
| 2 | `XILINX_VIVADO` | Vivado **安装目录**（`settings64.bat` 在它下面） |
| 3 | 两个都没设 | 假设你当前这个 shell 已经有 Vivado 环境 |

**cmd（命令提示符）**

```bat
set VIVADO_SETTINGS=<你的 Vivado 安装目录>\Vivado\settings64.bat
```

**PowerShell**

```powershell
$env:VIVADO_SETTINGS = '<你的 Vivado 安装目录>\Vivado\settings64.bat'
```

> ⚠️ 又是那个坑：PowerShell 里写 `set VIVADO_SETTINGS=...` **不会生效**，
> 必须用 `$env:VIVADO_SETTINGS = '...'`。

想永久生效：cmd 用 `setx VIVADO_SETTINGS "..."`，PowerShell 用
`[Environment]::SetEnvironmentVariable('VIVADO_SETTINGS','...','User')`。

也可以不改环境变量，直接当参数给：

```bash
python build/scripts/run_sim.py --vivado-settings "<你的 Vivado 安装目录>\Vivado\settings64.bat"
```

> ★ 跑之前它会**逐个检查** `settings64.bat`、`xvlog`、`xelab`、`xsim` 在不在，
> 缺一个就立刻报错并**把上面这段配置方法原样打出来**，不会假装跑过了。
> 退出码：`10` settings64.bat 找不到 ｜ `11` 加载失败 ｜ `12` 工具不在 PATH。
>
> ★ xsim.bat 就算引擎没起来也返回 0，所以 `run_sim.py` **按日志内容**判成败
> （要有"仿真结束"标记、且没有 ERROR）。别只看退出码。

★ 上面这些命令请**从仓库根目录执行**。
软件产物在指定的 `--outdir`；RTL 产物在运行器打印的独立目录内 `sim/wave/`，综合报告在 `build/reports/`。

修复版默认仿真等待 12 次 bbox 结算，CSV 必须完整覆盖 0–11。比较器会拒绝缺帧、重复帧、空表和额外帧。仓库旧 `sim/wave/bbox_rtl.csv` 只有 0–10，严格比较应失败；请比较新运行目录，不要覆盖旧归档。

---

## 第 6 步 · 提交前自查（★ 30 秒，别跳过）

改完文档就跑这个 —— 它会检查你写的命令在代码里**真的存在**：

**【仓库根目录】**

```bash
python build/scripts/check_doc_commands.py
```

| 输出 | 意思 |
|---|---|
| `✅ 文档里所有命令的参数都真实存在` | 过了 |
| `★ 发现 N 个问题` + 退出码非 0 | 有命令写了不存在的参数，**按它列出的真实参数改** |
| `★ 降级提示：N 个脚本的 --help 没跑起来` | 这几个脚本的参数是**源码推断**来的，不是实际 `--help`。设 `MOTION_PYTHON` 指向装了依赖的解释器即可消掉 |

**这个脚本存在的原因**：文档里的命令如果是从记忆里抄的，很容易抄错。

> 想确认这个校验器本身还灵不灵，跑它的自检（临时文件放系统临时目录，不进仓库）：
> `python build/scripts/check_doc_commands.py --self-test`
>
> **文档里要写"错误写法"当反面教材时**，在那一行的任意位置加
> `<!-- 反例：说明 -->`，整行就不会被检查了。别靠"检查器恰好不认识这个参数名"。

> ⚠️ **反面例子（已修）**：本文件早期版本里写过 `python multi_track.py --algo`，<!-- 反例：这里演示的是不存在的 --algo 参数 -->
> 而 `--algo` 这个参数**从来就不存在**，正确的是 `--source algo`。
> 队友跑不动、白花了时间，才有了这个校验脚本。
> ★ 所以下面这句话里出现的 `--algo` 是**反面教材**，不是可用写法。<!-- 反例：这行里的 --algo 是演示错写法，检查器会跳过 -->

---

## 常见问题

| 现象 | 原因 | 怎么办 |
|---|---|---|
| 退出码非 0 + `[数据未就绪]` | 没给数据根，或给了错的 | 照它打印的说明改；用 `--list` 验证 |
| 退出码非 0 + `[数据不完整]` | 序列**缺帧 / 有坏文件 / 真值尺寸不符** | 照报错里给的**帧号与文件路径**去补数据；**不要去调参数**，调参数只会让分数错得更隐蔽 |
| `可用序列 (0)` | 指到了太深/太浅的一级 | `--data-root` 应指向**含类别目录**的那一级 |
| 数据下完了想一次性确认没坏文件 | 默认预检是"快查"（只看存在性 + 文件头） | 加 `--strict-data-check`，会逐帧真解码（900 帧约 22 秒） |
| 跑完发现 `git status` 里结果 CSV 变了 | `algo_lab` / `cdnet_official` 会**直接覆盖** `src/ps/` 下的同名结果文件 | 跑之前先 `git status` 确认干净；要留旧结果就先复制一份。**别急着 add 这些改动**，先想清楚是不是你想留的新结果 |
| `ModuleNotFoundError` | 虚拟环境没激活 | 重做第 1 步的 `.venv\Scripts\activate` |
| 找不到某文件 | 没在仓库根目录执行 | 回到仓库根再跑 |
| `push` 被拒绝 | 推的是 `main`，或没有 Write 权限 | 推自己的分支；权限问题找仓库 owner |
| 网页打不开仓库、报证书错 | 网络问题（**本机 hosts 被加速器改过**） | 见文末附录 |

---

## 附录 A · 本机推送报证书错的绕法

本机 `hosts` 里被加速器写过屏蔽列表，把 github 指向了 `127.0.0.1`。
临时绕开（`-c` 是"这一次用一下"，不改你的配置）：

```bash
git -c url."https://140.82.112.3/".insteadOf="https://github.com/" \
    -c http.sslVerify=false push origin main
```

---

## 附录 B · 复现 12 段评测所需的数据清单

**只要从 CDnet 下载页取这 7 个类别下的这 12 段**即可（全集 53 段不用全下）。

| # | 序列 | 类别 | temporalROI | 计分帧数 |
|---|---|---|---|---|
| 1 | badWeather/snowFall | badWeather | 800~6500 | 5701 |
| 2 | baseline/highway | baseline | 470~1700 | 1231 |
| 3 | baseline/office | baseline | 570~2050 | 1481 |
| 4 | baseline/pedestrians | baseline | 300~1099 | 800 |
| 5 | cameraJitter/badminton | cameraJitter | 800~1150 | 351 |
| 6 | cameraJitter/traffic | cameraJitter | 900~1570 | 671 |
| 7 | dynamicBackground/canoe | dynamicBackground | 800~1189 | 390 |
| 8 | dynamicBackground/fountain02 | dynamicBackground | 500~1499 | 1000 |
| 9 | intermittentObjectMotion/streetLight | intermittentObjectMotion | 175~3200 | 3026 |
| 10 | nightVideos/busyBoulvard | nightVideos | 730~2760 | 2031 |
| 11 | shadow/busStation | shadow | 300~1250 | 951 |
| 12 | shadow/peopleInShade | shadow | 250~1199 | 950 |

合计 **18583 计分帧**。CDnet 的 `temporalROI.txt` 是**1 基**的帧号区间，
每条序列还会额外预热 100 帧（`nw`），预热帧不计分。

**配置**：

| 项 | 值 |
|---|---|
| 压缩域 | 2×2 求和，8bit → 10bit，640×360 |
| 变体集（冠军对照） | `--set r12` → V0 / V12 / V43 / V45 / V46 / V47 |
| 变体集（含半径对照） | `--set r11` → V0 / V12 / V40 / V42 / V43 / V44 |
| 现役冠军 | **V43**（官方口径 **0.737**） |
| 真值排除 | 50 / 85 / 170（阴影与难例不计入 F1） |
| 输出 | `src/ps/cdnet_official_results_r12.csv` |

---

## 改代码之前，先读两份东西

1. **`CONTRIBUTING.md`** —— 协作规矩。一句话版：**`main` 分支只有 @Zcyyc11 能推**，
   其他人建自己的分支、提 PR、review 过再合。
2. **`docs/interface_freeze_table.md`** —— 接口定义。接口是三个人共用的，改错了三个人一起翻车。
