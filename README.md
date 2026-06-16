# Creative Pipeline V3

Creative Pipeline V3 是一个面向 Codex 的文件驱动工作流，用来把零散产品资料整理成主图方案，并通过已登录的 Edge/ChatGPT 页面并发提交六张主图提示词。

当前版本：`3.1.0`，定位为“项目架构标准化版”。

## 四个位置

这个项目按四个位置组织，避免源码、模板、真实项目和历史版本混在一起。

```text
开发室：本仓库
模板室：template/main-image-project
工作室：用户从模板复制出来的具体产品项目
档案室：本地版本档案目录，默认建议放在桌面
```

开发室只修改工具本身。模板室只放干净母版。工作室放真实素材和运行结果。档案室只保存发布快照，不用于继续开发。

## 工作流程

```text
P1 输入盘点
-> 人工确认
-> P2 综合分析
-> P3 三套六图方案
-> 人工选择或混合
-> P4 六份自然语言提示词
-> 人工审核
-> P5 六个 ChatGPT 页面并发提交
```

复杂分析由 Codex 完成。脚本只负责确定性的动作，例如安装、复制模板、检查环境、启动 Edge、分发提示词。

## 安装

要求：

- Windows 10 或 Windows 11
- Codex Desktop
- Microsoft Edge
- 可使用图片生成的 ChatGPT 账号
- Node.js 20+ 与 npm，或 Codex Desktop 自带的 Node/Playwright 运行环境

安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install.ps1"
```

检查环境：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\doctor.ps1"
```

安装后重新打开 Codex，让 Skill 出现在可用 Skill 列表中。

## 创建产品项目

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-project.ps1" `
  -Destination "D:\Projects\产品名称" `
  -ProjectName "产品名称"
```

也可以手工复制 `template/main-image-project` 并用产品名称重命名。

## 放置输入资料

把资料放进产品项目的 `01_inputs`：

```text
01_inputs/
├─ product_info/
├─ product_views/
│  ├─ three_view/       # 一张包含正面、侧面和背面的三视图
│  └─ details/
├─ competitor_main_images/
├─ reviews/
├─ market_and_audience/
├─ brand_assets/
└─ other_references/
```

## 在 Codex 中运行

1. 新建 Codex 对话。
2. 将产品项目文件夹设为项目目录。
3. 输入：

```text
使用 $creative-pipeline-v3 运行当前项目。先执行 P1，检查输入资料并停下来等我确认。
```

每个阶段结束后，按照 Codex 提示进行确认。P3 和 P4 的结果可以通过项目中的 `人工审核区` 打开和修改。

## 第一轮浏览器登录

第一次进入 P5 时，工作流会启动一个独立 Edge 配置：

```text
%LOCALAPPDATA%\CreativePipelineV3\EdgeProfile
```

用户需要手动登录一次 ChatGPT。之后登录状态会保留，后续项目可以复用。

不要提交或分享该 Edge Profile。它可能包含 Cookie、会话和账号信息。

## 项目结构

```text
skill/                     # Codex Skill
template/main-image-project # 标准项目母版
scripts/                   # 安装、诊断、复制模板和维护脚本
docs/                      # 架构和开发文档
versioning/                # 后续完整版本管理器的设计位置
examples/                  # 脱敏示例
tests/                     # 自动测试和弱 Codex 测试
```

## 版本管理

临时的本地小版本发布脚本已经在 `3.1.0` 中移除。后续版本管理会升级为独立模块，计划接入 DeepSeek API 自动分析更新内容、建议版本号、生成变更说明，并写入版本档案。

当前占位说明见：

```text
versioning/README.md
```

## 当前限制

- 浏览器自动化依赖 ChatGPT 当前页面结构，网页改版后可能需要更新定位规则。
- 普通方式启动且未开放 CDP 的 Edge 无法事后接管。
- P5 的终点是启动六个图片生成任务，不负责下载、筛选或修图。
- 工作流目前以 Windows 和 Edge 为目标环境。

## 隐私

不要把产品机密资料、客户隐私数据、浏览器 Profile、Cookie、登录数据、会话文件或真实产品项目提交到 Git。

## License

[MIT](LICENSE)
