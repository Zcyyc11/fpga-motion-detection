# Skill 7 · Vivado 2026.1 generic 参数传参格式（fileset 属性）

## 适用范围

- **什么条件下能用**：Vivado 2026.1（新版 Vivado 建议先按本技能自查）；用 `set_property generic` 给 RTL 顶层传 `parameter/generic`（如模式选择开关、位宽、阈值）时。
- **解决什么问题**：generic 传参用**逗号**分隔时，Vivado **编译照样通过、bit 照样出来，但参数根本没绑上**——得到一个"看起来成功、实际是默认配置"的静默坏货。上板前必须核对绑定。

## 使用方法

在 Tcl 构建脚本中（或工程 fileset 属性），**必须用空格分隔**：

```tcl
# ✅ 正确：空格分隔（2026.1 实测）
set_property generic {MODE_BG=0 INPUT_SEL=1} [current_fileset]

# ✅ 备选：synth_design 直接传参（空格分隔）
synth_design -generic "MODE_BG=0 INPUT_SEL=1" -top board_top ...

# ❌ 错误：逗号分隔 —— 整个串被解析成一个 generic 名，参数全部丢失/错绑
set_property generic {MODE_BG=0,INPUT_SEL=1} [current_fileset]
```

**上板前必须做的一步核对**（综合日志里搜）：

```text
Parameter MODE_BG bound to: 0 - type: integer   ← 出现这个才是真绑定
Parameter INPUT_SEL bound to: 1 - type: integer
```

## 已验证的效果

- **测试环境**：Vivado 2026.1（`D:\AMDDesignTools\2026.1\Vivado`）；PYNQ-Z2（XC7Z020-1CLG400C）；`build/scripts/build_vivado.tcl`
- **结果**：对"自测/真实 HDMI 输入"两版固件做三种传参格式对比实测——
  - 逗号格式：`EFFECTIVE_GENERIC=MODE_BG=0,INPUT_SEL=1`（整串被当单个 generic 名）+ `MODE_BG bound to: EL=1`（垃圾值）→ **两版功能同为默认配置**（坏 bit 哈希 `2B620F4D69AB...`）
  - 空格格式：`MODE_BG bound to: 0`、`INPUT_SEL bound to: 1` 真绑定 → 自测版哈希 `5937D6602BF5...`、HDMI 版 `83613671915C...`（时序 WNS 均收敛）
- **证据文件**：`build/scripts/build_vivado.tcl` L121 注释；两版 bit 位于 `build/bitstream/`。

## 从哪些失败或观察中总结得出

1. **现象**：f7d7088 时代"两版 bit 构建成功"——日志显示 `EFFECTIVE_GENERIC=MODE_BG=0,INPUT_SEL=1`（逗号）+ `Parameter MODE_BG bound to: EL=1`。两版固件功能其实是同一个默认配置，拿它们上板测不出真东西。
2. **原因**：Vivado 2026.1 的 fileset generic 属性解析规则是**空格分隔**；逗号分隔把整串当作一个 generic 名，导致 MODE_BG 绑到垃圾值、INPUT_SEL 压根没绑。**Vivado 不报错**——综合通过、bit 照出，错误完全静默。
3. **结论**：① 传参一律空格分隔；② 上板/交付前必须 grep 综合日志的 `bound to` 行核对每个参数；③ 两个及以上参数尤其危险（单参数 `MODE_BG=0` 无逗号问题）。

## 失效条件

- **旧版本 Vivado**（如 2022.2）：本技能以 2026.1 实测为准，旧版本解析规则可能不同，需各自验证。
- **GUI 手动跑**：若工程 fileset 未设置 generic 属性、直接在 GUI 里 Run，则不会继承脚本的 generic——跑出来的可能是默认配置。GUI 构建后同样要核对 `bound to`。
- **`synth_design -generic` 与 fileset 属性是两条路**：一条改了不代表另一条生效，脚本里两处都要对齐。
- **已知未覆盖的边界**：仅验证了 `MODE_BG=0/1`、`INPUT_SEL=0/1` 两个整型参数；字符串/位宽带花括号等复杂 generic 未验证。
