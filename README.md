# Creative Pipeline V3

一个面向 Codex 的文件驱动主图方案生成工作流。

它把零散产品资料整理为三套六图候选方案，经人工选择后生成六份适合 Image 2 一类图像模型的自然语言提示词，最后通过已登录的 Microsoft Edge 在六个 ChatGPT 标签页中并发提交。

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

复杂分析由 Codex 完成。脚本只负责文件清单、项目复制、浏览器启动、参考文件上传和并发提交。

## 系统要求

- Windows 10 或 Windows 11
- Codex Desktop
- Microsoft Edge
- Node.js 20 或更新版本与 npm，或者 Codex Desktop 自带的 Node/Playwright 运行环境
- 可以登录并使用 ChatGPT 图片生成的账号

## 安装

克隆或下载仓库后，在 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install.ps1"
```

安装程序会：

- 将 Skill 安装到 `$CODEX_HOME/skills/creative-pipeline-v3`
- 未设置 `CODEX_HOME` 时安装到 `~/.codex/skills/creative-pipeline-v3`
- 将 Playwright 运行依赖安装到 `%LOCALAPPDATA%\CreativePipelineV3\runtime`

检查环境：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\doctor.ps1"
```

安装后重新打开 Codex，使 Skill 出现在可用 Skill 列表中。

## 创建产品项目

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\new-project.ps1" `
  -Destination "D:\Projects\产品名称" `
  -ProjectName "产品名称"
```

也可以手工复制 `template/main-image-project` 并使用产品名称重命名。

## 放置输入资料

将资料放入产品项目的 `01_inputs`：

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

每个阶段结束后，按照 Codex 提示进行确认。

P3 和 P4 的结果可以通过项目中的 `人工审核区` 打开。修改工作方法则编辑 `可编辑工作流提示词`。

## 第一次浏览器登录

第一次进入 P5 时，工作流会启动一个独立的 Edge 配置：

```text
%LOCALAPPDATA%\CreativePipelineV3\EdgeProfile
```

用户需要手工登录一次 ChatGPT。之后登录状态会保留，后续项目可以复用。

不要提交或分享该 Edge Profile。它可能包含 Cookie、会话和账号信息。

## 项目结构

- `skill/creative-pipeline-v3`：Codex Skill
- `template/main-image-project`：标准项目母版
- `scripts/install.ps1`：安装 Skill 和依赖
- `scripts/new-project.ps1`：创建产品项目
- `scripts/doctor.ps1`：检查运行环境
- `scripts/uninstall.ps1`：卸载 Skill 和本地运行环境

## 当前限制

- 浏览器自动化依赖 ChatGPT 当前页面结构，网页改版后可能需要更新定位规则。
- 普通方式启动且未开放 CDP 的 Edge 无法事后接管。
- P5 的终点是启动六个图片生成任务，不负责下载、筛选或修图。
- 工作流目前以 Windows 和 Edge 为目标环境。

## 隐私

不要把产品机密资料、客户隐私数据、浏览器 Profile、Cookie、登录数据、会话文件或已经填写的真实产品项目提交到 Git。

## License

[MIT](LICENSE)
