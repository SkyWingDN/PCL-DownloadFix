<#
    PCL 下载功能修复补丁（版本分发入口）
    ------------------------------------------------
    自动识别官方原版版本并调用对应的修复脚本：
      - 2.99.0.0 (413)
      - 2.99.0.1 (415)

    用法：
        powershell -NoProfile -ExecutionPolicy Bypass -File apply_patch.ps1 -InputExe "官方 PCL.exe" -OutputExe "修复后.exe"

    或直接双击 apply_patch.bat（把官方 exe 拖到 bat 上）。
#>
param(
    [Parameter(Mandatory = $false)][string]$InputExe = "",
    [Parameter(Mandatory = $false)][string]$OutputExe = ""
)

$ErrorActionPreference = 'Stop'

function Fail([string]$msg) {
    Write-Host ""
    Write-Host ("[失败] " + $msg) -ForegroundColor Red
    exit 1
}

$Supported = @{
    '6B6E1260CB5A1D6A303855F1C60CAB3D0BC1AEBBA7E40A964180188B271E7386' = @('2.99.0.0 (413)', '2.99.0.0.ps1')
    '0DB34E19D9EEB6D496D20FABE786EC16BBD36BA6B0CCDC8D29CB7E909C114397' = @('2.99.0.1 (415)', '2.99.0.1.ps1')
}

if (-not $InputExe) {
    $InputExe = Read-Host "请输入官方原版 PCL 的 exe 路径"
}
if (-not (Test-Path -LiteralPath $InputExe)) { Fail "找不到输入文件：$InputExe" }
if (-not $OutputExe) {
    $dir = Split-Path -Parent (Resolve-Path -LiteralPath $InputExe)
    $OutputExe = Join-Path $dir 'Plain Craft Launcher 2 (下载修复版).exe'
}

$hash = (Get-FileHash -LiteralPath $InputExe -Algorithm SHA256).Hash
Write-Host ("输入文件: " + (Resolve-Path -LiteralPath $InputExe))
Write-Host ("SHA256  : " + $hash)

if (-not $Supported.ContainsKey($hash)) {
    Fail ("不支持的版本。目前仅支持官方原版：`n  - 2.99.0.0 (413)`n  - 2.99.0.1 (415)")
}

$info = $Supported[$hash]
Write-Host ("检测到 PCL " + $info[0]) -ForegroundColor Cyan
$scriptPath = Join-Path (Join-Path $PSScriptRoot 'versions') $info[1]
& $scriptPath -InputExe $InputExe -OutputExe $OutputExe
if (-not (Test-Path -LiteralPath $OutputExe)) { Fail "修复失败，未生成输出文件。" }
Write-Host ("输出文件: " + (Resolve-Path -LiteralPath $OutputExe))
Write-Host ("SHA256  : " + (Get-FileHash -LiteralPath $OutputExe -Algorithm SHA256).Hash)
Write-Host "修复完成。" -ForegroundColor Cyan
