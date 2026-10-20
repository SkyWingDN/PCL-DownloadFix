<#
    PCL 2.99.0.0 (413) 下载功能修复补丁
    ------------------------------------------------
    将官方原版 PCL 2.99.0.0 (413) 单文件启动器修复为可正常使用
    “下载 → 原版游戏” 与 “整合包安装” 功能的版本。

    仅适用于官方原版 2.99.0.0 (413)（SHA256:
    6B6E1260CB5A1D6A303855F1C60CAB3D0BC1AEBBA7E40A964180188B271E7386）。

    用法：
        powershell -NoProfile -ExecutionPolicy Bypass -File apply_patch.ps1 -InputExe "官方 PCL.exe" -OutputExe "修复后.exe"

    或直接双击 apply_patch.bat（将官方 exe 拖到 bat 上）。
#>
param(
    [Parameter(Mandatory = $false)][string]$InputExe = "",
    [Parameter(Mandatory = $false)][string]$OutputExe = ""
)

$ErrorActionPreference = 'Stop'
$script:OriginalHash = '6B6E1260CB5A1D6A303855F1C60CAB3D0BC1AEBBA7E40A964180188B271E7386'

function Fail([string]$msg) {
    Write-Host ""
    Write-Host ("[失败] " + $msg) -ForegroundColor Red
    exit 1
}

if (-not $InputExe) {
    $InputExe = Read-Host "请输入官方原版 PCL 2.99.0.0 的 exe 路径"
}
if (-not (Test-Path -LiteralPath $InputExe)) { Fail "找不到输入文件：$InputExe" }
if (-not $OutputExe) {
    $dir = Split-Path -Parent (Resolve-Path -LiteralPath $InputExe)
    $OutputExe = Join-Path $dir 'Plain Craft Launcher 2 (下载修复版).exe'
}

$hash = (Get-FileHash -LiteralPath $InputExe -Algorithm SHA256).Hash
Write-Host ("输入文件: " + (Resolve-Path -LiteralPath $InputExe))
Write-Host ("SHA256  : " + $hash)
if ($hash -ne $script:OriginalHash) {
    Fail "输入文件不是受支持的官方原版 PCL 2.99.0.0 (413)。请使用官方渠道下载原版后再运行本补丁。"
}

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InputExe))

# ------------------------------------------------------------------
# 补丁 1/2：PageDownloadInstall.LoaderInit 的加载器被替换成了抛异常的假加载器
#   方法体 IL 起始文件偏移 0x2C0C0，第 0x1A 字节起为 48 字节的
#   “new LoaderTask("关闭下载", 抛异常委托)” 构造序列；
#   把它替换为 ldsfld ModDownload::DlClientListLoader（字段 token 0x0400040F）。
# ------------------------------------------------------------------
$expectedA = '72334701707efb0900042c077efb0900042b167ef9090004fe0667140006738d05000a2580fb0900041418738e05000a'
$offsetA = 0x2C0DA
$actualA = -join ($bytes[$offsetA..($offsetA + 47)] | ForEach-Object { $_.ToString('x2') })
if ($actualA -ne $expectedA) {
    Fail "找不到预期的补丁 1 位置（文件可能已被修改过，或版本不匹配）。"
}
$newA = [byte[]](0x7E, 0x0F, 0x04, 0x00, 0x04) + [byte[]]::new(43)
[Array]::Copy($newA, 0, $bytes, $offsetA, $newA.Length)
Write-Host "[1/2] 已恢复原版游戏下载加载器" -ForegroundColor Green

$patchedA = [System.IO.Path]::Combine($env:TEMP, 'pcl_downloadfix_patchA_' + [guid]::NewGuid().ToString('N') + '.exe')
[System.IO.File]::WriteAllBytes($patchedA, $bytes)

