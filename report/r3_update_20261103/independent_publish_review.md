# 发布说明独立复核

2026-11-03，范围为本次 README、视频指南、版本与验证说明及清单；未重新审计全部 RTL 或实测硬件。

独立复核提出一项模块归属修正，现已修改：

- 实际输入链路为 `hdmi_in_ctrl`（坐标/帧首）→ `gray_conv`（灰度）→ `tier1_md_pipeline`。
- `combined_top` 直接实例化 `tier1_md_pipeline(INPUT_SEL=1)`；包内 `md_pipeline` 是 `INPUT_SEL=0` 的内部测试兼容封装，不属于外部 HDMI 路径。

其余已读内容的 r3 身份、bit 哈希、时序结果、视频工具用途与参数、帧率/截图限制和验收边界未发现其他必须修正项。
本复核不构成团队换手签字或实板验收。
