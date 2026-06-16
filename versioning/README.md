# 版本管理器

版本管理器是 Creative Pipeline V3 的独立发布工具，放在开发室中维护，不属于主图工作流 P1-P5。

它负责：

1. 读取 `VERSION.json`、Git 状态和 diff 摘要。
2. 调用 DeepSeek API 分析改动，建议 `patch`、`minor` 或 `major`。
3. 生成 `CHANGELOG.md` 草稿。
4. 在用户确认后更新版本文件和变更记录。
5. 创建本地版本档案快照、`RELEASE_NOTES.md` 和 `RELEASE_MANIFEST.json`。
6. 用脚本硬规则排除浏览器数据、真实产品素材、运行结果、密钥和缓存。

## 快速开始

先预览，不写入文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\versioning\scripts\version-manager.ps1" -DryRun -SkipAI -ReleaseIntent "说明这次更新的目标"
```

接入 DeepSeek 时，优先使用环境变量：

```powershell
$env:DEEPSEEK_API_KEY = "你的密钥"
```

也可以把密钥放在仓库外的本地配置：

```text
%LOCALAPPDATA%\CreativePipelineV3\versioning\config.json
```

配置格式参考 `config.example.json`。不要把真实密钥写进仓库。

确认发布到默认档案室：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\versioning\scripts\version-manager.ps1" -Approve -ReleaseIntent "说明这次更新的目标"
```

默认档案室：

```text
%USERPROFILE%\Desktop\创意资产流水线_版本档案
```

## 安全原则

- DeepSeek 只负责建议，不负责决定。
- 文件排除、安全检查和归档由本地脚本硬规则执行。
- `-DryRun` 不修改 `VERSION.json`、`CHANGELOG.md`，也不创建正式快照。
- 未传 `-Approve` 时，脚本会要求人工确认。
- Git commit、tag、push 不在最小版本中自动执行。