# ------------------------------------------------------------------
# 补丁 2/2：ModModpack 的整合包安装逻辑
#   使用 Mono.Cecil 重写两个方法体：
#     ModModpack.ModpackInstall(string,string,string) —— 恢复按格式分发安装
#     ModModpack.ModpackInstall()                      —— 恢复“安装已有整合包”文件选择
# ------------------------------------------------------------------
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'lib\Mono.Cecil.dll')

    $resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
    $rp = New-Object Mono.Cecil.ReaderParameters
    $rp.AssemblyResolver = $resolver
    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($patchedA, $rp)
    $mod = $asm.MainModule

    # 从原版程序的内嵌资源中提取依赖程序集（仅供 Mono.Cecil 解析引用，不复制、不修改）
    $resDir = [System.IO.Path]::Combine($env:TEMP, 'pcl_downloadfix_refs_' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($resDir) | Out-Null
    $resRes = $mod.Resources | Where-Object { $_.Name -eq 'PCL.Resources.resources' }
    if ($null -eq $resRes) { throw '找不到 PCL.Resources.resources 资源' }
    $resStream = $resRes.GetResourceStream()
    $resReader = New-Object System.Resources.ResourceReader -ArgumentList (, $resStream)
    $extracted = 0
    foreach ($entry in $resReader) {
        if ($entry.Value -is [byte[]]) {
            $b = [byte[]]$entry.Value
            if ($b.Length -gt 2 -and $b[0] -eq 0x4D -and $b[1] -eq 0x5A) {
                [System.IO.File]::WriteAllBytes([System.IO.Path]::Combine($resDir, ($entry.Key + '.dll')), $b)
                $extracted++
            }
        }
    }
    $resReader.Close()
    $resolver.AddSearchDirectory($resDir)
    Write-Host ("[*] 已从原版程序中提取 " + $extracted + " 个内嵌依赖程序集，用于构建补丁") -ForegroundColor DarkGray

    function Find-Ref([string]$name, [string]$declType, [int]$paramCount) {
        $found = @()
        foreach ($r in $mod.GetMemberReferences()) {
            if ($r.Name -ne $name) { continue }
            if ($r.DeclaringType.FullName -ne $declType) { continue }
            if ($r.Parameters.Count -ne $paramCount) { continue }
            $found += $r
        }
        return $found
    }

    $mmType = $mod.Types | Where-Object { $_.FullName -eq 'PCL.ModModpack' }
    if ($null -eq $mmType) { throw '找不到 PCL.ModModpack 类型' }

    # ================= 2.1 恢复 ModpackInstall(string,string,string) =================
    $method = $mmType.Methods | Where-Object { $_.Name -eq 'ModpackInstall' -and $_.Parameters.Count -eq 3 }
    $body = $method.Body
    $il = $body.GetILProcessor()

    $blockedLdstr = $null
    foreach ($ins in $body.Instructions) {
        if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr -and [string]$ins.Operand -like '为遵守相关法律法规*') { $blockedLdstr = $ins; break }
    }
    if ($null -eq $blockedLdstr) { throw '找不到被替换的抛异常代码（补丁可能已应用）' }
    $newobjEx = $blockedLdstr.Next
    $throwIns = $newobjEx.Next
    $finallyStart = $throwIns.Next
    if ($throwIns.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Throw) { throw '方法结构不符合预期' }

    $resultVar = New-Object Mono.Cecil.Cil.VariableDefinition -ArgumentList (, $method.ReturnType)
    $body.Variables.Add($resultVar) | Out-Null

    $loggerInfo = (Find-Ref 'Info' 'MeloongCore.Logger' 3)[0]
    if ($null -eq $loggerInfo) { throw '找不到 Logger.Info 引用' }

    $srcPathStr = 'E:\Projects\PCL\本体代码\Plain Craft Launcher 2\Modules\Minecraft\ModModpack.vb'
    $installMethods = @{}
    foreach ($m in $mmType.Methods) { if ($m.Name -like 'InstallPack*') { $installMethods[$m.Name] = $m } }

    $retBlock = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$resultVar)
    $retIns = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ret)

    function New-CaseIns([string]$logText, [Mono.Cecil.MethodDefinition]$target, [bool]$useInstanceName, [bool]$useLogo, [bool]$useBase) {
        $list = New-Object System.Collections.ArrayList
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, $logText)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, $srcPathStr)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$loggerInfo)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$body.Variables[1])) | Out-Null
        if ($useBase) { $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$body.Variables[2])) | Out-Null }
        if ($useInstanceName) { $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1)) | Out-Null }
        if ($useLogo) { $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldarg_2)) | Out-Null }
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$target)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stloc, [Mono.Cecil.Cil.VariableDefinition]$resultVar)) | Out-Null
        $list.Add([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Leave, [Mono.Cecil.Cil.Instruction]$retBlock)) | Out-Null
        return $list
    }

    $case0 = New-CaseIns '整合包种类：CurseForge' $installMethods['InstallPackCurseForge'] $true $true $true
    $case1 = New-CaseIns '整合包种类：HMCL' $installMethods['InstallPackHMCL'] $false $false $true
    $case2 = New-CaseIns '整合包种类：MMC' $installMethods['InstallPackMMC'] $false $false $true
    $case3 = New-CaseIns '整合包种类：MCBBS' $installMethods['InstallPackMCBBS'] $true $false $true
    $case4 = New-CaseIns '整合包种类：Modrinth' $installMethods['InstallPackModrinth'] $true $true $true
    $case9 = New-CaseIns '整合包种类：带启动器的压缩包' $installMethods['InstallPackLauncherPack'] $false $false $true
    $caseD = New-CaseIns '整合包种类：未能识别，假定为压缩包' $installMethods['InstallPackCompress'] $false $false $false

    $targets = [Mono.Cecil.Cil.Instruction[]]::new(10)
    $targets[0] = $case0[0]; $targets[1] = $case1[0]; $targets[2] = $case2[0]; $targets[3] = $case3[0]; $targets[4] = $case4[0]
    $targets[5] = $caseD[0]; $targets[6] = $caseD[0]; $targets[7] = $caseD[0]; $targets[8] = $caseD[0]; $targets[9] = $case9[0]
    $switchIns = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Switch, $targets)

    $v4 = $body.Variables[4]
    $ldlocNum = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$v4)
    $ldc0 = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
    $switchLdloc = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$v4)
    $bgeIns = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Bge_S, [Mono.Cecil.Cil.Instruction]$switchLdloc)
    $brDefault = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Br, [Mono.Cecil.Cil.Instruction]$caseD[0])

    foreach ($ins in $body.Instructions) {
        if ($ins.Operand -is [Mono.Cecil.Cil.Instruction] -and $ins.Operand -eq $blockedLdstr) { $ins.Operand = $ldlocNum }
    }
    foreach ($eh in $body.ExceptionHandlers) {
        if ($eh.TryEnd -eq $blockedLdstr) { $eh.TryEnd = $ldlocNum }
        if ($eh.HandlerEnd -eq $blockedLdstr) { $eh.HandlerEnd = $ldlocNum }
    }

    $il.Remove($throwIns); $il.Remove($newobjEx); $il.Remove($blockedLdstr)

    $all = New-Object System.Collections.ArrayList
    foreach ($x in @($ldlocNum, $ldc0, $bgeIns, $brDefault, $switchLdloc, $switchIns)) { $all.Add($x) | Out-Null }
    foreach ($c in @($case0, $case1, $case2, $case3, $case4, $case9, $caseD)) { foreach ($i in $c) { $all.Add($i) | Out-Null } }
    foreach ($i in $all) { $il.InsertBefore($finallyStart, [Mono.Cecil.Cil.Instruction]$i) }

    $last = $body.Instructions[$body.Instructions.Count - 1]
    $il.InsertAfter($last, [Mono.Cecil.Cil.Instruction]$retBlock)
    $il.InsertAfter($retBlock, [Mono.Cecil.Cil.Instruction]$retIns)
    foreach ($eh in $body.ExceptionHandlers) {
        if ($eh.HandlerType -eq [Mono.Cecil.Cil.ExceptionHandlerType]::Finally -and $eh.HandlerStart -eq $finallyStart) { $eh.HandlerEnd = $retBlock }
    }

    # ================= 2.2 恢复 ModpackInstall() =================
    $methodC = $mmType.Methods | Where-Object { $_.Name -eq 'ModpackInstall' -and $_.Parameters.Count -eq 0 }
    $bodyC = $methodC.Body
    $ilC = $bodyC.GetILProcessor()
    $retC = $bodyC.Instructions[$bodyC.Instructions.Count - 1]
    if ($retC.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ret) { throw '无参 ModpackInstall 结构不符合预期' }
    $old = @($bodyC.Instructions)
    foreach ($ins in $old) { if ($ins -ne $retC) { $ilC.Remove($ins) } }

    $strVar = New-Object Mono.Cecil.Cil.VariableDefinition -ArgumentList (, $mod.TypeSystem.String)
    $bodyC.Variables.Add($strVar) | Out-Null

    $closureType = $mmType.NestedTypes | Where-Object { $_.Name -eq '_Closure$__0-0' }
    $closureCtor = $closureType.Methods | Where-Object { $_.Name -eq '.ctor' -and $_.Parameters.Count -eq 0 }
    $closureLambda = $closureType.Methods | Where-Object { $_.Name -eq '_Lambda$__0' -and $_.Parameters.Count -eq 0 }
    $closureField = $closureType.Fields | Where-Object { $_.Name -eq '$VB$Local_File' }

    $selectFile = (Find-Ref 'SelectFile' 'MeloongCore.Wpf.Dialogs' 4)[0]
    $actionCtor = $null
    foreach ($r in $mod.GetMemberReferences()) {
        if ($r.Name -eq '.ctor' -and $r.DeclaringType.FullName -eq 'System.Action' -and $r.Parameters.Count -eq 2) { $actionCtor = $r; break }
    }
    $firstOrDefault = $null
    foreach ($r in $mod.GetMemberReferences()) {
        if ($r.Name -eq 'FirstOrDefault' -and $r.DeclaringType.FullName -eq 'System.Linq.Enumerable' -and $r.Parameters.Count -eq 1) { $firstOrDefault = $r; break }
    }
    $gim = New-Object Mono.Cecil.GenericInstanceMethod -ArgumentList (, $firstOrDefault)
    $gim.GenericArguments.Add($mod.TypeSystem.String) | Out-Null

    $isNullEmpty = (Find-Ref 'IsNullOrEmpty' 'System.String' 1)[0]
    $modBase = $mod.Types | Where-Object { $_.FullName -eq 'PCL.ModBase' }
    $runInThread = $modBase.Methods | Where-Object { $_.Name -eq 'RunInThread' -and $_.Parameters.Count -eq 1 }

    $BT = [char]96
    $tupleName = 'System.ValueTuple' + $BT + '2<System.String[],System.String>'
    $tupleCtor = $null
    foreach ($r in $mod.GetMemberReferences()) {
        if ($r.Name -eq '.ctor' -and $r.DeclaringType.FullName -eq $tupleName) { $tupleCtor = $r; break }
    }
    if ($null -eq $tupleCtor) { throw '找不到 ValueTuple 构造引用' }
    $tupleType = $tupleCtor.DeclaringType

    $oneOfName = 'MeloongCore.OneOf' + $BT + '2<System.Collections.Generic.IEnumerable' + $BT + '1<System.ValueTuple' + $BT + '2<System.String[],System.String>>,System.String>'
    $opImplicit = $null
    foreach ($r in $mod.GetMemberReferences()) {
        if ($r.Name -eq 'op_Implicit' -and $r.DeclaringType.FullName -eq $oneOfName -and $r.Parameters.Count -eq 1) {
            $pt = $r.Parameters[0].ParameterType
            if ($pt -is [Mono.Cecil.GenericParameter] -and $pt.Position -eq 0) { $opImplicit = $r; break }
        }
    }
    if ($null -eq $opImplicit) { throw '找不到 OneOf op_Implicit 引用' }

    $nullableName = 'System.Nullable' + $BT + '1<' + $oneOfName + '>'
    $nullableCtor = $null
    foreach ($r in $mod.GetMemberReferences()) {
        if ($r.Name -eq '.ctor' -and $r.DeclaringType.FullName -eq $nullableName -and $r.Parameters.Count -eq 1) { $nullableCtor = $r; break }
    }
    if ($null -eq $nullableCtor) { throw '找不到 Nullable 构造引用' }

    $newInsList = New-Object System.Collections.ArrayList
    function AddI([object]$ins) { $script:newInsList.Add($ins) | Out-Null }
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, '选择整合包压缩文件'))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Newarr, [Mono.Cecil.TypeReference]$tupleType))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Dup))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_3))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Newarr, [Mono.Cecil.TypeReference]$mod.TypeSystem.String))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Dup))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'rar'))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Dup))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'zip'))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Dup))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'mrpack'))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldstr, '整合包文件'))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Newobj, [Mono.Cecil.MethodReference]$tupleCtor))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stelem_Any, [Mono.Cecil.TypeReference]$tupleType))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$opImplicit))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Newobj, [Mono.Cecil.MethodReference]$nullableCtor))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$selectFile))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$gim))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stloc, [Mono.Cecil.Cil.VariableDefinition]$strVar))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$strVar))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$isNullEmpty))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Brtrue_S, [Mono.Cecil.Cil.Instruction]$retC))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Newobj, [Mono.Cecil.MethodReference]$closureCtor))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stloc, [Mono.Cecil.Cil.VariableDefinition]$bodyC.Variables[0]))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$bodyC.Variables[0]))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$strVar))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stfld, [Mono.Cecil.FieldReference]$closureField))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldloc, [Mono.Cecil.Cil.VariableDefinition]$bodyC.Variables[0]))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldftn, [Mono.Cecil.MethodReference]$closureLambda))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Newobj, [Mono.Cecil.MethodReference]$actionCtor))
    AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, [Mono.Cecil.MethodReference]$runInThread))

    foreach ($i in $newInsList) { $ilC.InsertBefore($retC, [Mono.Cecil.Cil.Instruction]$i) }

    $asm.Write($OutputExe)
    Write-Host "[2/2] 已恢复整合包安装功能" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $patchedA) { Remove-Item -LiteralPath $patchedA -Force -ErrorAction SilentlyContinue }
    if ($resDir -and (Test-Path -LiteralPath $resDir)) { Remove-Item -LiteralPath $resDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host ("输出文件: " + (Resolve-Path -LiteralPath $OutputExe))
Write-Host ("SHA256  : " + (Get-FileHash -LiteralPath $OutputExe -Algorithm SHA256).Hash)
Write-Host "修复完成。" -ForegroundColor Cyan
exit 0
