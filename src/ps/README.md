# src/ps/ — PS 侧软件（PYNQ Python）

**定位**：`PL 负责实时像素流水线`，PS 侧只做三件事 —— 加载 overlay、驱动数据搬运、**生成黄金参考做对照**。

| 文件 | 作用 |
|---|---|
| `load_overlay.py` | 加载 `.bit` 并校验（含 `ignore_version=True` 处理） |
| `run_motion_detect.ipynb` | 上板主流程：启动流水线 → 取质心结果 → 输出叠加画面 |
| `golden_ref.py` | OpenCV 黄金参考实现（同一段视频跑同一算法的软件版），用于功能正确性比对 |

> ⚠️ 黄金参考**只用于验证**，不构成作品实现。作品的功能主体在 `src/rtl/`。
