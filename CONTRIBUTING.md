# 协作规范

> **看这一条就够了：**
> # main 分支只有 @Zcyyc11 能推。其他人改代码，先建自己的分支，改完提 PR，review 过再合。

---

## 为什么有这条规矩

三个人同时改代码，最怕的不是活多，是**两个人改同一个文件、互相覆盖**。

我们队最常见的翻车方式就是「顶层文件被两个人轮流覆盖」——所以宁可麻烦一点，也不要事后回滚。

> ⚠️ 说明：本仓库已于 2026-11-05 转为 public。公开仓库可以开启分支保护，但目前尚未启用，
> 所以这条规矩**仍靠大家的自觉**，不是 GitHub 强制拦你。请当真。

---

## 具体怎么做

### 第一步：别在 main 上改，先建自己的分支

```bash
git checkout main
git pull
git checkout -b feat/你的活
```

分支命名用这三种前缀：

| 前缀 | 什么时候用 | 例子 |
|---|---|---|
| `feat/` | 加新功能 | `feat/hdmi-input` |
| `fix/` | 修 bug | `fix/bbox-offset` |
| `docs/` | 只改文档 | `docs/contributing` |

### 第二步：改完提交，推自己的分支

```bash
git add <你改的文件>
git commit -m "一句话说清改了什么"
git push origin feat/你的活
```

**提交信息要写清"改了什么"，不要写"更新""修改"这种废话。**

### 第三步：在 GitHub 上提 Pull Request

推完之后打开仓库，会看到 `Compare & pull request` 按钮。

PR 描述里写三件事：
1. 改了什么
2. 怎么验证的（跑了什么命令，结果是什么）
3. 有没有动接口

### 第四步：等别人 review

**★ 换手验：写代码的人不许给自己签字。**

你提的 PR，必须由另外一个人看过才能合。他至少要：
- 跑一遍你的测试
- 确认结果和你声称的一致

### 第五步：合进 main

Review 通过后合并。合完把自己的分支删掉。

---

## 三道硬门（过不了不能合）

| # | 门 | 怎么过 |
|---|---|---|
| 1 | 仿真跑通 | `python build\scripts\run_sim.py`，波形与你声称的一致 |
| 2 | 资源与最高频率没倒退 | 看 `build/reports/`，跟上一版比 |
| 3 | 改了接口的，接口表同步改 | `docs/interface_freeze_table.md` 必须一起改 |

---

## 谁碰哪些文件

**按模块分，各自只碰自己那几个文件。** 详细的线怎么分看 `docs/getting_started.md`。

| 线 | 主要文件 |
|---|---|
| 视频通路与上板 | `src/rtl/video_timing.v`、`src/rtl/overlay.v`、`src/rtl/board/`、`data/golden/` |
| 算法与 PL 落地 | `src/rtl/diff_stage.v`、`threshold.v`、`morph3x3.v`、`morph_open.v`、`downsample2x2.v`、`src/ps/algo_lab.py` |
| 验证与证据 | `sim/`、`report/`、`docs/` |

## ★ 顶层文件的规矩

`src/rtl/md_pipeline.v` 是整机顶层，把每一级串起来。

**它只有一个 owner（@Zcyyc11）。** 其他人可以提建议、可以在 PR 里说"这里我觉得应该改"，但**不要自己直接改**。

理由：顶层一乱，三个人一起停摆。

---

## 禁止事项

| ❌ 禁止 | 为什么 |
|---|---|
| 直接往 main 推 | 会覆盖别人的活，这是第一条规矩 |
| 提交 Vivado 工程目录 | 几百 MB，GitHub 单文件上限 100 MB。只提交源码 + 约束 + Tcl 脚本 |
| 在微信里口头改位宽 | **聊天记录不是接口文档**。要改就提 PR 改 `docs/interface_freeze_table.md` |
| 只跑 1~2 条视频就下结论 | 我们有过教训：某个改动 3 条快测最好，12 条全量直接崩到 0.554。**下结论必须跑全量** |
| 提交第三方参考代码 | 版权问题，`.gitignore` 里已设红线 |

---

## 卡住了怎么办

1. **先看报错最后一行**，那通常是真原因
2. `ModuleNotFoundError` → 虚拟环境没激活，看 `docs/getting_started.md`
3. 找不到文件 → 确认你在 `src/ps` 之类的正确目录下跑
4. 还是不行 → **把完整报错 + 你跑的命令贴群里**，别只说「跑不了」
