# Plain Craft Launcher (PCL) 下载功能修复版（第三方修改，非官方）

> 目前支持官方 **2.99.0.0 (413)** 与 **2.99.0.1 (415)** 两个版本。
>
> - 本项目为非官方第三方修改，与 PCL 作者及官方无关；PCL 版权归原作者所有。
> - 作者：龙腾猫跃（LTCat）｜ 官方仓库：<https://github.com/Meloong-Git/PCL> ｜ 官方下载：<https://meloong.com/pcl> ｜ 赞助作者：<https://meloong.com/afd/a/LTCat>
> - 本修复由 **DeepSeek** 分析并生成补丁。

## 问题现象

- 官方 2.99.0.0 (413) 起关闭 MC 下载功能，点击下载会报：
  > 为遵守相关法律法规，PCL 不再提供 MC 下载功能，非常抱歉 qwq……
- 官方 2.99.0.1 (415) 更新日志写着“删除：MC 下载功能相关入口”，实际上把入口整个删除/隐藏了：
  - 下载页左侧没有「原版游戏」；
  - 启动页在未安装游戏时不显示「下载游戏」按钮；
  - 版本选择页空列表时没有下载入口；
  - 「安装已有整合包」被隐藏；
  - 整合包安装逻辑被替换为直接抛异常。

这些功能在旧版本（如 2.13.1.1）里都是正常存在的。本项目只是把被删除/替换的实现恢复回来，不修改其它任何功能。

## 修复内容

| 版本 | 恢复内容 |
|---|---|
| 2.99.0.0 (413) | 下载页「原版游戏」版本列表；整合包安装分发（CurseForge / HMCL / MMC / MCBBS / Modrinth / 压缩包）与「安装已有整合包」 |
| 2.99.0.1 (415) | 上述全部；另外恢复：下载页「原版游戏」入口、启动页「下载游戏」按钮、版本选择页空列表「下载游戏」按钮、页面内「安装已有整合包」按钮 |

修复后版本号、图标、界面、正版购买劝导逻辑、主色调均保持官方原样。

## 下载与使用

在 **Releases** 中下载对应版本的压缩包（`PCL2-DownloadFix-2.99.0.0.zip` / `PCL2-DownloadFix-2.99.0.1.zip`），解压后双击 `Plain Craft Launcher 2.exe`。
压缩包不包含账号、日志、个人设置或本机路径；首次运行会自动生成 PCL 设置。

## 自行修补（推荐给注重安全的用户）

不直接使用别人给的 exe，也可以用官方原版自己生成（脚本自动识别版本，仅支持官方原版 413 / 415）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\patcher\apply_patch.ps1 -InputExe "官方原版PCL.exe" -OutputExe "PCL修复版.exe"
```

或把官方原版 exe 直接拖到 `patcher\apply_patch.bat` 上。脚本会先校验 SHA256，输出与本仓库 Release 中的 exe 完全一致。

## 校验值

| 文件 | SHA256 |
|---|---|
| 官方 2.99.0.0 (413) | `6B6E1260CB5A1D6A303855F1C60CAB3D0BC1AEBBA7E40A964180188B271E7386` |
| 官方 2.99.0.1 (415) | `0DB34E19D9EEB6D496D20FABE786EC16BBD36BA6B0CCDC8D29CB7E909C114397` |
| 修复版 exe（2.99.0.0） | `BF4D2889E9D54A415432E1B32EB891A73A3F3024308B6D7D21C896D14B8D3FD8` |
| 修复版 exe（2.99.0.1） | `2C02F3CD108198667C4E51B72BA961F56B45022F9F6D1BA6A41F4309392AFC91` |
| Release 压缩包 | 见 [SHA256SUMS.txt](SHA256SUMS.txt) |

## 许可与声明

- PCL 的版权归原作者（龙腾猫跃 / 成都瓜皮龙科技有限公司）所有，本项目**不主张任何权利**。
- 本项目属于第三方修改（“重度使用”），按《PCL 存储库合理使用指南》要求：明确标注非官方、保留作者署名与赞助链接、公开修改内容与可复现补丁、未修改正版购买劝导逻辑、主色仍为蓝色。
- 相关文件：<https://github.com/Meloong-Git/PCL/blob/main/LICENCE>
- 本项目仅供学习交流与个人使用，请勿用于商业用途。
- 如原作者认为本项目不妥，请在本仓库提 Issue，我会立即删除。

## 致谢

- [龙腾猫跃 / Meloong-Git](https://github.com/Meloong-Git) —— PCL（Plain Craft Launcher）作者
- [Mono.Cecil](https://github.com/jbevain/cecil)（MIT License）
