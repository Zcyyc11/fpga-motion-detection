# data/captures/ — 采集素材

真实拍摄 / 外部数据集的测试素材。**大体积视频与图片不入库**，本文件只登记
"素材在哪、怎么来的、怎么再取一次"。

## 现在用哪一份

**CDnet 2014**（运动目标检测标准评测数据集）—— 放在**仓库之外**：

```
D:\FPGA\datasets\cdnet2014\
```

| 类别 | 序列 | 分辨率 | temporalROI | 选它的理由 |
|---|---|---|---|---|
| `baseline` | `pedestrians` | 360 × 240 | 300 ~ 1099 | 最普通的真实场景，暴露帧差法的**漏检（空洞）** |
| `dynamicBackground` | `canoe` | 320 × 240 | 800 ~ 1189 | **水波荡漾**的背景，帧差法**误检爆炸** |

- 完整说明（校验值 / 目录结构 / 真值标签含义 / 全部 53 段清单 / 引用要求）：
  **`D:\FPGA\datasets\cdnet2014\README.md`**
- 在该目录里可直接观看：`<序列>_input.mp4`（原始画面）、
  `<序列>_truth_overlay.mp4`（真值涂红）

## 怎么在它上面跑我们的算法

```bash
python src/ps/cdnet_demo.py --seq D:\FPGA\datasets\cdnet2014\baseline\pedestrians
python src/ps/cdnet_demo.py --seq D:\FPGA\datasets\cdnet2014\dynamicBackground\canoe
```

输出：终端一张对照表（精确率 / 召回率 / F1 / 误检 / 漏检），
外加 `cdnet_demo_fig.png`（三方对比图）与 `cdnet_demo_metrics.csv`（逐帧数字）。

## 为什么放在仓库外面

1. **体积**：两段原始帧加起来约 2000 张图，后续还会加，不适合进 git。
2. **不是我们的版权物**：第三方数据集，遵守与 `FPGA参考作品` 同一条红线
   —— **不进参赛仓库**。
3. **可复现靠"说明"不靠"文件"**：来源、URL 规律、SHA256 都写在上面的 README 里，
   别人照着能一模一样地取回同一份数据。

## 以后要加素材时的规矩

- 任何外部素材都放**仓外**（建议统一在 `D:\FPGA\datasets\` 下按数据集名建目录）;
- 在本目录登记：**从哪来 / 原始 URL 或命令 / 体积 / SHA256 / 用途 / 引用要求**；
- 若是自己拍摄的：记清**场地、设备、分辨率、帧率、拍摄日期**，原始文件不要裁剪；
- **不登记 = 等于没有**。别人复现不了的数据，在评分里不加分反而减分。
