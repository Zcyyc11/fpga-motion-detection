# src/rtl/ — 自研 RTL

**命名约定**：模块按功能命名，小写 + 下划线（如 `gray_conv.v`、`frame_diff.v`、`thresh_bin.v`）。
每个模块配套 testbench 放 `sim/tb/`，文件名与被测模块一致。

**待实现模块清单**（随实现更新）：

| 模块 | 功能 | 状态 |
|---|---|---|
| `hdmi_in_ctrl.v` | HDMI 输入侧 AXI4-Stream 接收与帧同步（`tuser` 帧起始） | ⬜ |
| `gray_conv.v` | RGB → YCbCr 取 Y 分量（灰度） | ⬜ |
| `frame_buffer.v` | 缓存方案封装（无缓存 / 2×2 压缩 / 4×4 压缩 三档可切换） | ⬜ |
| `frame_diff.v` | 帧间差分（当前帧 − 缓存帧） | ⬜ |
| `thresh_bin.v` | 阈值分割 → 二值图 | ⬜ |
| `morph_erode.v` / `morph_dilate.v` | 形态学腐蚀 / 膨胀（3×3） | ⬜ |
| `centroid.v` | 逐帧累加像素坐标 → 运动区域质心 | ⬜ |
| `bbox_overlay.v` | 标记框叠加回输出视频流 | ⬜ |
| `timing_ctrl.v` | 行/场同步与时序控制 | ⬜ |
