# Windows 11 原生透明任务栏

本分支保存当前确认的配置：保留 Windows 默认任务栏布局、图标尺寸、按钮形状和圆角，加入透明背景以及液态玻璃风格的悬停、选中效果。

- 任务栏底色：浅灰 `#D9D9D9`，着色不透明度约 25%，背景模糊 20。
- 悬停及选中背景：模糊 5、低透明度白色着色、渐变高光边缘。鼠标移开后，当前应用仍保留玻璃材质。
- 保留 Windows 的底部活动指示线、应用合并和溢出行为。
- 使用系统默认几何形状，没有圆形按钮、浮动 Dock 布局或自定义模组 DLL。

## 使用

先安装 [Windhawk](https://windhawk.net/) 和 [Windows 11 Taskbar Styler](https://windhawk.net/mods/windows-11-taskbar-styler)。本配置在 Taskbar Styler 1.10 上校验。

双击以下文件，按 Windows 提示授予管理员权限：

| 文件 | 用途 |
| --- | --- |
| `outputs/Apply-Win11-Default-Transparent.cmd` | 应用当前透明任务栏配置。 |
| `outputs/Restore-Previous-Taskbar.cmd` | 恢复最近一次应用或重置前的设置和模组启用状态。 |
| `outputs/Reset-Windows-Taskbar.cmd` | 停用任务栏样式及尺寸模组，恢复原生 Windows 任务栏。 |

应用时会停用已安装的 `taskbar-icon-size`，以恢复默认尺寸；该模组不是必需依赖。应用及重置前会先保存本机备份，失败时尝试回滚。

备份位于 `outputs/Windows-Taskbar-Backups/`，结果记录在 `outputs/Windows-Default-Transparent-result.txt`；这些本机文件不会提交到 Git。

## 配置与校验

实际配置保存在 `outputs/Win11-Default-Transparent.json`，只包含背景材质及悬停、选中时的画刷属性。控制脚本不替换 Windhawk 模组 DLL，也不结束 Explorer 进程。

背景的 `#40D9D9D9` 使用 ARGB：`40` 是约 25% 的透明度通道，`D9D9D9` 是浅灰色；同时修改背景画刷的 `TintColor` 和 `FallbackColor` 可调整色彩。着色透明度描述的是底色，模糊及背后的画面也会影响实际观感。

只读校验，无需管理员权限：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\outputs\Windows-Default-Transparent.ps1 -ValidateOnly -NoPause
```

在已应用本配置的电脑上，可额外比对当前注册表配置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\outputs\Windows-Default-Transparent.ps1 -ValidateOnly -CompareCurrent -NoPause
```

玻璃效果基于 Windhawk 模糊画刷和渐变描边，不包含实时折射或持续流光动画。仓库原有的 `Glass-Dock-All` 文件属于旧 Dock 方案，本分支使用上面的新入口。
