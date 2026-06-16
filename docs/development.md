# 开发者指南

## 日常开发位置

只在源码仓库中修改功能：

```text
creative-pipeline-v3-github
```

不要直接修改版本档案里的快照，也不要把真实产品项目中的运行结果复制回模板。

## 修改哪一层

- 改流程规则：优先改 `template/main-image-project/可编辑工作流提示词`
- 改项目结构：改 `template/main-image-project`
- 改安装和环境检查：改 `scripts`
- 改 Codex 调度规则：改 `skill/creative-pipeline-v3/SKILL.md`
- 改版本管理：后续改 `versioning`
- 改说明：改 `README.md` 或 `docs`

## 版本号建议

- 小修复：patch，例如 `3.1.0 -> 3.1.1`
- 新增兼容功能：minor，例如 `3.1.0 -> 3.2.0`
- 不兼容旧项目：major，例如 `3.x -> 4.0.0`

## 提交前检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\validate-release.ps1"
```

还要确认没有提交：

- 浏览器 Profile
- Cookie
- Login Data
- 真实产品输入素材
- 真实客户数据
- 运行输出图片
