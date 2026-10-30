# 韦博交付包（Tier1 / PR#3 板端验收）— 2026-10-28

线一（主城要）替韦博（孙伟博）整理的全部 Tier1 验收成果，整进此目录。
本包为本地交付版；GitHub 上传因本机 GitHub 凭据（gh keyring token）已失效 + 代理不通，**暂未推上去**，详见末尾“GitHub 上传状态”。

## 文件清单

| 文件 | 内容 | 状态 |
|------|------|------|
| 00_进度说明_给韦博的人话版.docx | 验收结论 / 方法 / 证据 / .xsa缺陷 / 待办 / 下一步（主交付，嵌真红框截图） | 新写 |
| 01_Tier1验收运行记录表.docx | 验收逐项记录；UART 栏已回填“弃用/改 AXI”，总体 5/5 | 已回填 |
| 02_韦博_Tier1_xsa缺陷反馈.docx | 必须修的 .xsa 缺陷（bit 不可复现/不可重下）复现与规避 | 已有 |
| 03_acceptance_record.json | 验收原始数据：bit SHA / 时钟 / MMIO 回读 / 采集统计 / 16条AXI采样 / verdict=PASS | 已有 |
| 04_真板子红框截图_vehicles_final_n7438.png | 真板子 J11 采集卡抓帧（高速路+车红框+警戒线+绿方块） | 已有 |

## 核心结论

- Tier1 bit（SHA256 前8位 e4f1e25c，PR#3 声明一致）在真板子（PYNQ-Z2 / XC7Z020-1CLG400C）**板端验收 PASS**。
- 三路互证：真板子跑通（时钟125/100、AXI回读一致）+ 检测红框出图（976帧100%红框）+ AXI遥测活（帧号/目标/包围盒实时、drop=0）。
- 串口已正式弃用，改“网线+AXI 直读”替代（仅限带 AXI 的 Tier1 bit）。
- 必须修：.xsa 缺陷（Overlay 下 bit 时同目录 .xsa 优先加载，导致 bit 下不进/下错版本）。

## 待办（未收口）

1. 互验签字：出 bit 者不自签，需徐一夫/线一跑 tb/板测签字（团队互验门）。
2. PR#3 出 DRAFT：Tier1 源码/bit/.xsa 进仓库开 PR。
3. 长稳多场景：连续运行/断电连测3次（约18分钟长测）原“待补”，本次未做满。
4. UART 已弃用改 AXI，不必再修。

## GitHub 上传状态（阻塞）

- 本机 `gh` keyring 内 GitHub token 已失效（“token in keyring is invalid”）。
- 全机扫描未发现任何有效 GitHub token（ghp_/github_pat_ 等）。
- 系统代理 127.0.0.1:7897 当前未正常监听，连不通 api.github.com。
- 本地 git 自 10-20 对象库残缺已废，唯一通路是 GitHub Git Data API 服务端建 commit，但该通路依赖有效 token + 代理。

**出路（二选一，线一即可执行）：**
- 你提供一枚 GitHub Classic PAT（repo 权限），或在本机跑 `gh auth login` / `gh auth refresh` 让 token 重新有效；
- 确认代理 127.0.0.1:7897 已启动。
- 满足任一可用凭据后，线一立即用 Git Data API 把本包推到仓库新分支 `line1/weibo-tier1-acceptance-20261028` 并开 PR 说明进度。
