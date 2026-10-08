# 发布说明

本仓库保存校园异常 2D 动作 roguelite 的立项研究文档与 Godot 战斗原型源码。引擎二进制与可执行试玩包不进入源码历史，通过 GitHub Releases 分发。

## 为什么仓库里没有引擎和 EXE

`output/windows/CampusPrototype.exe` 与 `tools/godot/Godot_v4.7.2-stable_win64.exe` 的 SHA-256 完全相同，两者都是同一个 Godot 编辑器二进制。把它提交进仓库会超出 GitHub 单文件 100 MB 上限，而且用两份副本保存同一个文件没有意义。

试玩压缩包约 82.4 MiB，其中绝大部分同样是那个引擎二进制。它适合作为 Release 附件，而不适合放进源码历史。

## 获取引擎

原型锁定 Godot 4.7.2.stable。仓库中的构建与检查脚本读取 `tools/godot/` 下的可执行文件。

```powershell
# 在仓库根目录执行：下载并解压官方 Windows 便携版
$dir = "tools\godot"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$url = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip"
Invoke-WebRequest -Uri $url -OutFile "$dir\godot.zip" -UseBasicParsing
Expand-Archive -Path "$dir\godot.zip" -DestinationPath $dir -Force
Remove-Item "$dir\godot.zip"
```

解压后应得到 `Godot_v4.7.2-stable_win64.exe` 与 `Godot_v4.7.2-stable_win64_console.exe` 两个文件。

## 运行与检查

```powershell
# 试玩
.\tools\godot\Godot_v4.7.2-stable_win64.exe --path game

# 自动检查
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --self-test
```

也可以直接运行仓库根目录的 `试玩校园异常.cmd` 与 `检查战斗原型.cmd`。

## 获取试玩包

打开本仓库的 Releases 页面，下载最新的 `校园异常_Windows试玩_v0.1.zip`。包内包含引擎、资源包、试玩说明与 Godot 许可文件。文件大小与 SHA-256 记录在 `output/prototype/build-manifest.json`。

## 许可

引擎为 Godot，使用 MIT 许可，商用可行，无引擎版税。随试玩包分发的许可全文与第三方版权清单位于 `output/windows/`，该目录不进入版本控制，构建时由 `tools/godot/dump_notices.gd` 重新生成。
