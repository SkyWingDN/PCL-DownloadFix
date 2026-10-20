# Plain Craft Launcher (PCL) 2.99.0.0 下载功能修复版（第三方修改，非官方）

> **本项目是第三方基于 PCL 的独立二次创作，不是官方项目，与 PCL 作者（龙腾猫跃 / Meloong-Git）无关。**
> 本项目仅恢复 PCL 2.99.0.0 (413) 中被移除的下载相关入口逻辑，未改动其他功能。
>
> - PCL 作者：龙腾猫跃（LTCat）
> - PCL 官方仓库：<https://github.com/Meloong-Git/PCL>
> - PCL 官方下载：<https://meloong.com/pcl>
> - 赞助作者：<https://meloong.com/afd/a/LTCat>
>
> 喜欢 PCL 的话，请通过官方渠道支持作者。

---

## 问题现象

官方 PCL 2.99.0.0 (413) 中：

- 点击「下载」时会直接弹出／抛出：

  > 为遵守相关法律法规，PCL 暂时不再提供 MC 下载功能，非常抱歉 qwq……

  导致「下载 → 原版游戏」页面无法打开。
- 「下载 → 整合包 → 安装已有整合包」只弹出上述提示，无法选择整合包文件安装。
- 另一个官方旧版 PCL 2.13.1.1 (408) 的同功能均正常。

排查后发现，问题并不是网络或接口失效，而是 2.99.0.0 中这两处入口的**代码逻辑被替换成了直接抛出异常**；底层下载、整合包安装等实现其实都还在程序里。本项目将这两处逻辑恢复为原本的功能实现。

## 修复内容

1. **原版游戏下载**
   `PCL.PageDownloadInstall.LoaderInit()` 中，原本应传入 Minecraft 版本列表加载器
   `ModDownload.DlClientListLoader`，2.99.0.0 中被替换成了一个名为「关闭下载」、回调必定抛异常的临时 `LoaderTask`。
   已恢复为正确的加载器，下载页可以正常加载 Minecraft 版本列表。

2. **整合包安装**
   - `PCL.ModModpack.ModpackInstall(string File, string InstanceName, string Logo)`：
     原先按 CurseForge / HMCL / MMC / MCBBS / Modrinth / 带启动器的压缩包 / 普通压缩包 等格式分发安装的逻辑被替换成抛异常，已恢复。
   - `PCL.ModModpack.ModpackInstall()`（「安装已有整合包」按钮）：
     被替换成只弹提示，已恢复文件选择框（筛选 `*.rar;*.zip;*.mrpack`）与后台安装逻辑。

3. 其余部分（版本号 2.99.0.0 (413)、图标、界面、下载实现、正版购买劝导逻辑、主色调等）保持原样。

详细技术说明与补丁位置见 [docs/修复原理.md](docs/修复原理.md)。

## 下载与使用

1. 在本仓库的 **Releases** 中下载 `PCL2-DownloadFix-2.99.0.0.zip`。
2. 解压到任意文件夹，双击 `Plain Craft Launcher 2.exe` 即可。
3. 压缩包内不包含任何账号、日志或个人设置；首次运行会自行生成 PCL 配置，并让你选择或新建 Minecraft 文件夹。

> 注意：修改后的程序没有官方数字签名，个别杀毒软件／SmartScreen 可能误报，请自行判断是否信任；也可以按下方方法用官方原版自行生成。

## 自行修补（推荐给注重安全的用户）

不直接下载别人给的 exe，也可以拿**官方原版 2.99.0.0 (413)** 自己生成修复版：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\patcher\apply_patch.ps1 -InputExe "官方原版PCL.exe" -OutputExe "PCL修复版.exe"
```

或者把官方原版 exe 直接拖到 `patcher\apply_patch.bat` 上，脚本会自动：

1. 校验输入文件是否为官方原版 2.99.0.0（SHA256 必须匹配）；
2. 应用补丁 1（恢复原版游戏下载加载器）；
3. 使用 Mono.Cecil 重写两个整合包安装方法；
4. 输出修复后的 exe。

本仓库提供的 Release 就是该脚本对官方原版运行后的产物，SHA256 完全一致，可自行校验。

## 校验值

| 文件 | SHA256 |
|---|---|
| 官方原版 PCL 2.99.0.0 (413) | `6B6E1260CB5A1D6A303855F1C60CAB3D0BC1AEBBA7E40A964180188B271E7386` |
| 修复版 `Plain Craft Launcher 2.exe` | `BF4D2889E9D54A415432E1B32EB891A73A3F3024308B6D7D21C896D14B8D3FD8` |
| Release 压缩包 | 见 [SHA256SUMS.txt](SHA256SUMS.txt) |

## 许可与声明

- PCL 的版权归原作者（龙腾猫跃 / 成都瓜皮龙科技有限公司）所有，本项目**不主张任何权利**。
- 本项目为第三方修改（“重度使用”），按《PCL 存储库合理使用指南》的要求：
  - 明确标注为第三方独立二次创作，非官方；
  - 保留原作者署名与赞助链接；
  - 公开修改内容与可复现的修补脚本（官方完整源码见官方仓库）；
  - 未修改正版购买劝导逻辑，界面主色仍为蓝色；
  - 不包含任何赞助解锁类功能。
- 相关文件：<https://github.com/Meloong-Git/PCL/blob/main/LICENCE>
  （《PCL 分发有限许可》）与《PCL 存储库合理使用指南》。
- 本项目仅供学习交流与个人使用，请勿用于商业用途。
- **如果原作者认为本项目不妥，请在本仓库提 Issue，我会立即删除。**

## 致谢

- [龙腾猫跃 / Meloong-Git](https://github.com/Meloong-Git) —— PCL（Plain Craft Launcher）作者
- [Mono.Cecil](https://github.com/jbevain/cecil)（MIT License）—— 补丁脚本使用的 .NET 程序集处理库
